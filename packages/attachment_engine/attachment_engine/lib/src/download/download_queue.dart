// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:collection';

import 'download_manager.dart';

/// Relative priority of a queued download.
enum DownloadPriority { high, normal, low }

class QueuedDownload {
  QueuedDownload({
    required this.key,
    required this.url,
    this.priority = DownloadPriority.normal,
    this.state = DownloadState.queued,
  });

  final String key;
  final String url;
  final DownloadPriority priority;
  DownloadState state;
}

/// A simple in-memory priority queue for downloads. Higher-priority items
/// are dequeued first; within the same priority, FIFO order is preserved.
class DownloadQueue {
  final List<QueuedDownload> _items = [];

  int get length => _items.length;

  void enqueue(QueuedDownload item) {
    _items.add(item);
    _items.sort((a, b) => a.priority.index.compareTo(b.priority.index));
  }

  QueuedDownload? dequeue() {
    final index = _items.indexWhere((i) => i.state == DownloadState.queued);
    if (index == -1) return null;
    final item = _items[index];
    item.state = DownloadState.running;
    return item;
  }

  QueuedDownload? byKey(String key) {
    for (final item in _items) {
      if (item.key == key) return item;
    }
    return null;
  }

  void remove(String key) {
    _items.removeWhere((i) => i.key == key);
  }

  UnmodifiableListView<QueuedDownload> get all => UnmodifiableListView(_items);
}
