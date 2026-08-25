// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine (no
// native Windows toolchain available here). It implements the real,
// documented Win32 interop for the OS share sheet:
//   - IDataTransferManagerInterop / DataTransferManager:
//     https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-idatatransfermanagerinterop
//     https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-idatatransfermanagerinterop-getforwindow
//     https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-idatatransfermanagerinterop-showshareuiforwindow
// This is the exact mechanism Microsoft's own C++/WinRT "Share content
// source app" samples use to show the native share UI from a classic Win32
// (non-UWP) desktop window: CoCreateInstance(CLSID_DataTransferManager, ...,
// IID_IDataTransferManagerInterop, ...), then GetForWindow(hwnd, ...) to
// obtain a DataTransferManager bound to that HWND, then
// ShowShareUIForWindow(hwnd) to display it. The class documentation notes
// "Windows 8 [UWP apps only]" as the nominal target, but GetForWindow's own
// remarks describe it as the non-UWP-window equivalent of
// DataTransferManager.GetForCurrentView — i.e. it is specifically the
// escape hatch for classic Win32 windows, which is how this is used here.

#ifndef PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_SHARE_CHANNEL_H_
#define PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_SHARE_CHANNEL_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

namespace attachment_engine_windows {

// Replaces `share_plus` on Windows. Method channel name
// "attachment_engine/share", methods "shareFile"/"shareText", matching the
// Android (ShareChannel.kt) and iOS (ShareChannel.swift) contract exactly.
class ShareChannel {
 public:
  ShareChannel(flutter::BinaryMessenger* messenger, HWND top_level_window);
  ~ShareChannel();

  ShareChannel(const ShareChannel&) = delete;
  ShareChannel& operator=(const ShareChannel&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Shows the real DataTransferManager share UI for `path_utf8` (optional)
  // and/or `text_utf8` (optional). Returns an HRESULT; failures are
  // reported back to Dart as a `share_failed` PlatformException.
  HRESULT ShowShareUi(const std::string* path_utf8,
                       const std::string* text_utf8);

  HWND top_level_window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace attachment_engine_windows

#endif  // PACKAGES_ATTACHMENT_ENGINE_WINDOWS_WINDOWS_SHARE_CHANNEL_H_
