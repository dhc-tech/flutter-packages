import Flutter
import Foundation

/// Replaces `path_provider`: exposes app-private storage directories via
/// `NSSearchPathForDirectoriesInDomains`. Implements the Pigeon-generated
/// `PathsHostApi`.
class PathsChannel: NSObject, PathsHostApi {
  func register(with messenger: FlutterBinaryMessenger) {
    PathsHostApiSetup.setUp(binaryMessenger: messenger, api: self)
  }

  func unregister(with messenger: FlutterBinaryMessenger) {
    PathsHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
  }

  func getApplicationSupportDirectory() async throws -> String {
    let paths = NSSearchPathForDirectoriesInDomains(
      .applicationSupportDirectory, .userDomainMask, true)
    let dir = paths.first ?? NSTemporaryDirectory()
    try? FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true, attributes: nil)
    return dir
  }

  func getApplicationCacheDirectory() async throws -> String {
    let paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
    let dir = paths.first ?? NSTemporaryDirectory()
    try? FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true, attributes: nil)
    return dir
  }
}
