// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_PLUGIN_APPLE_SIGN_IN_PLUGIN_LINUX_H_
#define FLUTTER_PLUGIN_APPLE_SIGN_IN_PLUGIN_LINUX_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

FLUTTER_PLUGIN_EXPORT GType apple_sign_in_plugin_linux_get_type();

FLUTTER_PLUGIN_EXPORT void apple_sign_in_plugin_linux_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_APPLE_SIGN_IN_PLUGIN_LINUX_H_
