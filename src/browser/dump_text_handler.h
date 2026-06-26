// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CARBONYL_SRC_BROWSER_DUMP_TEXT_HANDLER_H_
#define CARBONYL_SRC_BROWSER_DUMP_TEXT_HANDLER_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "carbonyl/src/browser/export.h"
#include "content/public/browser/web_contents_observer.h"

namespace content {
class WebContents;
}

namespace headless {
class HeadlessBrowser;
}

namespace network {
class SimpleURLLoader;
}

namespace carbonyl {

// Implements `--dump-text[=<mode>]` (issue #88) without going through the
// headless command-handler infrastructure (which carbonyl cannot enable due
// to `headless_use_embedded_resources = true`).
//
// On `DocumentOnLoadCompletedInPrimaryMainFrame`, the handler schedules an
// idle window (default 500 ms; tunable via `--idle=<ms>`). When the idle
// timer fires, it executes a mode-specific JavaScript expression in an
// isolated world on the primary main frame and writes the result to stdout
// before terminating the process.
//
// A hard timeout (default 30 s; tunable via `--max-wait=<ms>`) terminates
// the process with a non-zero exit code if the page never reaches the
// load-complete state.
//
// Termination uses `HeadlessBrowserImpl::ShutdownWithExitCode()` (per #93),
// which runs chromium's orderly teardown — RenderFrameHost / WebContents
// destructors, viz compositor cleanup, etc. The earlier `std::_Exit` path
// was fast but produced a `WebFrame LEAKED` stderr line on every invocation
// and could leave OS-level resources (temp dirs, sockets) un-cleaned.
//
// The handler self-deletes when the WebContents is destroyed or after the
// result has been emitted, mirroring the lifetime convention of
// `HeadlessCommandHandler`.
class CARBONYL_BRIDGE_EXPORT DumpTextHandler
    : public content::WebContentsObserver {
 public:
  enum class Mode {
    kInnerText,       // document.body.innerText
    kAccessibility,   // accessibility-tree snapshot (depends on #4)
    kRawDom,          // document.documentElement.outerHTML
  };

  // Returns true if any carbonyl dump-text command-line switch is present.
  // Read by the headless_shell bootstrap to decide whether to install the
  // handler on the freshly-built WebContents.
  static bool IsRequested();

  // Install a handler on the given WebContents and start the idle/timeout
  // timers. Lifetime: self-owned — the handler deletes itself when finished.
  // Safe to call once per process; subsequent calls are ignored.
  //
  // `browser` is the HeadlessBrowser the WebContents belongs to. It is
  // captured for the ordered-shutdown path (#93) and downcast to
  // `headless::HeadlessBrowserImpl` to call `ShutdownWithExitCode()`. The
  // pointer must outlive this handler — which it does, because the browser
  // owns the WebContents that drives this handler's lifecycle.
  static void StartFor(content::WebContents* web_contents,
                       headless::HeadlessBrowser* browser);

 private:
  DumpTextHandler(content::WebContents* web_contents,
                  headless::HeadlessBrowser* browser,
                  Mode mode,
                  int idle_ms,
                  int max_wait_ms);
  ~DumpTextHandler() override;

  // content::WebContentsObserver:
  void DocumentOnLoadCompletedInPrimaryMainFrame() override;
  void DidFinishNavigation(
      content::NavigationHandle* navigation_handle) override;
  void WebContentsDestroyed() override;

  void OnIdleElapsed();
  void OnMaxWaitElapsed();
  void OnJavaScriptResult(base::Value result);
  bool TryFetchEmbeddedPdfs(const std::string& page_text);
  void OnEmbeddedPdfUrlsResult(base::Value result);
  void FetchNextEmbeddedPdf();
  void OnEmbeddedPdfDownloaded(
      std::unique_ptr<network::SimpleURLLoader> loader,
      std::optional<std::string> body);
  bool TryFetchPdfOnTimeout();
  void OnPdfDownloaded(std::unique_ptr<network::SimpleURLLoader> loader,
                       std::optional<std::string> body);
  void EmitAndExit(const std::string& text, int exit_code);

  // RAW_PTR_EXCLUSION: HeadlessBrowser lifetime is owned by chromium's
  // browser-main loop, not by carbonyl, and outlives this observer by
  // construction (we are torn down when the browser shuts down the
  // WebContents we observe). raw_ptr would add hash-map churn for no
  // safety gain in this single-process / single-instance scenario.
  RAW_PTR_EXCLUSION headless::HeadlessBrowser* browser_;

  Mode mode_;
  int idle_ms_;
  int max_wait_ms_;
  bool finished_ = false;
  bool load_complete_ = false;

  // Set by DidFinishNavigation when the latest primary-frame commit was a
  // chromium error page or had a non-OK net::Error code (per #91). Read
  // by OnIdleElapsed to decide whether to skip JS extraction and emit
  // exit code 6 instead of 0.
  bool nav_failed_ = false;
  int nav_error_code_ = 0;  // net::Error (negative on failure, 0 = net::OK)

  std::string pending_text_;
  std::vector<std::string> pending_pdf_urls_;
  size_t pending_pdf_index_ = 0;

  base::OneShotTimer idle_timer_;
  base::OneShotTimer max_wait_timer_;
};

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_DUMP_TEXT_HANDLER_H_
