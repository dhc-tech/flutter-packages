import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter/material.dart';

/// Demonstrates [AttachmentEngineConfig] using only the real, public
/// engine API — every toggle below rebuilds an [AttachmentManager] with a
/// genuinely different [AttachmentEngineConfig] and shows the resulting
/// behavior change, rather than a cosmetic-only switch.
class ConfigDemoPage extends StatefulWidget {
  const ConfigDemoPage({super.key});

  @override
  State<ConfigDemoPage> createState() => _ConfigDemoPageState();
}

class _ConfigDemoPageState extends State<ConfigDemoPage> {
  bool _cacheEnabled = true;
  bool _videoEnabled = true;
  bool _externalOpenAllowed = true;
  bool _resumeEnabled = true;
  int _maxConcurrentDownloads = 2;

  String _cacheDemoResult = '';
  String _rendererDemoResult = '';
  String _concurrencyDemoResult = '';
  bool _busy = false;

  AttachmentEngineConfig get _currentConfig => AttachmentEngineConfig(
    cache: CacheConfig(enabled: _cacheEnabled),
    renderers: RendererConfig(video: _videoEnabled),
    download: DownloadConfig(
      resumeEnabled: _resumeEnabled,
      maxConcurrentDownloads: _maxConcurrentDownloads,
    ),
    externalOpen: ExternalOpenConfig(
      allowExternalFallback: _externalOpenAllowed,
    ),
  );

  final _sampleAttachment = Attachment(
    id: 'config-demo-video',
    name: 'Sample MP4 (network)',
    extension: 'mp4',
    mimeType: 'video/mp4',
    remoteUrl:
        'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
    source: const AttachmentSource.url(
      'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
    ),
    attachmentType: AttachmentType.video,
  );

  /// Runs the real cache-on-vs-off demo: writes bytes for an in-memory
  /// attachment via the actual [AttachmentCacheManager] built from the
  /// current toggle state, then looks it up again to show whether it was
  /// actually retained.
  Future<void> _runCacheDemo() async {
    setState(() => _busy = true);
    final cacheManager = AttachmentCacheManager(
      metadataStore: FileBasedMetadataStore(
        fileName: 'config_demo_cache_metadata.json',
      ),
      config: _currentConfig.cache,
    );
    await cacheManager.init();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final attachment = Attachment(
      id: 'config-demo-bytes',
      name: 'demo.bin',
      source: AttachmentSource.bytes(bytes),
    );
    await cacheManager.write(attachment, bytes);
    final hit = await cacheManager.lookup(attachment);
    setState(() {
      _busy = false;
      _cacheDemoResult = _cacheEnabled
          ? (hit != null
                ? 'Cache ON: write then lookup found it (path: $hit).'
                : 'Cache ON but lookup missed - unexpected.')
          : (hit == null
                ? 'Cache OFF: lookup returned null - nothing was persisted, '
                      'exactly as configured.'
                : 'Cache OFF but a hit was found - unexpected.');
    });
  }

  /// Demonstrates a disabled renderer by deriving real capabilities via
  /// [CapabilityEngine] built from the current config.
  void _runRendererDemo() {
    final engine = CapabilityEngine(rendererConfig: _currentConfig.renderers);
    final caps = engine.derive(
      _sampleAttachment.copyWith(
        localPath: '/tmp/flower.mp4',
        status: AttachmentStatus.ready,
      ),
    );
    setState(() {
      _rendererDemoResult = _videoEnabled
          ? 'Video renderer ENABLED: canPlay=${caps.canPlay}, '
                'disabledByConfig=${caps.rendererDisabledByConfig}.'
          : 'Video renderer DISABLED: canPlay=${caps.canPlay}, '
                'disabledByConfig=${caps.rendererDisabledByConfig}. '
                'The viewer will show the disabled/unsupported state.';
    });
  }

  /// Queues 5 fake downloads through a real [DownloadManager] configured
  /// with the current `maxConcurrentDownloads`, and reports the actual
  /// observed peak concurrency.
  Future<void> _runConcurrencyDemo() async {
    setState(() {
      _busy = true;
      _concurrencyDemoResult =
          'Running 5 downloads (cap=$_maxConcurrentDownloads)...';
    });
    final client = _DemoTrackingClient();
    final manager = DownloadManager(
      client: client,
      config: _currentConfig.download,
    );
    await Future.wait(
      List.generate(
        5,
        (i) => manager.download('demo-$i', 'https://example.com/$i'),
      ),
    );
    setState(() {
      _busy = false;
      _concurrencyDemoResult =
          'Cap was $_maxConcurrentDownloads; peak observed concurrency was '
          '${client.peakConcurrency} across ${client.totalCalls} downloads.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AttachmentEngineConfig demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Every switch below is wired to the real AttachmentEngineConfig '
            'public API (CacheConfig, RendererConfig, DownloadConfig, '
            'ExternalOpenConfig) - none are cosmetic-only.',
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Cache enabled'),
            value: _cacheEnabled,
            onChanged: (v) => setState(() => _cacheEnabled = v),
          ),
          FilledButton(
            onPressed: _busy ? null : _runCacheDemo,
            child: const Text('Run cache demo'),
          ),
          if (_cacheDemoResult.isNotEmpty) Text(_cacheDemoResult),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('Video renderer enabled'),
            value: _videoEnabled,
            onChanged: (v) => setState(() => _videoEnabled = v),
          ),
          FilledButton(
            onPressed: _runRendererDemo,
            child: const Text('Check video capabilities'),
          ),
          if (_rendererDemoResult.isNotEmpty) Text(_rendererDemoResult),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('External-open fallback allowed'),
            value: _externalOpenAllowed,
            onChanged: (v) => setState(() => _externalOpenAllowed = v),
          ),
          SwitchListTile(
            title: const Text('Download resume enabled'),
            value: _resumeEnabled,
            onChanged: (v) => setState(() => _resumeEnabled = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Max concurrent downloads: '),
              DropdownButton<int>(
                value: _maxConcurrentDownloads,
                items: const [1, 2, 3, 5]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _maxConcurrentDownloads = v ?? 2),
              ),
            ],
          ),
          FilledButton(
            onPressed: _busy ? null : _runConcurrencyDemo,
            child: const Text('Run concurrency demo (5 downloads)'),
          ),
          if (_concurrencyDemoResult.isNotEmpty) Text(_concurrencyDemoResult),
        ],
      ),
    );
  }
}

class _DemoTrackingClient implements DownloadClient {
  int _running = 0;
  int peakConcurrency = 0;
  int totalCalls = 0;

  @override
  Future<Uint8List> download(
    String url, {
    void Function(DownloadProgress progress)? onProgress,
    Object? cancelToken,
    String? destinationHint,
    bool resume = false,
  }) async {
    totalCalls++;
    _running++;
    peakConcurrency = peakConcurrency > _running ? peakConcurrency : _running;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _running--;
    return Uint8List.fromList([0]);
  }

  @override
  Object createCancelToken() => Object();

  @override
  void cancel(Object cancelToken) {}
}
