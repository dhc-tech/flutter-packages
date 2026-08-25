// Copyright 2026 DHC
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine — see
// video_channel.h for the documented API and the render-mode-HWND
// embedding tradeoff this implementation makes.

#include "video_channel.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>

#include <flutter/standard_method_codec.h>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::EventChannel;
using flutter::EventSink;
using flutter::MethodCall;
using flutter::MethodResult;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::RuntimeClass;
using Microsoft::WRL::RuntimeClassFlags;

namespace attachment_engine_windows {

namespace {
constexpr char kMethodChannelName[] = "attachment_engine/video";
constexpr char kEventChannelPrefix[] = "attachment_engine/video_events/";
constexpr wchar_t kChildWindowClassName[] =
    L"AttachmentEngineWindowsVideoSurface";
constexpr UINT kProgressTimerMs = 250;

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  const int wlen = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring result(wlen > 0 ? wlen - 1 : 0, L'\0');
  if (wlen > 0) {
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, result.data(), wlen);
  }
  return result;
}

void EnsureWindowClassRegistered(HINSTANCE instance) {
  static bool registered = false;
  if (registered) return;
  WNDCLASSW wc = {};
  wc.lpfnWndProc = DefWindowProcW;
  wc.hInstance = instance;
  wc.lpszClassName = kChildWindowClassName;
  RegisterClassW(&wc);
  registered = true;
}
}  // namespace

class VideoMediaEngineNotify
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          IMFMediaEngineNotify> {
 public:
  using Callback = std::function<void(DWORD)>;
  explicit VideoMediaEngineNotify(Callback callback)
      : callback_(std::move(callback)) {}

  IFACEMETHODIMP EventNotify(DWORD event, DWORD_PTR, DWORD) override {
    callback_(event);
    return S_OK;
  }

 private:
  Callback callback_;
};

class VideoPlayerEntry {
 public:
  VideoPlayerEntry(flutter::BinaryMessenger* messenger, HWND parent_window,
                    const std::string& player_id)
      : player_id_(player_id) {
    EnsureWindowClassRegistered(GetModuleHandleW(nullptr));
    // Render-mode HWND target (see video_channel.h "Embedding tradeoff").
    // Created hidden/zero-sized; `SetLayout` moves and shows it once the
    // Dart-side widget reports real bounds.
    child_hwnd_ = CreateWindowExW(
        0, kChildWindowClassName, L"", WS_CHILD, 0, 0, 0, 0, parent_window,
        nullptr, GetModuleHandleW(nullptr), nullptr);

    event_channel_ = std::make_unique<EventChannel<EncodableValue>>(
        messenger, kEventChannelPrefix + player_id,
        &flutter::StandardMethodCodec::GetInstance());
    auto handler =
        std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
            [this](const EncodableValue*,
                   std::unique_ptr<EventSink<EncodableValue>>&& events)
                -> std::unique_ptr<
                    flutter::StreamHandlerError<EncodableValue>> {
              event_sink_ = std::move(events);
              return nullptr;
            },
            [this](const EncodableValue*)
                -> std::unique_ptr<
                    flutter::StreamHandlerError<EncodableValue>> {
              event_sink_ = nullptr;
              return nullptr;
            });
    event_channel_->SetStreamHandler(std::move(handler));
  }

  ~VideoPlayerEntry() { Dispose(); }

  HRESULT EnsureEngine() {
    if (media_engine_) return S_OK;

    ComPtr<IMFMediaEngineClassFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_MFMediaEngineClassFactory, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&factory));
    if (FAILED(hr)) return hr;

    ComPtr<IMFAttributes> attributes;
    hr = MFCreateAttributes(&attributes, 3);
    if (FAILED(hr)) return hr;

    notify_ = Microsoft::WRL::Make<VideoMediaEngineNotify>(
        [this](DWORD event) { OnMediaEngineEvent(event); });
    hr = attributes->SetUnknown(MF_MEDIA_ENGINE_CALLBACK, notify_.Get());
    if (FAILED(hr)) return hr;
    hr = attributes->SetUINT64(MF_MEDIA_ENGINE_PLAYBACK_HWND,
                                reinterpret_cast<UINT64>(child_hwnd_));
    if (FAILED(hr)) return hr;

    return factory->CreateInstance(0, attributes.Get(), &media_engine_);
  }

  void Load(const std::wstring& path_or_url) {
    if (FAILED(EnsureEngine())) {
      Emit("error");
      return;
    }
    BSTR url = SysAllocString(path_or_url.c_str());
    Emit("buffering");
    media_engine_->SetSource(url);
    SysFreeString(url);
  }

  void Play() {
    if (media_engine_) media_engine_->Play();
    Emit("playing");
  }

  void Pause() {
    if (media_engine_) media_engine_->Pause();
    Emit("paused");
  }

  void Seek(int position_ms) {
    if (media_engine_) media_engine_->SetCurrentTime(position_ms / 1000.0);
  }

  void SetSpeed(double speed) {
    if (media_engine_) media_engine_->SetPlaybackRate(speed);
  }

  void SetVolume(double volume) {
    if (media_engine_) media_engine_->SetVolume(volume);
  }

  // See video_channel.h: keeps the render-mode child HWND aligned with the
  // Dart-side widget's on-screen bounds (physical pixels, relative to the
  // top-level window's client area).
  void SetLayout(int left, int top, int width, int height) {
    if (!child_hwnd_) return;
    SetWindowPos(child_hwnd_, nullptr, left, top, width, height,
                 SWP_NOZORDER | SWP_SHOWWINDOW);
  }

  void Dispose() {
    if (timer_id_ != 0) {
      KillTimer(nullptr, timer_id_);
      timer_id_ = 0;
    }
    if (media_engine_) {
      media_engine_->Shutdown();
      media_engine_.Reset();
    }
    if (child_hwnd_) {
      DestroyWindow(child_hwnd_);
      child_hwnd_ = nullptr;
    }
    event_sink_ = nullptr;
    event_channel_->SetStreamHandler(nullptr);
  }

 private:
  void OnMediaEngineEvent(DWORD event) {
    switch (event) {
      case MF_MEDIA_ENGINE_EVENT_CANPLAY:
        Emit("ready");
        StartProgressLoop();
        break;
      case MF_MEDIA_ENGINE_EVENT_ENDED:
        Emit("completed");
        break;
      case MF_MEDIA_ENGINE_EVENT_ERROR:
        Emit("error");
        break;
      default:
        break;
    }
  }

  void StartProgressLoop() { timer_id_ = SetTimer(nullptr, 0, kProgressTimerMs, nullptr); }

  void Emit(const std::string& state) {
    if (!event_sink_) return;
    EncodableMap map;
    map[EncodableValue("state")] = EncodableValue(state);
    event_sink_->Success(EncodableValue(map));
  }

  void EmitProgress() {
    if (!media_engine_ || !event_sink_) return;
    double position_seconds = 0;
    media_engine_->GetCurrentTime(&position_seconds);
    const double duration_seconds = media_engine_->GetDuration();
    DWORD width = 0, height = 0;
    media_engine_->GetNativeVideoSize(&width, &height);
    EncodableMap map;
    map[EncodableValue("state")] =
        EncodableValue(media_engine_->IsPaused() ? std::string("paused")
                                                  : std::string("playing"));
    map[EncodableValue("positionMs")] =
        EncodableValue(static_cast<int>(position_seconds * 1000));
    map[EncodableValue("durationMs")] =
        EncodableValue(static_cast<int>(duration_seconds * 1000));
    map[EncodableValue("width")] = EncodableValue(static_cast<int>(width));
    map[EncodableValue("height")] = EncodableValue(static_cast<int>(height));
    event_sink_->Success(EncodableValue(map));
  }

  std::string player_id_;
  HWND child_hwnd_ = nullptr;
  ComPtr<IMFMediaEngine> media_engine_;
  ComPtr<VideoMediaEngineNotify> notify_;
  std::unique_ptr<EventChannel<EncodableValue>> event_channel_;
  std::unique_ptr<EventSink<EncodableValue>> event_sink_;
  UINT_PTR timer_id_ = 0;
};

VideoChannel::VideoChannel(flutter::PluginRegistrarWindows* registrar,
                            HWND top_level_window)
    : registrar_(registrar), top_level_window_(top_level_window) {
  MFStartup(MF_VERSION, MFSTARTUP_LITE);

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), kMethodChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

VideoChannel::~VideoChannel() {
  channel_->SetMethodCallHandler(nullptr);
  players_.clear();
}

VideoPlayerEntry* VideoChannel::EnsureEntry(const std::string& player_id) {
  auto it = players_.find(player_id);
  if (it != players_.end()) return it->second.get();
  auto entry = std::make_unique<VideoPlayerEntry>(
      registrar_->messenger(), top_level_window_, player_id);
  auto* raw = entry.get();
  players_[player_id] = std::move(entry);
  return raw;
}

void VideoChannel::DisposeEntry(const std::string& player_id) {
  players_.erase(player_id);
}

void VideoChannel::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (args == nullptr) {
    result->Error("bad_args", "playerId is required");
    return;
  }
  const auto player_id_it = args->find(EncodableValue("playerId"));
  if (player_id_it == args->end() ||
      !std::holds_alternative<std::string>(player_id_it->second)) {
    result->Error("bad_args", "playerId is required");
    return;
  }
  const std::string player_id = std::get<std::string>(player_id_it->second);
  const auto& method = call.method_name();

  if (method == "load") {
    std::wstring source;
    const auto path_it = args->find(EncodableValue("path"));
    const auto url_it = args->find(EncodableValue("url"));
    if (path_it != args->end() &&
        std::holds_alternative<std::string>(path_it->second)) {
      source = Utf8ToWide(std::get<std::string>(path_it->second));
    } else if (url_it != args->end() &&
               std::holds_alternative<std::string>(url_it->second)) {
      source = Utf8ToWide(std::get<std::string>(url_it->second));
    }
    EnsureEntry(player_id)->Load(source);
    result->Success();
  } else if (method == "play") {
    EnsureEntry(player_id)->Play();
    result->Success();
  } else if (method == "pause") {
    EnsureEntry(player_id)->Pause();
    result->Success();
  } else if (method == "seek") {
    int ms = 0;
    const auto it = args->find(EncodableValue("positionMs"));
    if (it != args->end() && std::holds_alternative<int>(it->second)) {
      ms = std::get<int>(it->second);
    }
    EnsureEntry(player_id)->Seek(ms);
    result->Success();
  } else if (method == "setSpeed") {
    double speed = 1.0;
    const auto it = args->find(EncodableValue("speed"));
    if (it != args->end() && std::holds_alternative<double>(it->second)) {
      speed = std::get<double>(it->second);
    }
    EnsureEntry(player_id)->SetSpeed(speed);
    result->Success();
  } else if (method == "setVolume") {
    double volume = 1.0;
    const auto it = args->find(EncodableValue("volume"));
    if (it != args->end() && std::holds_alternative<double>(it->second)) {
      volume = std::get<double>(it->second);
    }
    EnsureEntry(player_id)->SetVolume(volume);
    result->Success();
  } else if (method == "setLayout") {
    auto get_int = [&](const char* key) {
      const auto it = args->find(EncodableValue(std::string(key)));
      if (it != args->end() && std::holds_alternative<int>(it->second)) {
        return std::get<int>(it->second);
      }
      return 0;
    };
    EnsureEntry(player_id)->SetLayout(get_int("left"), get_int("top"),
                                       get_int("width"), get_int("height"));
    result->Success();
  } else if (method == "dispose") {
    DisposeEntry(player_id);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace attachment_engine_windows
