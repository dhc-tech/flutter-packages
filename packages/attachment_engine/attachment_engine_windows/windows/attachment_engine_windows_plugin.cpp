// Copyright 2026 DHC
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine — see
// attachment_engine_windows_plugin.h for details. It mirrors the
// `RegisterWithRegistrar` entry point shape that Flutter's Windows plugin
// template (and the generated `generated_plugin_registrant.cc`) expects.

#include "attachment_engine_windows_plugin.h"

#include <flutter/plugin_registrar_windows.h>

namespace attachment_engine_windows {

// static
void AttachmentEngineWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<AttachmentEngineWindowsPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

AttachmentEngineWindowsPlugin::AttachmentEngineWindowsPlugin(
    flutter::PluginRegistrarWindows* registrar) {
  // `registrar->GetView()->GetNativeWindow()` returns the top-level HWND
  // for this Flutter view; the Share and Video channels need it (Share for
  // IDataTransferManagerInterop::GetForWindow/ShowShareUIForWindow, Video
  // for attaching a child HWND surface for the Media Foundation video
  // sink).
  HWND top_level_window = registrar->GetView()->GetNativeWindow();

  share_channel_ = std::make_unique<ShareChannel>(
      registrar->messenger(), top_level_window);

  audio_channel_ =
      std::make_unique<AudioChannel>(registrar->messenger());

  video_channel_ = std::make_unique<VideoChannel>(
      registrar, top_level_window);
}

AttachmentEngineWindowsPlugin::~AttachmentEngineWindowsPlugin() = default;

}  // namespace attachment_engine_windows
