// Copyright 2026 The Carbonyl Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "carbonyl/src/browser/javascript_dialog_manager.h"

#include <utility>

#include "base/logging.h"
#include "base/strings/utf_string_conversions.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/javascript_dialog_type.h"

namespace carbonyl {

namespace {

const char* DialogTypeName(content::JavaScriptDialogType type) {
  switch (type) {
    case content::JAVASCRIPT_DIALOG_TYPE_ALERT:
      return "alert";
    case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
      return "confirm";
    case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
      return "prompt";
  }
}

}  // namespace

CarbonylJavaScriptDialogManager::CarbonylJavaScriptDialogManager() = default;
CarbonylJavaScriptDialogManager::~CarbonylJavaScriptDialogManager() = default;

void CarbonylJavaScriptDialogManager::RunJavaScriptDialog(
    content::WebContents* web_contents,
    content::RenderFrameHost* render_frame_host,
    content::JavaScriptDialogType dialog_type,
    const std::u16string& message_text,
    const std::u16string& default_prompt_text,
    DialogClosedCallback callback,
    bool* did_suppress_message) {
  if (did_suppress_message) {
    *did_suppress_message = false;
  }

  LOG(INFO) << "carbonyl: auto-accepting JavaScript "
            << DialogTypeName(dialog_type) << " dialog: "
            << base::UTF16ToUTF8(message_text);

  const std::u16string user_input =
      dialog_type == content::JAVASCRIPT_DIALOG_TYPE_PROMPT
          ? default_prompt_text
          : std::u16string();
  std::move(callback).Run(/*success=*/true, user_input);
}

void CarbonylJavaScriptDialogManager::RunBeforeUnloadDialog(
    content::WebContents* web_contents,
    content::RenderFrameHost* render_frame_host,
    bool is_reload,
    DialogClosedCallback callback) {
  LOG(INFO) << "carbonyl: auto-accepting beforeunload dialog";
  std::move(callback).Run(/*success=*/true, std::u16string());
}

bool CarbonylJavaScriptDialogManager::HandleJavaScriptDialog(
    content::WebContents* web_contents,
    bool accept,
    const std::u16string* prompt_override) {
  return false;
}

void CarbonylJavaScriptDialogManager::CancelDialogs(
    content::WebContents* web_contents,
    bool reset_state) {}

}  // namespace carbonyl
