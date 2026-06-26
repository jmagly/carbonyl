// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// See `src/browser/bridge.rs::main()` for the Rust-side companion that
// propagates `CARBONYL_ENV_SHELL_MODE=1` to chromium subprocesses when
// `--dump-text` is selected, preventing renderer-thread spin-up that
// would otherwise interleave ANSI escapes into the dump output (#88).

#include "carbonyl/src/browser/dump_text_handler.h"

#include <cstdlib>
#include <iostream>
#include <optional>
#include <string>
#include <utility>

#include "base/command_line.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "carbonyl/src/browser/accessibility_handler.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/browser/web_contents.h"
#include "headless/lib/browser/headless_browser_impl.h"
#include "net/base/load_flags.h"
#include "net/base/net_errors.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "third_party/pdfium/public/fpdf_text.h"
#include "third_party/pdfium/public/fpdfview.h"
#include "url/gurl.h"

namespace carbonyl {

namespace {

// The user-facing CLI switch names — parsed by `src/cli/cli.rs` on the
// Rust side, AND read directly here on the C++ side. They appear on
// `base::CommandLine::ForCurrentProcess()` for free because the user
// typed them on the command line; no argv re-injection needed.
constexpr char kSwitchDumpText[] = "dump-text";
constexpr char kSwitchDumpIdle[] = "idle";
constexpr char kSwitchDumpMaxWait[] = "max-wait";

// Default timings — match the Rust CLI defaults in src/cli/cli.rs.
constexpr int kDefaultIdleMs = 500;
constexpr int kDefaultMaxWaitMs = 30000;
constexpr size_t kMaxPdfBytes =
    network::SimpleURLLoader::kMaxBoundedStringDownloadSize;

// Isolated-world ID for the extraction script. The content layer caps
// embedder world IDs at `ISOLATED_WORLD_ID_MAX = 11` (private constant in
// render_frame_host_impl.cc; the CHECK fires hard if we exceed it). 0 is
// the main world. carbonyl's headless build does not load extensions, so
// any value 1..11 is safe; we pick 1.
constexpr int32_t kCarbonylDumpTextWorldId = 1;

// At most one handler per process. The chromium bootstrap calls StartFor
// once after the initial WebContents is built; this guard tolerates a
// double-install without leaking state.
bool g_handler_started = false;

DumpTextHandler::Mode ParseMode(const std::string& raw) {
  // Empty value (just `--carbonyl-dump-text` with no `=`) defaults to
  // innertext, matching how the Rust CLI emits this switch.
  if (raw.empty() || raw == "innertext" || raw == "inner-text") {
    return DumpTextHandler::Mode::kInnerText;
  }
  if (raw == "accessibility" || raw == "a11y" || raw == "ax") {
    return DumpTextHandler::Mode::kAccessibility;
  }
  if (raw == "raw-dom" || raw == "rawdom" || raw == "dom" ||
      raw == "outerhtml") {
    return DumpTextHandler::Mode::kRawDom;
  }
  LOG(WARNING) << "carbonyl --dump-text: unknown mode '" << raw
               << "', falling back to innertext";
  return DumpTextHandler::Mode::kInnerText;
}

int ParsePositiveInt(const std::string& raw, int fallback) {
  int value = 0;
  if (base::StringToInt(raw, &value) && value > 0) {
    return value;
  }
  return fallback;
}

// JS expression for the isolated-world eval modes. Each must return a
// string when evaluated in an isolated world; ExecuteJavaScriptInIsolatedWorld
// delivers the result through the callback as a base::Value.
//
// kAccessibility is NOT handled here: it takes the browser-process AX
// snapshot path in OnIdleElapsed (issue #4 / #90), not a JS eval. This
// function is only consulted for the JS-eval modes.
const char* ScriptForMode(DumpTextHandler::Mode mode) {
  switch (mode) {
    case DumpTextHandler::Mode::kInnerText:
      return "document.body ? document.body.innerText : ''";
    case DumpTextHandler::Mode::kRawDom:
      return
          "(document.doctype "
          "? new XMLSerializer().serializeToString(document.doctype) + '\\n' "
          ": '') + document.documentElement.outerHTML";
    case DumpTextHandler::Mode::kAccessibility:
      // Unreachable: kAccessibility is intercepted in OnIdleElapsed and
      // never routed through the JS-eval path. Kept for switch
      // exhaustiveness; returns a benign empty expression.
      return "''";
  }
  return "''";
}

const char* EmbeddedPdfUrlsScript() {
  return
      "Array.from(document.querySelectorAll("
      "  'iframe[src], embed[src], object[data]'"
      ")).map((element) => {"
      "  const raw = element.getAttribute('src') ||"
      "      element.getAttribute('data') || '';"
      "  if (!raw) return '';"
      "  let href = '';"
      "  try { href = new URL(raw, document.baseURI).href; }"
      "  catch (_) { return ''; }"
      "  const type = (element.getAttribute('type') || '').toLowerCase();"
      "  const path = new URL(href).pathname.toLowerCase();"
      "  return (type === 'application/pdf' || path.endsWith('.pdf'))"
      "      ? href : '';"
      "}).filter(Boolean).join('\\n')";
}

bool LooksLikePdfUrl(const GURL& url) {
  return url.is_valid() && url.SchemeIsHTTPOrHTTPS() &&
         base::EndsWith(url.ExtractFileName(), ".pdf",
                        base::CompareCase::INSENSITIVE_ASCII);
}

std::string ExtractPdfText(base::span<const uint8_t> pdf_data) {
  FPDF_InitLibrary();
  FPDF_DOCUMENT document =
      FPDF_LoadMemDocument64(pdf_data.data(), pdf_data.size(), nullptr);
  std::u16string text;
  if (document) {
    const int page_count = FPDF_GetPageCount(document);
    for (int page_index = 0; page_index < page_count; ++page_index) {
      FPDF_PAGE page = FPDF_LoadPage(document, page_index);
      if (!page) {
        continue;
      }
      FPDF_TEXTPAGE text_page = FPDFText_LoadPage(page);
      if (!text_page) {
        FPDF_ClosePage(page);
        continue;
      }
      const int char_count = FPDFText_CountChars(text_page);
      if (char_count <= 0) {
        FPDFText_ClosePage(text_page);
        FPDF_ClosePage(page);
        continue;
      }
      if (!text.empty() && text.back() != u'\n') {
        text.push_back(u'\n');
      }
      text.reserve(text.size() + char_count);
      for (int i = 0; i < char_count; ++i) {
        const unsigned int char_code = FPDFText_GetUnicode(text_page, i);
        if (char_code) {
          text.push_back(static_cast<char16_t>(char_code));
        }
      }
      FPDFText_ClosePage(text_page);
      FPDF_ClosePage(page);
    }
    FPDF_CloseDocument(document);
  }
  FPDF_DestroyLibrary();
  return base::UTF16ToUTF8(text);
}

}  // namespace

// static
bool DumpTextHandler::IsRequested() {
  return base::CommandLine::ForCurrentProcess()->HasSwitch(kSwitchDumpText);
}

// static
void DumpTextHandler::StartFor(content::WebContents* web_contents,
                               headless::HeadlessBrowser* browser) {
  if (g_handler_started || !web_contents || !browser || !IsRequested()) {
    return;
  }
  g_handler_started = true;

  const auto* cmd = base::CommandLine::ForCurrentProcess();
  Mode mode = ParseMode(cmd->GetSwitchValueASCII(kSwitchDumpText));
  int idle_ms =
      ParsePositiveInt(cmd->GetSwitchValueASCII(kSwitchDumpIdle),
                       kDefaultIdleMs);
  int max_wait_ms =
      ParsePositiveInt(cmd->GetSwitchValueASCII(kSwitchDumpMaxWait),
                       kDefaultMaxWaitMs);

  // Self-owned: deleted on WebContentsDestroyed or as part of the chromium
  // teardown chain that ShutdownWithExitCode triggers (which destroys the
  // WebContents, which fires our WebContentsObserver::WebContentsDestroyed,
  // which `delete this`'s).
  new DumpTextHandler(web_contents, browser, mode, idle_ms, max_wait_ms);
}

DumpTextHandler::DumpTextHandler(content::WebContents* web_contents,
                                 headless::HeadlessBrowser* browser,
                                 Mode mode,
                                 int idle_ms,
                                 int max_wait_ms)
    : browser_(browser),
      mode_(mode),
      idle_ms_(idle_ms),
      max_wait_ms_(max_wait_ms) {
  content::WebContentsObserver::Observe(web_contents);

  // Hard timeout — fires if the page never reaches load-complete.
  max_wait_timer_.Start(
      FROM_HERE, base::Milliseconds(max_wait_ms_),
      base::BindOnce(&DumpTextHandler::OnMaxWaitElapsed,
                     base::Unretained(this)));
}

DumpTextHandler::~DumpTextHandler() = default;

void DumpTextHandler::DocumentOnLoadCompletedInPrimaryMainFrame() {
  if (load_complete_ || finished_) {
    return;
  }
  load_complete_ = true;

  // Schedule the idle window. Once it elapses (no further intervening
  // load events), we execute the extraction script.
  idle_timer_.Start(
      FROM_HERE, base::Milliseconds(idle_ms_),
      base::BindOnce(&DumpTextHandler::OnIdleElapsed,
                     base::Unretained(this)));
}

void DumpTextHandler::DidFinishNavigation(
    content::NavigationHandle* navigation_handle) {
  // Track only primary-frame, committed navigations. Sub-frame iframe
  // failures and aborted navigations don't change the dump-text result.
  // Per #91, the goal here is to distinguish "page loaded with no text"
  // (exit 0) from "navigation failed; chromium served an error page"
  // (exit 6).
  if (!navigation_handle->IsInPrimaryMainFrame() ||
      !navigation_handle->HasCommitted()) {
    return;
  }

  const net::Error net_error = navigation_handle->GetNetErrorCode();
  const bool is_error_page = navigation_handle->IsErrorPage();

  if (is_error_page || net_error != net::OK) {
    nav_failed_ = true;
    nav_error_code_ = static_cast<int>(net_error);
  } else {
    // A subsequent navigation succeeded (e.g. redirect to a real page);
    // clear any prior failure so the success path runs.
    nav_failed_ = false;
    nav_error_code_ = 0;
  }
}

void DumpTextHandler::WebContentsDestroyed() {
  // Two paths land here:
  //   (1) Unexpected renderer destruction before extraction completed —
  //       we have not yet called EmitAndExit, so finished_ is false.
  //       Shut down with a non-zero exit code.
  //   (2) Orderly teardown initiated by our own ShutdownWithExitCode call
  //       in EmitAndExit — finished_ is true, the exit code is already
  //       latched on the browser. Just self-delete and return.
  const bool unexpected = !finished_;
  finished_ = true;
  idle_timer_.Stop();
  max_wait_timer_.Stop();
  if (unexpected) {
    LOG(ERROR) << "carbonyl --dump-text: WebContents destroyed before "
                  "extraction completed";
    if (browser_) {
      static_cast<headless::HeadlessBrowserImpl*>(browser_)
          ->ShutdownWithExitCode(3);
    }
  }
  delete this;
}

void DumpTextHandler::OnIdleElapsed() {
  if (finished_) {
    return;
  }

  // Per #91: if the primary-frame navigation that just completed was a
  // chromium error page or had a non-OK net::Error, skip JS extraction
  // and exit with code 6. Otherwise the extractor would yield the empty
  // body of the styled chrome-error page and mask the failure as exit 0.
  if (nav_failed_) {
    // net::ErrorToString already prepends "net::"; don't double it (#97).
    LOG(WARNING) << "carbonyl --dump-text: navigation failed ("
                 << net::ErrorToString(nav_error_code_) << "); exit 6";
    EmitAndExit(std::string(), 6);
    return;
  }

  // Accessibility mode (#4 / #90): use the browser-process AX snapshot
  // rather than an isolated-world JS eval. AccessibilityHandler is
  // installed unconditionally in OnBrowserStart (chromium patch 0028) and
  // forces ui::kAXModeWebContentsOnly, so by the time the load+idle window
  // has elapsed the tree is populated. GetTreeJSON() is synchronous, runs
  // on this (UI) thread, never returns nullptr, and yields the sentinel
  // {"error":"no_tree"} on any failure path. The returned C string is heap
  // allocated and must be released via carbonyl_free_string().
  if (mode_ == Mode::kAccessibility) {
    const char* tree_json = AccessibilityHandler::GetTreeJSON();
    std::string out = tree_json ? tree_json : "";
    carbonyl_free_string(tree_json);
    EmitAndExit(out, 0);
    return;
  }

  auto* rfh = web_contents() ? web_contents()->GetPrimaryMainFrame() : nullptr;
  if (!rfh) {
    EmitAndExit(std::string(), 4);
    return;
  }

  const std::string script_utf8 = ScriptForMode(mode_);
  rfh->ExecuteJavaScriptInIsolatedWorld(
      base::UTF8ToUTF16(script_utf8),
      base::BindOnce(&DumpTextHandler::OnJavaScriptResult,
                     base::Unretained(this)),
      kCarbonylDumpTextWorldId);
}

void DumpTextHandler::OnMaxWaitElapsed() {
  if (finished_) {
    return;
  }
  if (TryFetchPdfOnTimeout()) {
    return;
  }
  LOG(ERROR) << "carbonyl --dump-text: --max-wait elapsed (" << max_wait_ms_
             << " ms); page never finished loading";
  EmitAndExit(std::string(), 5);
}

void DumpTextHandler::OnJavaScriptResult(base::Value result) {
  if (finished_) {
    return;
  }
  std::string text;
  if (result.is_string()) {
    text = result.GetString();
  } else if (!result.is_none()) {
    // Mode scripts always return strings; anything else means the page's
    // global state interfered. Stringify defensively.
    text = result.DebugString();
  }
  if (TryFetchEmbeddedPdfs(text)) {
    return;
  }
  EmitAndExit(text, 0);
}

bool DumpTextHandler::TryFetchEmbeddedPdfs(const std::string& page_text) {
  if (mode_ == Mode::kAccessibility || !web_contents()) {
    return false;
  }

  auto* rfh = web_contents()->GetPrimaryMainFrame();
  if (!rfh) {
    return false;
  }

  pending_text_ = page_text;
  pending_pdf_urls_.clear();
  pending_pdf_index_ = 0;
  max_wait_timer_.Stop();

  rfh->ExecuteJavaScriptInIsolatedWorld(
      base::UTF8ToUTF16(EmbeddedPdfUrlsScript()),
      base::BindOnce(&DumpTextHandler::OnEmbeddedPdfUrlsResult,
                     base::Unretained(this)),
      kCarbonylDumpTextWorldId);
  return true;
}

void DumpTextHandler::OnEmbeddedPdfUrlsResult(base::Value result) {
  if (finished_) {
    return;
  }

  if (result.is_string()) {
    for (const auto& line : base::SplitString(
             result.GetString(), "\n", base::TRIM_WHITESPACE,
             base::SPLIT_WANT_NONEMPTY)) {
      GURL url(line);
      if (LooksLikePdfUrl(url)) {
        pending_pdf_urls_.push_back(url.spec());
      }
    }
  }

  FetchNextEmbeddedPdf();
}

void DumpTextHandler::FetchNextEmbeddedPdf() {
  if (finished_) {
    return;
  }
  if (pending_pdf_index_ >= pending_pdf_urls_.size()) {
    EmitAndExit(pending_text_, 0);
    return;
  }

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(pending_pdf_urls_[pending_pdf_index_]);
  request->load_flags = net::LOAD_DISABLE_CACHE;
  auto loader = network::SimpleURLLoader::Create(
      std::move(request), net::DefineNetworkTrafficAnnotation(
                              "carbonyl_dump_text_embedded_pdf",
                              R"(
        semantics {
          sender: "Carbonyl dump-text embedded PDF fallback"
          description:
            "Fetches PDF URLs embedded in the current document so Carbonyl can "
            "extract PDF text when Chromium headless does not render those "
            "iframes or objects into terminal-visible content."
          trigger:
            "The user invoked carbonyl --dump-text on a document containing "
            "iframe, embed, or object elements that reference PDF URLs."
          data: "The requested embedded PDF response body."
          destination: WEBSITE
        }
        policy {
          cookies_allowed: YES
          cookies_store: "The active Chromium profile cookie jar."
          setting:
            "No separate setting. This only runs for an explicit user "
            "--dump-text navigation."
          policy_exception_justification:
            "Carbonyl is a command-line browser. Enterprise policy is not "
            "implemented for this Carbonyl-specific diagnostic path."
        })"));
  network::SimpleURLLoader* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      web_contents()
          ->GetBrowserContext()
          ->GetDefaultStoragePartition()
          ->GetURLLoaderFactoryForBrowserProcess()
          .get(),
      base::BindOnce(&DumpTextHandler::OnEmbeddedPdfDownloaded,
                     base::Unretained(this), std::move(loader)),
      kMaxPdfBytes);
}

void DumpTextHandler::OnEmbeddedPdfDownloaded(
    std::unique_ptr<network::SimpleURLLoader> loader,
    std::optional<std::string> body) {
  if (finished_) {
    return;
  }
  if (body) {
    const std::string text = ExtractPdfText(base::as_byte_span(*body));
    if (!text.empty()) {
      if (!pending_text_.empty() && pending_text_.back() != '\n') {
        pending_text_.push_back('\n');
      }
      pending_text_ += text;
    } else {
      LOG(WARNING)
          << "carbonyl --dump-text: embedded PDF fallback extracted no text from "
          << pending_pdf_urls_[pending_pdf_index_];
    }
  } else {
    LOG(WARNING) << "carbonyl --dump-text: embedded PDF fallback failed to fetch "
                 << pending_pdf_urls_[pending_pdf_index_] << " (net "
                 << loader->NetError() << ")";
  }

  ++pending_pdf_index_;
  FetchNextEmbeddedPdf();
}

bool DumpTextHandler::TryFetchPdfOnTimeout() {
  if (mode_ == Mode::kAccessibility || !web_contents()) {
    return false;
  }
  const GURL url = web_contents()->GetVisibleURL();
  if (!LooksLikePdfUrl(url)) {
    return false;
  }

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = url;
  request->load_flags = net::LOAD_DISABLE_CACHE;
  auto loader = network::SimpleURLLoader::Create(
      std::move(request), net::DefineNetworkTrafficAnnotation(
                              "carbonyl_dump_text_pdf",
                              R"(
        semantics {
          sender: "Carbonyl dump-text PDF fallback"
          description:
            "Fetches the direct PDF URL currently being loaded so Carbonyl can "
            "extract text through PDFium when Chromium headless does not "
            "commit an in-browser PDF viewer document."
          trigger:
            "The user invoked carbonyl --dump-text on a URL whose path ends "
            "in .pdf, and the normal page load timed out."
          data: "The requested PDF response body."
          destination: WEBSITE
        }
        policy {
          cookies_allowed: YES
          cookies_store: "The active Chromium profile cookie jar."
          setting:
            "No separate setting. This only runs for an explicit user "
            "--dump-text navigation."
          policy_exception_justification:
            "Carbonyl is a command-line browser. Enterprise policy is not "
            "implemented for this Carbonyl-specific diagnostic path."
        })"));
  network::SimpleURLLoader* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      web_contents()
          ->GetBrowserContext()
          ->GetDefaultStoragePartition()
          ->GetURLLoaderFactoryForBrowserProcess()
          .get(),
      base::BindOnce(&DumpTextHandler::OnPdfDownloaded, base::Unretained(this),
                     std::move(loader)),
      kMaxPdfBytes);
  return true;
}

void DumpTextHandler::OnPdfDownloaded(
    std::unique_ptr<network::SimpleURLLoader> loader,
    std::optional<std::string> body) {
  if (finished_) {
    return;
  }
  if (!body) {
    LOG(ERROR) << "carbonyl --dump-text: direct PDF fallback failed to fetch "
               << web_contents()->GetVisibleURL() << " (net "
               << loader->NetError() << ")";
    EmitAndExit(std::string(), 5);
    return;
  }

  const std::string text = ExtractPdfText(base::as_byte_span(*body));
  if (text.empty()) {
    LOG(ERROR) << "carbonyl --dump-text: direct PDF fallback extracted no text";
    EmitAndExit(std::string(), 5);
    return;
  }
  EmitAndExit(text, 0);
}

void DumpTextHandler::EmitAndExit(const std::string& text, int exit_code) {
  finished_ = true;
  idle_timer_.Stop();
  max_wait_timer_.Stop();
  if (!text.empty()) {
    std::cout << text << std::endl;
  }
  std::cout.flush();

  // Initiate chromium's orderly shutdown (per #93) instead of std::_Exit.
  // ShutdownWithExitCode posts a quit closure on the UI message loop;
  // the destructor chain that follows tears down the WebContents — which
  // fires our WebContentsObserver::WebContentsDestroyed and self-deletes
  // this handler. We MUST post to the UI thread because this method runs
  // on the JS-result callback (which may not be on the UI thread).
  if (browser_) {
    content::GetUIThreadTaskRunner({})->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](headless::HeadlessBrowser* browser, int code) {
              static_cast<headless::HeadlessBrowserImpl*>(browser)
                  ->ShutdownWithExitCode(code);
            },
            browser_, exit_code));
  } else {
    // Fallback if we somehow lost the browser pointer (shouldn't happen
    // — StartFor requires a non-null browser). Preserve exit-code
    // propagation by falling back to _Exit; logged so the regression is
    // visible.
    LOG(ERROR) << "carbonyl --dump-text: browser pointer null at exit; "
                  "falling back to _Exit (regression vs #93)";
    std::_Exit(exit_code);
  }
}

}  // namespace carbonyl
