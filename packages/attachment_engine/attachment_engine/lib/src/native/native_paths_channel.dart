import 'dart:io';

import 'package:attachment_engine_platform_interface/attachment_engine_platform_interface.dart';

/// Replaces `path_provider`: asks the native side (via
/// [AttachmentEnginePlatform]) for app-private storage directories.
///
/// iOS: `NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory /
/// .cachesDirectory, .userDomainMask, true)`.
/// Android: `context.filesDir` / `context.cacheDir`.
class NativePathsChannel {
  NativePathsChannel._();

  static Directory? _supportDirCache;
  static Directory? _cacheDirCache;

  /// App-private, persistent storage directory (survives app restarts,
  /// excluded from user-visible file browsing).
  static Future<Directory> applicationSupportDirectory() async {
    final cached = _supportDirCache;
    if (cached != null) return cached;
    try {
      final path = await AttachmentEnginePlatform.instance
          .getApplicationSupportDirectory();
      final dir = Directory(path);
      _supportDirCache = dir;
      return dir;
    } catch (_) {
      // Fallback for platforms/tests without a platform implementation
      // registered (e.g. plain `dart test`): use a directory under the
      // system temp directory so callers still get a writable, discoverable
      // location.
      final dir = Directory(
        '${Directory.systemTemp.path}/attachment_engine_support',
      );
      _supportDirCache = dir;
      return dir;
    }
  }

  /// App-private cache directory (OS may purge it under storage pressure).
  static Future<Directory> applicationCacheDirectory() async {
    final cached = _cacheDirCache;
    if (cached != null) return cached;
    try {
      final path = await AttachmentEnginePlatform.instance
          .getApplicationCacheDirectory();
      final dir = Directory(path);
      _cacheDirCache = dir;
      return dir;
    } catch (_) {
      final dir = Directory(
        '${Directory.systemTemp.path}/attachment_engine_cache',
      );
      _cacheDirCache = dir;
      return dir;
    }
  }

  /// Test-only hook to reset cached directories between tests.
  static void resetForTesting() {
    _supportDirCache = null;
    _cacheDirCache = null;
  }
}
