#include "include/apple_sign_in_plugin_windows/apple_sign_in_plugin_windows.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shellapi.h>

#include <memory>
#include <string>
#include <unordered_map>
#include <chrono>

namespace {

class AppleSignInPluginWindows : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  AppleSignInPluginWindows(std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);
  virtual ~AppleSignInPluginWindows();

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_result_;
  std::string pending_state_;
  std::string expected_scheme_;
  std::string expected_host_;
  std::chrono::steady_clock::time_point request_start_time_;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void ProcessNativeCallback(const std::string& callback_url,
                             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CleanupPending();
};

void AppleSignInPluginWindows::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "apple_sign_in_plugin_windows",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<AppleSignInPluginWindows>(std::move(channel));

  plugin->channel_->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

AppleSignInPluginWindows::AppleSignInPluginWindows(
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
    : channel_(std::move(channel)) {}

AppleSignInPluginWindows::~AppleSignInPluginWindows() {
  CleanupPending();
}

void AppleSignInPluginWindows::CleanupPending() {
  pending_result_ = nullptr;
  pending_state_.clear();
  expected_scheme_.clear();
  expected_host_.clear();
}

void AppleSignInPluginWindows::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("isAvailable") == 0) {
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name().compare("signIn") == 0) {
    if (pending_result_ != nullptr) {
      result->Error("already_in_progress", "A Sign in with Apple request is already in progress.");
      return;
    }

    const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("invalid_arguments", "Arguments must be an EncodableMap.");
      return;
    }

    auto url_it = arguments->find(flutter::EncodableValue("url"));
    auto state_it = arguments->find(flutter::EncodableValue("state"));
    auto scheme_it = arguments->find(flutter::EncodableValue("callbackScheme"));
    auto host_it = arguments->find(flutter::EncodableValue("callbackHost"));

    if (url_it == arguments->end() || state_it == arguments->end() || scheme_it == arguments->end()) {
      result->Error("invalid_arguments", "Missing required url, state, or callbackScheme argument.");
      return;
    }

    const std::string url = std::get<std::string>(url_it->second);
    pending_state_ = std::get<std::string>(state_it->second);
    expected_scheme_ = std::get<std::string>(scheme_it->second);
    if (host_it != arguments->end() && std::holds_alternative<std::string>(host_it->second)) {
      expected_host_ = std::get<std::string>(host_it->second);
    } else {
      expected_host_.clear();
    }

    pending_result_ = std::move(result);
    request_start_time_ = std::chrono::steady_clock::now();

    HINSTANCE hResult = ShellExecuteA(NULL, "open", url.c_str(), NULL, NULL, SW_SHOWNORMAL);
    if ((INT_PTR)hResult <= 32) {
      if (pending_result_) {
        pending_result_->Error("launch_failed", "Failed to open system browser with ShellExecute.");
      }
      CleanupPending();
    }
  } else if (method_call.method_name().compare("onNativeCallback") == 0) {
    const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("invalid_arguments", "Callback arguments must be an EncodableMap.");
      return;
    }
    auto callback_it = arguments->find(flutter::EncodableValue("callbackUrl"));
    if (callback_it == arguments->end()) {
      result->Error("invalid_arguments", "Missing 'callbackUrl' in callback notification.");
      return;
    }
    const std::string callback_url = std::get<std::string>(callback_it->second);
    ProcessNativeCallback(callback_url, std::move(result));
  } else if (method_call.method_name().compare("cancelSignIn") == 0) {
    if (pending_result_ != nullptr) {
      pending_result_->Error("canceled", "Sign in with Apple was canceled.");
      CleanupPending();
    }
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

void AppleSignInPluginWindows::ProcessNativeCallback(
    const std::string& callback_url,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> ack_result) {
  if (pending_result_ == nullptr) {
    if (ack_result) ack_result->Success(flutter::EncodableValue(false));
    return;
  }

  // Check 5-minute timeout
  auto now = std::chrono::steady_clock::now();
  if (std::chrono::duration_cast<std::chrono::minutes>(now - request_start_time_).count() >= 5) {
    pending_result_->Error("canceled", "Sign in with Apple timed out waiting for callback.");
    CleanupPending();
    if (ack_result) ack_result->Success(flutter::EncodableValue(false));
    return;
  }

  // Basic URI validation
  if (!expected_scheme_.empty()) {
    std::string expected_prefix = expected_scheme_ + "://";
    if (callback_url.rfind(expected_prefix, 0) != 0) {
      pending_result_->Error("authorization_failed", "Apple Sign-In callback URI scheme mismatch.");
      CleanupPending();
      if (ack_result) ack_result->Success(flutter::EncodableValue(false));
      return;
    }
  }

  if (!expected_host_.empty()) {
    std::string expected_with_host = expected_scheme_ + "://" + expected_host_;
    if (callback_url.rfind(expected_with_host, 0) != 0) {
      pending_result_->Error("authorization_failed", "Apple Sign-In callback URI host mismatch.");
      CleanupPending();
      if (ack_result) ack_result->Success(flutter::EncodableValue(false));
      return;
    }
  }

  // Pass validated URI to Dart via pending result
  flutter::EncodableMap resultMap;
  resultMap[flutter::EncodableValue("callbackUrl")] = flutter::EncodableValue(callback_url);
  resultMap[flutter::EncodableValue("expectedState")] = flutter::EncodableValue(pending_state_);

  pending_result_->Success(flutter::EncodableValue(resultMap));
  CleanupPending();

  if (ack_result) {
    ack_result->Success(flutter::EncodableValue(true));
  }
}

}  // namespace

void AppleSignInPluginWindowsRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  AppleSignInPluginWindows::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
