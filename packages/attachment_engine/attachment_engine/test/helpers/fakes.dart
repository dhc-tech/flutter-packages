// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';

/// Download client answering each call from [handler]; records every url.
class ScriptedDownloadClient implements DownloadClient {
  ScriptedDownloadClient(this.handler);

  /// Always succeeds with [bytes].
  factory ScriptedDownloadClient.ok(List<int> bytes) =>
      ScriptedDownloadClient((_, _) async => Uint8List.fromList(bytes));

  /// Always fails with [error].
  factory ScriptedDownloadClient.failing(Object error) =>
      ScriptedDownloadClient((_, _) => Future<Uint8List>.error(error));

  final Future<Uint8List> Function(int index, String url) handler;
  final List<String> urls = [];

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) {
    urls.add(url);
    return handler(urls.length - 1, url);
  }

  @override
  Object createCancelToken() => Object();

  @override
  void cancel(Object cancelToken) {}
}

class FakeConnectivity implements ConnectivityChecker {
  FakeConnectivity({this.online = true});

  bool online;
  int checks = 0;

  @override
  Future<bool> hasConnection() async {
    checks++;
    return online;
  }
}

/// In-memory [AttachmentMetadataStore] with call counters.
class MemoryMetadataStore implements AttachmentMetadataStore {
  final Map<String, CacheEntry> entries = {};
  int getAllCalls = 0;
  int puts = 0;
  int deletes = 0;
  bool initialized = false;

  @override
  Future<void> init() async => initialized = true;

  @override
  Future<CacheEntry?> get(String key) async => entries[key];

  @override
  Future<List<CacheEntry>> getAll() async {
    getAllCalls++;
    return entries.values.toList();
  }

  @override
  Future<void> put(CacheEntry entry) async {
    puts++;
    entries[entry.key] = entry;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    entries.remove(key);
  }

  @override
  Future<void> clear() async => entries.clear();
}

/// Records every diagnostics callback as a short string.
class RecordingDiagnostics implements AttachmentDiagnosticsSink {
  final List<String> events = [];
  Duration? lastDuration;
  bool? lastCacheHit;

  @override
  void onResolutionStart(String id) => events.add('start:$id');

  @override
  void onResolutionComplete(
    String id, {
    required Duration duration,
    required bool cacheHit,
  }) {
    lastDuration = duration;
    lastCacheHit = cacheHit;
    events.add('complete:$id:$cacheHit');
  }

  @override
  void onResolutionFailed(String id, {required String failureType}) =>
      events.add('failed:$id:$failureType');

  @override
  void onDownloadStart(String id) => events.add('dlStart:$id');

  @override
  void onDownloadComplete(
    String id, {
    required Duration duration,
    required int bytes,
  }) => events.add('dlComplete:$id:$bytes');

  @override
  void onDownloadFailed(String id, {required String failureType}) =>
      events.add('dlFailed:$id:$failureType');

  @override
  void onPlaybackError(String id, {required String failureType}) =>
      events.add('playback:$id:$failureType');
}
