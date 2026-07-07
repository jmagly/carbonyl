// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef CARBONYL_SRC_BROWSER_JAVASCRIPT_DIALOG_MANAGER_H_
#define CARBONYL_SRC_BROWSER_JAVASCRIPT_DIALOG_MANAGER_H_

#include <string>

#include "carbonyl/src/browser/export.h"
#include "content/public/browser/javascript_dialog_manager.h"

namespace carbonyl {

// Headless JavaScript dialog policy for Carbonyl's primary WebContents.
//
// Carbonyl has no native modal UI surface. Rather than leaving
// window.alert/confirm/prompt blocked forever, this manager applies a
// deterministic automation-safe policy:
//   alert: acknowledge
//   confirm: accept
//   prompt: accept with the page-provided default text
//   beforeunload: proceed
class CARBONYL_BRIDGE_EXPORT CarbonylJavaScriptDialogManager final
    : public content::JavaScriptDialogManager {
 public:
  CarbonylJavaScriptDialogManager();
  ~CarbonylJavaScriptDialogManager() override;

  CarbonylJavaScriptDialogManager(
      const CarbonylJavaScriptDialogManager&) = delete;
  CarbonylJavaScriptDialogManager& operator=(
      const CarbonylJavaScriptDialogManager&) = delete;

  void RunJavaScriptDialog(content::WebContents* web_contents,
                           content::RenderFrameHost* render_frame_host,
                           content::JavaScriptDialogType dialog_type,
                           const std::u16string& message_text,
                           const std::u16string& default_prompt_text,
                           DialogClosedCallback callback,
                           bool* did_suppress_message) override;

  void RunBeforeUnloadDialog(content::WebContents* web_contents,
                             content::RenderFrameHost* render_frame_host,
                             bool is_reload,
                             DialogClosedCallback callback) override;

  bool HandleJavaScriptDialog(content::WebContents* web_contents,
                              bool accept,
                              const std::u16string* prompt_override) override;

  void CancelDialogs(content::WebContents* web_contents,
                     bool reset_state) override;
};

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_JAVASCRIPT_DIALOG_MANAGER_H_
