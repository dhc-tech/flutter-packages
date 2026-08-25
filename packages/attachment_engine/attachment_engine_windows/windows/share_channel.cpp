// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine — see
// share_channel.h for the documented API this is based on and why it is
// written the way it is.
//
// This uses C++/WinRT (the header-only projection shipped in the Windows
// SDK since 10.0.17134.0 / available standalone via NuGet
// `Microsoft.Windows.CppWinRT`) to interop with the WinRT
// `Windows.ApplicationModel.DataTransfer` types that
// IDataTransferManagerInterop::GetForWindow hands back, mirroring the
// pattern shown in Microsoft's own "Share source app" C++/WinRT samples
// (search "DataTransferManager C++/WinRT sample" on
// github.com/microsoft/Windows-classic-samples).

#include "share_channel.h"

#include <ShObjIdl_core.h>
#include <shlwapi.h>
#include <wrl/client.h>

#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>

#include <flutter/standard_method_codec.h>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;
using Microsoft::WRL::ComPtr;

namespace winrt_dt = winrt::Windows::ApplicationModel::DataTransfer;
namespace winrt_storage = winrt::Windows::Storage;

namespace attachment_engine_windows {

namespace {
constexpr char kChannelName[] = "attachment_engine/share";
}  // namespace

ShareChannel::ShareChannel(flutter::BinaryMessenger* messenger,
                            HWND top_level_window)
    : top_level_window_(top_level_window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

ShareChannel::~ShareChannel() { channel_->SetMethodCallHandler(nullptr); }

void ShareChannel::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());

  if (call.method_name() == "shareFile") {
    if (args == nullptr) {
      result->Error("bad_args", "path is required");
      return;
    }
    const auto path_it = args->find(EncodableValue("path"));
    if (path_it == args->end() ||
        !std::holds_alternative<std::string>(path_it->second)) {
      result->Error("bad_args", "path is required");
      return;
    }
    const std::string path = std::get<std::string>(path_it->second);

    std::string text;
    const std::string* text_ptr = nullptr;
    const auto text_it = args->find(EncodableValue("text"));
    if (text_it != args->end() &&
        std::holds_alternative<std::string>(text_it->second)) {
      text = std::get<std::string>(text_it->second);
      text_ptr = &text;
    }

    const HRESULT hr = ShowShareUi(&path, text_ptr);
    if (FAILED(hr)) {
      result->Error("share_failed", "ShowShareUIForWindow failed",
                     std::make_unique<EncodableValue>(
                         EncodableValue(static_cast<int>(hr))));
      return;
    }
    result->Success();
    return;
  }

  if (call.method_name() == "shareText") {
    std::string text;
    if (args != nullptr) {
      const auto text_it = args->find(EncodableValue("text"));
      if (text_it != args->end() &&
          std::holds_alternative<std::string>(text_it->second)) {
        text = std::get<std::string>(text_it->second);
      }
    }
    const HRESULT hr = ShowShareUi(nullptr, &text);
    if (FAILED(hr)) {
      result->Error("share_failed", "ShowShareUIForWindow failed",
                     std::make_unique<EncodableValue>(
                         EncodableValue(static_cast<int>(hr))));
      return;
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

HRESULT ShareChannel::ShowShareUi(const std::string* path_utf8,
                                   const std::string* text_utf8) {
  // 1. Get the Win32->WinRT interop factory for DataTransferManager.
  ComPtr<IDataTransferManagerInterop> interop;
  HRESULT hr = CoCreateInstance(
      __uuidof(DataTransferManager), nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&interop));
  if (FAILED(hr)) return hr;

  // 2. Bind a DataTransferManager to our top-level HWND.
  winrt_dt::DataTransferManager data_transfer_manager{nullptr};
  hr = interop->GetForWindow(
      top_level_window_,
      winrt::guid_of<winrt_dt::DataTransferManager>(),
      winrt::put_abi(data_transfer_manager));
  if (FAILED(hr)) return hr;

  // 3. Copy the payload by value into the lambda: DataRequested fires
  // asynchronously (after ShowShareUIForWindow returns), so `this`'s call
  // arguments must not be referenced by pointer past this function's return.
  std::wstring path_copy;
  bool has_path = false;
  if (path_utf8 != nullptr) {
    const int wlen = MultiByteToWideChar(CP_UTF8, 0, path_utf8->c_str(), -1,
                                          nullptr, 0);
    path_copy.resize(wlen > 0 ? wlen - 1 : 0);
    if (wlen > 0) {
      MultiByteToWideChar(CP_UTF8, 0, path_utf8->c_str(), -1, path_copy.data(),
                           wlen);
    }
    has_path = true;
  }
  std::wstring text_copy;
  bool has_text = false;
  if (text_utf8 != nullptr && !text_utf8->empty()) {
    const int wlen = MultiByteToWideChar(CP_UTF8, 0, text_utf8->c_str(), -1,
                                          nullptr, 0);
    text_copy.resize(wlen > 0 ? wlen - 1 : 0);
    if (wlen > 0) {
      MultiByteToWideChar(CP_UTF8, 0, text_utf8->c_str(), -1, text_copy.data(),
                           wlen);
    }
    has_text = true;
  }

  // 4. Subscribe to DataRequested: this is where the DataPackage is
  // populated, exactly as in Microsoft's DataTransferManager share-source
  // samples.
  auto token = data_transfer_manager.DataRequested(
      [has_path, path_copy, has_text, text_copy](
          winrt_dt::DataTransferManager const&,
          winrt_dt::DataRequestedEventArgs const& event_args) {
        auto request = event_args.Request();
        auto data = request.Data();
        data.Properties().Title(L"Share");
        try {
          if (has_path) {
            auto file =
                winrt_storage::StorageFile::GetFileFromPathAsync(path_copy)
                    .get();
            auto items =
                winrt::single_threaded_vector<winrt_storage::IStorageItem>();
            items.Append(file);
            data.SetStorageItems(items);
            if (has_text) data.Properties().Description(text_copy);
          } else if (has_text) {
            data.SetText(text_copy);
          }
        } catch (winrt::hresult_error const& e) {
          request.FailWithDisplayText(e.message());
        }
      });
  (void)token;  // Deliberately not revoked: the DataTransferManager and its
                // single-use DataRequested subscription are scoped to this
                // one ShowShareUIForWindow call and are released when
                // `data_transfer_manager` goes out of scope.

  // 5. Actually show the native share flyout for our window.
  return interop->ShowShareUIForWindow(top_level_window_);
}

}  // namespace attachment_engine_windows
