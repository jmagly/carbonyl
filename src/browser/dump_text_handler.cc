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
#include <string>
#include <utility>

#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "carbonyl/src/browser/accessibility_handler.h"
#include "content/public/browser/browser_task_traits.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "headless/lib/browser/headless_browser_impl.h"
#include "net/base/net_errors.h"

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
