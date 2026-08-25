// Copyright 2026 DHC
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine (no
// native Linux toolchain available here). It mirrors the GObject-based
// plugin registrant pattern used by every published `flutter_linux` GTK
// plugin (see `flutter create --template=plugin --platforms=linux`'s
// generated `<name>_plugin.cc`).

#include "include/attachment_engine_linux/attachment_engine_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include "audio_channel.h"
#include "share_channel.h"  // No native share implementation — see header.
#include "video_channel.h"

struct _AttachmentEngineLinuxPlugin {
  GObject parent_instance;
  AttachmentEngineAudioChannel* audio_channel;
  AttachmentEngineVideoChannel* video_channel;
};

G_DEFINE_TYPE(AttachmentEngineLinuxPlugin, attachment_engine_linux_plugin,
              g_object_get_type())

static void attachment_engine_linux_plugin_dispose(GObject* object) {
  AttachmentEngineLinuxPlugin* self =
      ATTACHMENT_ENGINE_LINUX_PLUGIN(object);
  g_clear_object(&self->audio_channel);
  g_clear_object(&self->video_channel);
  G_OBJECT_CLASS(attachment_engine_linux_plugin_parent_class)
      ->dispose(object);
}

static void attachment_engine_linux_plugin_class_init(
    AttachmentEngineLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = attachment_engine_linux_plugin_dispose;
}

static void attachment_engine_linux_plugin_init(
    AttachmentEngineLinuxPlugin* self) {}

void attachment_engine_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  AttachmentEngineLinuxPlugin* plugin = ATTACHMENT_ENGINE_LINUX_PLUGIN(
      g_object_new(attachment_engine_linux_plugin_get_type(), nullptr));

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  // Share is intentionally NOT registered here — see share_channel.h for
  // why (no universal Linux share mechanism exists) — the Dart side throws
  // UnimplementedError directly instead of calling into native code.
  plugin->audio_channel = attachment_engine_audio_channel_new(messenger);
  plugin->video_channel =
      attachment_engine_video_channel_new(messenger, registrar);

  g_object_unref(plugin);
}
