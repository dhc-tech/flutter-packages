import Flutter
import Foundation

/// Replaces `dio`. Downloads over `URLSession`/`URLSessionDownloadTask`,
/// reporting progress/completion/error over a shared EventChannel
/// (`attachment_engine/download_events`), each event tagged with its
/// `downloadId`, mirroring the Android `HttpURLConnection` implementation.
///
/// `startDownload`/`resumeDownload`/`cancelDownload` are dispatched through
/// the Pigeon-generated `DownloadHostApi`. Progress/completion/error
/// *events* stay on the hand-written shared `FlutterEventChannel` below —
/// see the note in `attachment_engine_platform_interface/pigeons/messages.dart`.
class DownloadChannel: NSObject, DownloadHostApi, URLSessionDownloadDelegate {
  static let eventChannelName = "attachment_engine/download_events"

  private var eventChannel: FlutterEventChannel!
  private var eventSink: FlutterEventSink?

  private lazy var session: URLSession = {
    URLSession(configuration: .default, delegate: self, delegateQueue: nil)
  }()

  // downloadId -> task
  private var tasks: [String: URLSessionDownloadTask] = [:]
  // task identifier -> (downloadId, destPath)
  private var taskInfo: [Int: (downloadId: String, destPath: String)] = [:]
  // downloadId -> pending resume-data file path (sidecar next to destPath)
  private func resumeDataPath(for destPath: String) -> String { destPath + ".resumedata" }

  func register(with messenger: FlutterBinaryMessenger) {
    DownloadHostApiSetup.setUp(binaryMessenger: messenger, api: self)
    eventChannel = FlutterEventChannel(
      name: DownloadChannel.eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(
      DownloadStreamHandler(onListen: { [weak self] sink in
        self?.eventSink = sink
      }, onCancel: { [weak self] in
        self?.eventSink = nil
      }))
  }

  func unregister(with messenger: FlutterBinaryMessenger) {
    DownloadHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    eventChannel.setStreamHandler(nil)
    session.invalidateAndCancel()
  }

  @MainActor
  func startDownload(url: String, headers: [String: String], destPath: String) async throws -> String {
    try beginDownload(urlString: url, headers: headers, destPath: destPath, resume: false)
  }

  @MainActor
  func resumeDownload(url: String, headers: [String: String], destPath: String) async throws -> String {
    try beginDownload(urlString: url, headers: headers, destPath: destPath, resume: true)
  }

  @MainActor
  func cancelDownload(downloadId: String) async throws {
    if let task = tasks[downloadId] {
      let destPath = taskInfo[task.taskIdentifier]?.destPath
      task.cancel(byProducingResumeData: { [weak self] data in
        guard let self = self, let destPath = destPath, let data = data else { return }
        try? data.write(to: URL(fileURLWithPath: self.resumeDataPath(for: destPath)))
      })
    }
  }

  private func beginDownload(
    urlString: String, headers: [String: String], destPath: String, resume: Bool
  ) throws -> String {
    guard let url = URL(string: urlString) else {
      throw PigeonError(code: "bad_args", message: "url and destPath are required", details: nil)
    }
    // HTTPS must never be silently downgraded: reject plain-HTTP, matching
    // platform ATS defaults. (No caller-facing override is exposed through
    // the shared Pigeon contract.)
    if url.scheme?.lowercased() == "http" {
      throw PigeonError(code: "insecure_url", message: "Plain HTTP URLs are rejected by default", details: nil)
    }
    let downloadId = UUID().uuidString

    let resumeDataURL = URL(fileURLWithPath: resumeDataPath(for: destPath))
    if resume, let data = try? Data(contentsOf: resumeDataURL) {
      let task = session.downloadTask(withResumeData: data)
      tasks[downloadId] = task
      taskInfo[task.taskIdentifier] = (downloadId, destPath)
      try? FileManager.default.removeItem(at: resumeDataURL)
      task.resume()
      return downloadId
    }

    // No valid resume data (first attempt, or iOS discarded/expired it) - full request.
    var request = URLRequest(url: url, timeoutInterval: 30)
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    let task = session.downloadTask(with: request)
    tasks[downloadId] = task
    taskInfo[task.taskIdentifier] = (downloadId, destPath)
    task.resume()
    return downloadId
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let info = taskInfo[downloadTask.taskIdentifier] else { return }
    do {
      let destURL = URL(fileURLWithPath: info.destPath)
      try? FileManager.default.createDirectory(
        at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: info.destPath) {
        try FileManager.default.removeItem(atPath: info.destPath)
      }
      try FileManager.default.moveItem(at: location, to: destURL)
      emit(["downloadId": info.downloadId, "type": "completed", "path": info.destPath])
    } catch {
      emit([
        "downloadId": info.downloadId, "type": "error",
        "message": error.localizedDescription,
      ])
    }
    taskInfo.removeValue(forKey: downloadTask.taskIdentifier)
    tasks.removeValue(forKey: info.downloadId)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let info = taskInfo[downloadTask.taskIdentifier] else { return }
    emit([
      "downloadId": info.downloadId,
      "type": "progress",
      "received": totalBytesWritten,
      "total": totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : -1,
    ])
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error = error, let info = taskInfo[task.taskIdentifier] else { return }
    let nsError = error as NSError
    let message: String
    if nsError.code == NSURLErrorCancelled {
      message = "cancelled"
      // Persist any resume data produced alongside cancellation so a later
      // resumeDownload call can continue instead of restarting.
      if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
        try? resumeData.write(to: URL(fileURLWithPath: resumeDataPath(for: info.destPath)))
      }
    } else if nsError.domain == NSCocoaErrorDomain
      && nsError.code == NSFileWriteOutOfSpaceError
    {
      message = "insufficient_storage"
    } else {
      message = error.localizedDescription
    }
    emit(["downloadId": info.downloadId, "type": "error", "message": message])
    taskInfo.removeValue(forKey: task.taskIdentifier)
    tasks.removeValue(forKey: info.downloadId)
  }
}

private class DownloadStreamHandler: NSObject, FlutterStreamHandler {
  let onListen: (FlutterEventSink?) -> Void
  let onCancel: () -> Void

  init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
    self.onListen = onListen
    self.onCancel = onCancel
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    onListen(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancel()
    return nil
  }
}
