// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CARBONYL_SRC_BROWSER_DUMP_TEXT_HANDLER_H_
#define CARBONYL_SRC_BROWSER_DUMP_TEXT_HANDLER_H_

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "carbonyl/src/browser/export.h"
#include "content/public/browser/web_contents_observer.h"

namespace content {
class WebContents;
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
  static void StartFor(content::WebContents* web_contents);

 private:
  DumpTextHandler(content::WebContents* web_contents,
                  Mode mode,
                  int idle_ms,
                  int max_wait_ms);
  ~DumpTextHandler() override;

  // content::WebContentsObserver:
  void DocumentOnLoadCompletedInPrimaryMainFrame() override;
  void WebContentsDestroyed() override;

  void OnIdleElapsed();
  void OnMaxWaitElapsed();
  void OnJavaScriptResult(base::Value result);
  void EmitAndExit(const std::string& text, int exit_code);

  Mode mode_;
  int idle_ms_;
  int max_wait_ms_;
  bool finished_ = false;
  bool load_complete_ = false;

  base::OneShotTimer idle_timer_;
  base::OneShotTimer max_wait_timer_;
};

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_DUMP_TEXT_HANDLER_H_
