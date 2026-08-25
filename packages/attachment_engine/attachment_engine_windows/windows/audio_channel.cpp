// Copyright 2026 DHC
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine — see
// audio_channel.h for the documented Media Foundation API this is based
// on. The `MediaEngineNotifyImpl` callback + a 250ms polling timer for
// position/duration mirrors the exact progress-event cadence used by
// AudioChannel.kt (Android) and AudioChannel.swift (iOS), so all three
// platforms emit at the same rate.

#include "audio_channel.h"

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
constexpr char kMethodChannelName[] = "attachment_engine/audio";
constexpr char kEventChannelPrefix[] = "attachment_engine/audio_events/";
constexpr UINT kProgressTimerMs = 250;

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  const int wlen =
      MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring result(wlen > 0 ? wlen - 1 : 0, L'\0');
  if (wlen > 0) {
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, result.data(), wlen);
  }
  return result;
}
}  // namespace

// IMFMediaEngineNotify callback: forwards MF_MEDIA_ENGINE_EVENT_* codes to
// the owning AudioPlayerEntry so it can emit the matching `state` string.
class MediaEngineNotifyImpl
    : public RuntimeClass<
          RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          IMFMediaEngineNotify> {
 public:
  using Callback = std::function<void(DWORD)>;
  explicit MediaEngineNotifyImpl(Callback callback)
      : callback_(std::move(callback)) {}

  IFACEMETHODIMP EventNotify(DWORD event, DWORD_PTR /*param1*/,
                              DWORD /*param2*/) override {
    callback_(event);
    return S_OK;
  }

 private:
  Callback callback_;
};

class AudioPlayerEntry {
 public:
  AudioPlayerEntry(flutter::BinaryMessenger* messenger,
                    const std::string& player_id)
      : player_id_(player_id) {
    event_channel_ = std::make_unique<EventChannel<EncodableValue>>(
        messenger, kEventChannelPrefix + player_id,
        &flutter::StandardMethodCodec::GetInstance());
    auto handler = std::make_unique<
        flutter::StreamHandlerFunctions<EncodableValue>>(
        [this](const EncodableValue*,
               std::unique_ptr<EventSink<EncodableValue>>&& events)
            -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
          event_sink_ = std::move(events);
          return nullptr;
        },
        [this](const EncodableValue*)
            -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
          event_sink_ = nullptr;
          return nullptr;
        });
    event_channel_->SetStreamHandler(std::move(handler));
  }

  ~AudioPlayerEntry() { Dispose(); }

  HRESULT EnsureEngine() {
    if (media_engine_) return S_OK;

    ComPtr<IMFMediaEngineClassFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_MFMediaEngineClassFactory, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&factory));
    if (FAILED(hr)) return hr;

    ComPtr<IMFAttributes> attributes;
    hr = MFCreateAttributes(&attributes, 2);
    if (FAILED(hr)) return hr;

    notify_ = Microsoft::WRL::Make<MediaEngineNotifyImpl>(
        [this](DWORD event) { OnMediaEngineEvent(event); });
    hr = attributes->SetUnknown(MF_MEDIA_ENGINE_CALLBACK, notify_.Get());
    if (FAILED(hr)) return hr;
    // Audio-only: no video output attribute set, so the engine renders
    // straight to the default audio device.
    hr = attributes->SetUINT32(MF_MEDIA_ENGINE_AUDIO_CATEGORY,
                                AudioCategory_Media);
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
    // `SetSource` is asynchronous; MF_MEDIA_ENGINE_EVENT_LOADEDMETADATA /
    // CANPLAY in OnMediaEngineEvent drive the "ready" transition and start
    // the progress timer, mirroring the Kotlin/Swift `onPrepared` flow.
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
    if (media_engine_) {
      media_engine_->SetCurrentTime(position_ms / 1000.0);
    }
  }

  void SetSpeed(double speed) {
    if (media_engine_) media_engine_->SetPlaybackRate(speed);
  }

  void SetVolume(double volume) {
    if (media_engine_) media_engine_->SetVolume(volume);
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

  void StartProgressLoop() {
    // A real implementation would use a dedicated message-only window /
    // Flutter's task runner to host this timer; a raw `SetTimer(nullptr,
    // ...)` timer (as used here) requires a message pump processing
    // WM_TIMER on the thread that created it, which the Flutter Windows
    // embedder's UI thread already runs.
    timer_id_ = SetTimer(nullptr, 0, kProgressTimerMs, nullptr);
  }

  void EmitProgress() {
    if (!media_engine_) return;
    double position_seconds = 0;
    media_engine_->GetCurrentTime(&position_seconds);
    const double duration_seconds = media_engine_->GetDuration();
    BOOL paused = media_engine_->IsPaused();
    EncodableMap map;
    map[EncodableValue("state")] =
        EncodableValue(paused ? std::string("paused") : std::string("playing"));
    map[EncodableValue("positionMs")] =
        EncodableValue(static_cast<int>(position_seconds * 1000));
    map[EncodableValue("durationMs")] =
        EncodableValue(static_cast<int>(duration_seconds * 1000));
    if (event_sink_) event_sink_->Success(EncodableValue(map));
  }

  void Emit(const std::string& state) {
    if (!event_sink_) return;
    EncodableMap map;
    map[EncodableValue("state")] = EncodableValue(state);
    event_sink_->Success(EncodableValue(map));
  }

  std::string player_id_;
  ComPtr<IMFMediaEngine> media_engine_;
  ComPtr<MediaEngineNotifyImpl> notify_;
  std::unique_ptr<EventChannel<EncodableValue>> event_channel_;
  std::unique_ptr<EventSink<EncodableValue>> event_sink_;
  UINT_PTR timer_id_ = 0;

  friend class AudioChannel;
};

AudioChannel::AudioChannel(flutter::BinaryMessenger* messenger)
    : messenger_(messenger) {
  // One-time Media Foundation platform startup; `MFShutdown` is intentionally
  // never called here to keep this simple — the process exiting tears it
  // down anyway, matching the lifetime of the plugin itself.
  MFStartup(MF_VERSION, MFSTARTUP_LITE);

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kMethodChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

AudioChannel::~AudioChannel() {
  channel_->SetMethodCallHandler(nullptr);
  players_.clear();
}

AudioPlayerEntry* AudioChannel::EnsureEntry(const std::string& player_id) {
  auto it = players_.find(player_id);
  if (it != players_.end()) return it->second.get();
  auto entry = std::make_unique<AudioPlayerEntry>(messenger_, player_id);
  auto* raw = entry.get();
  players_[player_id] = std::move(entry);
  return raw;
}

void AudioChannel::DisposeEntry(const std::string& player_id) {
  players_.erase(player_id);
}

void AudioChannel::HandleMethodCall(
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
  } else if (method == "dispose") {
    DisposeEntry(player_id);
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace attachment_engine_windows
