// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine — see
// video_channel.h for the documented API and the GTK-overlay embedding
// tradeoff this implementation makes.

#include "video_channel.h"

#include <gst/gst.h>
#include <gtk/gtk.h>

#include <map>
#include <memory>
#include <string>

namespace {
constexpr char kMethodChannelName[] = "attachment_engine/video";
constexpr char kEventChannelPrefix[] = "attachment_engine/video_events/";
constexpr guint kProgressTimerMs = 250;
}  // namespace

struct VideoPlayerEntry {
  std::string player_id;
  GstElement* playbin = nullptr;
  GtkWidget* video_widget = nullptr;  // owned by `gtksink`'s "widget" prop.
  GtkFixed* overlay_fixed = nullptr;  // borrowed: the FlView's GTK parent.
  FlEventChannel* event_channel = nullptr;
  guint bus_watch_id = 0;
  guint progress_timer_id = 0;
  bool has_listener = false;
};

struct _AttachmentEngineVideoChannel {
  GObject parent_instance;
  FlBinaryMessenger* messenger;  // borrowed
  FlPluginRegistrar* registrar;  // borrowed
  FlMethodChannel* channel;
  std::map<std::string, std::unique_ptr<VideoPlayerEntry>>* players;
};

G_DEFINE_TYPE(AttachmentEngineVideoChannel, attachment_engine_video_channel,
              G_TYPE_OBJECT)

static void emit_state(VideoPlayerEntry* entry, const char* state) {
  if (!entry->has_listener) return;
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "state", fl_value_new_string(state));
  fl_event_channel_send(entry->event_channel, map, nullptr, nullptr);
}

static gboolean emit_progress(gpointer user_data) {
  auto* entry = static_cast<VideoPlayerEntry*>(user_data);
  if (!entry->has_listener || !entry->playbin) return G_SOURCE_CONTINUE;

  gint64 position_ns = 0, duration_ns = 0;
  gst_element_query_position(entry->playbin, GST_FORMAT_TIME, &position_ns);
  gst_element_query_duration(entry->playbin, GST_FORMAT_TIME, &duration_ns);
  GstState state = GST_STATE_NULL;
  gst_element_get_state(entry->playbin, &state, nullptr, 0);

  // GetNativeVideoSize equivalent: query the negotiated caps on the video
  // sink's own "sink" pad, falling back to 0x0 if not yet known.
  gint width = 0, height = 0;
  GstElement* video_sink = nullptr;
  g_object_get(entry->playbin, "video-sink", &video_sink, nullptr);
  if (video_sink) {
    GstPad* pad = gst_element_get_static_pad(video_sink, "sink");
    if (pad) {
      GstCaps* caps = gst_pad_get_current_caps(pad);
      if (caps) {
        GstStructure* s = gst_caps_get_structure(caps, 0);
        gst_structure_get_int(s, "width", &width);
        gst_structure_get_int(s, "height", &height);
        gst_caps_unref(caps);
      }
      gst_object_unref(pad);
    }
    gst_object_unref(video_sink);
  }

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(
      map, "state",
      fl_value_new_string(state == GST_STATE_PLAYING ? "playing" : "paused"));
  fl_value_set_string_take(
      map, "positionMs",
      fl_value_new_int(static_cast<int64_t>(position_ns / GST_MSECOND)));
  fl_value_set_string_take(
      map, "durationMs",
      fl_value_new_int(static_cast<int64_t>(duration_ns / GST_MSECOND)));
  fl_value_set_string_take(map, "width", fl_value_new_int(width));
  fl_value_set_string_take(map, "height", fl_value_new_int(height));
  fl_event_channel_send(entry->event_channel, map, nullptr, nullptr);
  return G_SOURCE_CONTINUE;
}

static gboolean on_bus_message(GstBus*, GstMessage* message,
                                gpointer user_data) {
  auto* entry = static_cast<VideoPlayerEntry*>(user_data);
  switch (GST_MESSAGE_TYPE(message)) {
    case GST_MESSAGE_ASYNC_DONE:
      emit_state(entry, "ready");
      if (entry->progress_timer_id == 0) {
        entry->progress_timer_id =
            g_timeout_add(kProgressTimerMs, emit_progress, entry);
      }
      break;
    case GST_MESSAGE_EOS:
      emit_state(entry, "completed");
      break;
    case GST_MESSAGE_ERROR:
      emit_state(entry, "error");
      break;
    default:
      break;
  }
  return TRUE;
}

static VideoPlayerEntry* ensure_entry(AttachmentEngineVideoChannel* self,
                                       const std::string& player_id) {
  auto it = self->players->find(player_id);
  if (it != self->players->end()) return it->second.get();

  auto entry = std::make_unique<VideoPlayerEntry>();
  entry->player_id = player_id;
  entry->playbin = gst_element_factory_make("playbin", nullptr);

  // gtksink: GStreamer's documented GTK embedding sink — exposes the
  // rendered frames as a plain GtkWidget via its "widget" property.
  // https://gstreamer.freedesktop.org/documentation/gtk/index.html
  GstElement* video_sink = gst_element_factory_make("gtksink", nullptr);
  if (video_sink) {
    g_object_set(entry->playbin, "video-sink", video_sink, nullptr);
    g_object_get(video_sink, "widget", &entry->video_widget, nullptr);
  }

  FlView* fl_view = fl_plugin_registrar_get_view(self->registrar);
  GtkWidget* parent = gtk_widget_get_parent(GTK_WIDGET(fl_view));
  // The overlay strategy assumes `FlView`'s parent (typically the window's
  // content area) is (or can be made) a GtkFixed/GtkOverlay so the video
  // widget can be positioned in pixel coordinates; a real app template
  // controls that container, so this plugin cannot assume its exact type
  // without a matching change to the generated `my_application.cc` — see
  // README "Known limitations".
  if (entry->video_widget && GTK_IS_FIXED(parent)) {
    entry->overlay_fixed = GTK_FIXED(parent);
    gtk_fixed_put(entry->overlay_fixed, entry->video_widget, 0, 0);
    gtk_widget_show(entry->video_widget);
  }

  GstBus* bus = gst_element_get_bus(entry->playbin);
  entry->bus_watch_id = gst_bus_add_watch(bus, on_bus_message, entry.get());
  gst_object_unref(bus);

  std::string channel_name = kEventChannelPrefix + player_id;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  entry->event_channel = fl_event_channel_new(self->messenger, channel_name.c_str(),
                                               FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(
      entry->event_channel,
      [](FlEventChannel*, FlValue*, gpointer user_data) -> FlMethodErrorResponse* {
        static_cast<VideoPlayerEntry*>(user_data)->has_listener = true;
        return nullptr;
      },
      [](FlEventChannel*, FlValue*, gpointer user_data) -> FlMethodErrorResponse* {
        static_cast<VideoPlayerEntry*>(user_data)->has_listener = false;
        return nullptr;
      },
      entry.get(), nullptr);

  auto* raw = entry.get();
  (*self->players)[player_id] = std::move(entry);
  return raw;
}

static void dispose_entry(AttachmentEngineVideoChannel* self,
                           const std::string& player_id) {
  auto it = self->players->find(player_id);
  if (it == self->players->end()) return;
  auto& entry = it->second;
  if (entry->progress_timer_id) g_source_remove(entry->progress_timer_id);
  if (entry->bus_watch_id) g_source_remove(entry->bus_watch_id);
  if (entry->video_widget && entry->overlay_fixed) {
    gtk_container_remove(GTK_CONTAINER(entry->overlay_fixed), entry->video_widget);
  }
  if (entry->playbin) {
    gst_element_set_state(entry->playbin, GST_STATE_NULL);
    gst_object_unref(entry->playbin);
  }
  self->players->erase(it);
}

static const char* fl_value_get_str_or(FlValue* map, const char* key) {
  FlValue* v = fl_value_lookup_string(map, key);
  return (v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING)
             ? fl_value_get_string(v)
             : nullptr;
}

static int64_t fl_value_get_int_or(FlValue* map, const char* key, int64_t fallback) {
  FlValue* v = fl_value_lookup_string(map, key);
  return v ? fl_value_get_int(v) : fallback;
}

static void handle_method_call(FlMethodChannel*, FlMethodCall* method_call,
                                gpointer user_data) {
  auto* self = ATTACHMENT_ENGINE_VIDEO_CHANNEL(user_data);
  FlValue* args = fl_method_call_get_args(method_call);
  const char* method = fl_method_call_get_name(method_call);

  const char* player_id_c = fl_value_get_str_or(args, "playerId");
  if (!player_id_c) {
    g_autoptr(FlMethodErrorResponse) response =
        fl_method_error_response_new("bad_args", "playerId is required", nullptr);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
    return;
  }
  std::string player_id = player_id_c;
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "load") == 0) {
    const char* path = fl_value_get_str_or(args, "path");
    const char* url = fl_value_get_str_or(args, "url");
    VideoPlayerEntry* entry = ensure_entry(self, player_id);
    g_autofree gchar* uri = nullptr;
    if (path) {
      uri = gst_filename_to_uri(path, nullptr);
    } else if (url) {
      uri = g_strdup(url);
    }
    if (uri) g_object_set(entry->playbin, "uri", uri, nullptr);
    emit_state(entry, "buffering");
    gst_element_set_state(entry->playbin, GST_STATE_PAUSED);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "play") == 0) {
    VideoPlayerEntry* entry = ensure_entry(self, player_id);
    gst_element_set_state(entry->playbin, GST_STATE_PLAYING);
    emit_state(entry, "playing");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "pause") == 0) {
    VideoPlayerEntry* entry = ensure_entry(self, player_id);
    gst_element_set_state(entry->playbin, GST_STATE_PAUSED);
    emit_state(entry, "paused");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "seek") == 0) {
    VideoPlayerEntry* entry = ensure_entry(self, player_id);
    gint64 ms = fl_value_get_int_or(args, "positionMs", 0);
    gst_element_seek_simple(
        entry->playbin, GST_FORMAT_TIME,
        static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT),
        ms * GST_MSECOND);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setSpeed") == 0) {
    VideoPlayerEntry* entry = ensure_entry(self, player_id);
    FlValue* speed_value = fl_value_lookup_string(args, "speed");
    gdouble speed = speed_value ? fl_value_get_float(speed_value) : 1.0;
    gint64 position_ns = 0;
    gst_element_query_position(entry->playbin, GST_FORMAT_TIME, &position_ns);
    gst_element_seek(
        entry->playbin, speed, GST_FORMAT_TIME,
        static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE),
        GST_SEEK_TYPE_SET, position_ns, GST_SEEK_TYPE_END, 0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setVolume") == 0) {
    VideoPlayerEntry* entry = ensure_entry(self, player_id);
    FlValue* volume_value = fl_value_lookup_string(args, "volume");
    gdouble volume = volume_value ? fl_value_get_float(volume_value) : 1.0;
    g_object_set(entry->playbin, "volume", volume, nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setLayout") == 0) {
    VideoPlayerEntry* entry = ensure_entry(self, player_id);
    int left = static_cast<int>(fl_value_get_int_or(args, "left", 0));
    int top = static_cast<int>(fl_value_get_int_or(args, "top", 0));
    int width = static_cast<int>(fl_value_get_int_or(args, "width", 0));
    int height = static_cast<int>(fl_value_get_int_or(args, "height", 0));
    if (entry->video_widget) {
      gtk_widget_set_size_request(entry->video_widget, width, height);
      if (entry->overlay_fixed) {
        gtk_fixed_move(entry->overlay_fixed, entry->video_widget, left, top);
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "dispose") == 0) {
    dispose_entry(self, player_id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void attachment_engine_video_channel_dispose(GObject* object) {
  auto* self = ATTACHMENT_ENGINE_VIDEO_CHANNEL(object);
  delete self->players;
  self->players = nullptr;
  G_OBJECT_CLASS(attachment_engine_video_channel_parent_class)->dispose(object);
}

static void attachment_engine_video_channel_class_init(
    AttachmentEngineVideoChannelClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = attachment_engine_video_channel_dispose;
}

static void attachment_engine_video_channel_init(
    AttachmentEngineVideoChannel* self) {
  self->players = new std::map<std::string, std::unique_ptr<VideoPlayerEntry>>();
}

AttachmentEngineVideoChannel* attachment_engine_video_channel_new(
    FlBinaryMessenger* messenger, FlPluginRegistrar* registrar) {
  gst_init(nullptr, nullptr);

  AttachmentEngineVideoChannel* self = ATTACHMENT_ENGINE_VIDEO_CHANNEL(
      g_object_new(ATTACHMENT_ENGINE_VIDEO_CHANNEL_TYPE, nullptr));
  self->messenger = messenger;
  self->registrar = registrar;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger, kMethodChannelName,
                                         FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, handle_method_call,
                                             self, nullptr);
  return self;
}
