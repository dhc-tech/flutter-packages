#include "include/apple_sign_in_plugin_linux/apple_sign_in_plugin_linux.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/types.h>
#include <cstring>
#include <chrono>

#define APPLE_SIGN_IN_PLUGIN_LINUX(obj)   (G_TYPE_CHECK_INSTANCE_CAST((obj), apple_sign_in_plugin_linux_get_type(),                               AppleSignInPluginLinux))

struct _AppleSignInPluginLinux {
  GObject parent_instance;
  FlMethodChannel* channel;
  FlMethodCall* pending_method_call;
  gchar* pending_state;
  gchar* expected_scheme;
  gchar* expected_host;
  std::chrono::steady_clock::time_point request_start_time;
};

G_DEFINE_TYPE(AppleSignInPluginLinux, apple_sign_in_plugin_linux, g_object_get_type())

static void cleanup_pending(AppleSignInPluginLinux* self) {
  if (self->pending_method_call != nullptr) {
    g_object_unref(self->pending_method_call);
    self->pending_method_call = nullptr;
  }
  g_free(self->pending_state);
  self->pending_state = nullptr;
  g_free(self->expected_scheme);
  self->expected_scheme = nullptr;
  g_free(self->expected_host);
  self->expected_host = nullptr;
}

static void handle_native_callback(AppleSignInPluginLinux* self, const gchar* callback_url, FlMethodCall* method_call) {
  if (self->pending_method_call == nullptr) {
    g_autoptr(FlValue) ack = fl_value_new_bool(FALSE);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(ack)), nullptr);
    return;
  }

  // Check 5-minute timeout
  auto now = std::chrono::steady_clock::now();
  if (std::chrono::duration_cast<std::chrono::minutes>(now - self->request_start_time).count() >= 5) {
    fl_method_call_respond(self->pending_method_call,
        FL_METHOD_RESPONSE(fl_method_error_response_new("canceled", "Sign in with Apple timed out waiting for callback.", nullptr)),
        nullptr);
    cleanup_pending(self);
    g_autoptr(FlValue) ack = fl_value_new_bool(FALSE);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(ack)), nullptr);
    return;
  }

  // Validate scheme
  if (self->expected_scheme != nullptr) {
    g_autofree gchar* scheme_prefix = g_strdup_printf("%s://", self->expected_scheme);
    if (!g_str_has_prefix(callback_url, scheme_prefix)) {
      fl_method_call_respond(self->pending_method_call,
          FL_METHOD_RESPONSE(fl_method_error_response_new("authorization_failed", "Apple Sign-In callback URI scheme mismatch.", nullptr)),
          nullptr);
      cleanup_pending(self);
      g_autoptr(FlValue) ack = fl_value_new_bool(FALSE);
      fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(ack)), nullptr);
      return;
    }
  }

  // Validate host
  if (self->expected_host != nullptr && strlen(self->expected_host) > 0) {
    g_autofree gchar* host_prefix = g_strdup_printf("%s://%s", self->expected_scheme, self->expected_host);
    if (!g_str_has_prefix(callback_url, host_prefix)) {
      fl_method_call_respond(self->pending_method_call,
          FL_METHOD_RESPONSE(fl_method_error_response_new("authorization_failed", "Apple Sign-In callback URI host mismatch.", nullptr)),
          nullptr);
      cleanup_pending(self);
      g_autoptr(FlValue) ack = fl_value_new_bool(FALSE);
      fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(ack)), nullptr);
      return;
    }
  }

  g_autoptr(FlValue) result_map = fl_value_new_map();
  fl_value_set_string_take(result_map, "callbackUrl", fl_value_new_string(callback_url));
  fl_value_set_string_take(result_map, "expectedState", fl_value_new_string(self->pending_state != nullptr ? self->pending_state : ""));

  fl_method_call_respond(self->pending_method_call,
      FL_METHOD_RESPONSE(fl_method_success_response_new(result_map)),
      nullptr);
  cleanup_pending(self);

  g_autoptr(FlValue) ack = fl_value_new_bool(TRUE);
  fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(ack)), nullptr);
}

static void apple_sign_in_plugin_linux_handle_method_call(
    AppleSignInPluginLinux* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "isAvailable") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (strcmp(method, "signIn") == 0) {
    if (self->pending_method_call != nullptr) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "already_in_progress", "A Sign in with Apple request is already in progress.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* url_val = fl_value_lookup_string(args, "url");
    FlValue* state_val = fl_value_lookup_string(args, "state");
    FlValue* scheme_val = fl_value_lookup_string(args, "callbackScheme");
    FlValue* host_val = fl_value_lookup_string(args, "callbackHost");

    if (url_val == nullptr || state_val == nullptr || scheme_val == nullptr) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalid_arguments", "Missing required url, state, or callbackScheme argument.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    const gchar* url = fl_value_get_string(url_val);
    self->pending_state = g_strdup(fl_value_get_string(state_val));
    self->expected_scheme = g_strdup(fl_value_get_string(scheme_val));
    self->expected_host = host_val != nullptr && fl_value_get_type(host_val) == FL_VALUE_TYPE_STRING
        ? g_strdup(fl_value_get_string(host_val))
        : nullptr;
    self->pending_method_call = g_object_ref(method_call);
    self->request_start_time = std::chrono::steady_clock::now();

    g_autoptr(GError) error = nullptr;
    gtk_show_uri_on_window(nullptr, url, GDK_CURRENT_TIME, &error);
    if (error != nullptr) {
      cleanup_pending(self);
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "launch_failed", error->message, nullptr));
      fl_method_call_respond(method_call, response, nullptr);
    }
  } else if (strcmp(method, "onNativeCallback") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* cb_val = fl_value_lookup_string(args, "callbackUrl");
    if (cb_val != nullptr && fl_value_get_type(cb_val) == FL_VALUE_TYPE_STRING) {
      handle_native_callback(self, fl_value_get_string(cb_val), method_call);
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("invalid_arguments", "Missing 'callbackUrl'.", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
    }
  } else if (strcmp(method, "cancelSignIn") == 0) {
    if (self->pending_method_call != nullptr) {
      fl_method_call_respond(self->pending_method_call,
          FL_METHOD_RESPONSE(fl_method_error_response_new("canceled", "Sign in with Apple was canceled.", nullptr)),
          nullptr);
      cleanup_pending(self);
    }
    g_autoptr(FlValue) ack = fl_value_new_bool(TRUE);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(ack)), nullptr);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

static void apple_sign_in_plugin_linux_dispose(GObject* object) {
  AppleSignInPluginLinux* self = APPLE_SIGN_IN_PLUGIN_LINUX(object);
  cleanup_pending(self);
  if (self->channel != nullptr) {
    g_object_unref(self->channel);
    self->channel = nullptr;
  }
  G_OBJECT_CLASS(apple_sign_in_plugin_linux_parent_class)->dispose(object);
}

static void apple_sign_in_plugin_linux_class_init(AppleSignInPluginLinuxClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = apple_sign_in_plugin_linux_dispose;
}

static void apple_sign_in_plugin_linux_init(AppleSignInPluginLinux* self) {
  self->channel = nullptr;
  self->pending_method_call = nullptr;
  self->pending_state = nullptr;
  self->expected_scheme = nullptr;
  self->expected_host = nullptr;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  AppleSignInPluginLinux* plugin = APPLE_SIGN_IN_PLUGIN_LINUX(user_data);
  apple_sign_in_plugin_linux_handle_method_call(plugin, method_call);
}

void apple_sign_in_plugin_linux_register_with_registrar(
    FlPluginRegistrar* registrar) {
  AppleSignInPluginLinux* plugin = APPLE_SIGN_IN_PLUGIN_LINUX(
      g_object_new(apple_sign_in_plugin_linux_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                                          "apple_sign_in_plugin_linux",
                                          FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(plugin->channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
