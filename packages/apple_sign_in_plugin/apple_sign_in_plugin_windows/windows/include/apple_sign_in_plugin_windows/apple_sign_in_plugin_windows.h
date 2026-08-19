#ifndef FLUTTER_PLUGIN_APPLE_SIGN_IN_PLUGIN_WINDOWS_H_
#define FLUTTER_PLUGIN_APPLE_SIGN_IN_PLUGIN_WINDOWS_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void AppleSignInPluginWindowsRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_APPLE_SIGN_IN_PLUGIN_WINDOWS_H_
