// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'package:attachment_engine/attachment_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CacheConfig', () {
    test('defaults', () {
      const c = CacheConfig();
      expect(c.enabled, isTrue);
      expect(c.maxTotalSizeBytes, 500 * 1024 * 1024);
      expect(c.maxFileSizeBytes, isNull);
      expect(c.retention, isNull);
      expect(c.thumbnailCachingEnabled, isTrue);
      expect(c.previewCachingEnabled, isTrue);
    });

    test('copyWith overrides each field and keeps the rest', () {
      const base = CacheConfig(
        maxFileSizeBytes: 10,
        retention: Duration(days: 1),
      );
      expect(base.copyWith(enabled: false).enabled, isFalse);
      expect(base.copyWith(maxTotalSizeBytes: 99).maxTotalSizeBytes, 99);
      expect(
        base.copyWith(thumbnailCachingEnabled: false).thumbnailCachingEnabled,
        isFalse,
      );
      expect(
        base.copyWith(previewCachingEnabled: false).previewCachingEnabled,
        isFalse,
      );
      expect(base.copyWith(maxFileSizeBytes: () => 5).maxFileSizeBytes, 5);
      expect(
        base.copyWith(retention: () => const Duration(hours: 2)).retention,
        const Duration(hours: 2),
      );
      expect(base.copyWith(), base);
    });

    test('copyWith can clear nullable fields via a null-returning closure', () {
      const base = CacheConfig(
        maxFileSizeBytes: 10,
        retention: Duration(days: 1),
      );
      expect(
        base.copyWith(maxFileSizeBytes: () => null).maxFileSizeBytes,
        isNull,
      );
      expect(base.copyWith(retention: () => null).retention, isNull);
    });

    test('equality, hashCode and toString', () {
      expect(const CacheConfig(), const CacheConfig());
      expect(const CacheConfig().hashCode, const CacheConfig().hashCode);
      expect(const CacheConfig() == const CacheConfig(enabled: false), isFalse);
      expect(
        const CacheConfig() == const CacheConfig(retention: Duration.zero),
        isFalse,
      );
      expect(const CacheConfig().toString(), 'CacheConfig');
    });

    test('validation boundaries: zero is allowed, file size equal to total is '
        'allowed, zero retention is allowed', () {
      const AttachmentEngineConfig(cache: CacheConfig(maxTotalSizeBytes: 0))
          .validate();
      const AttachmentEngineConfig(
        cache: CacheConfig(maxTotalSizeBytes: 5, maxFileSizeBytes: 5),
      ).validate();
      const AttachmentEngineConfig(cache: CacheConfig(retention: Duration.zero))
          .validate();
    });

    test('validation rejects one-past-the-boundary values with a message '
        'naming the field', () {
      expect(
        () => const AttachmentEngineConfig(
          cache: CacheConfig(maxTotalSizeBytes: 5, maxFileSizeBytes: 6),
        ).validate(),
        throwsA(
          isA<AttachmentConfigValidationError>().having(
            (e) => e.message,
            'message',
            allOf(contains('maxFileSizeBytes'), contains('maxTotalSizeBytes')),
          ),
        ),
      );
      expect(
        () => const AttachmentEngineConfig(
          cache: CacheConfig(retention: Duration(microseconds: -1)),
        ).validate(),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
    });
  });

  group('RendererConfig', () {
    test('all renderers are enabled by default', () {
      const c = RendererConfig();
      for (final t in AttachmentType.values) {
        expect(c.isEnabled(t), isTrue, reason: t.name);
      }
    });

    test('isEnabled reflects exactly one disabled type at a time', () {
      final disabled = <AttachmentType, RendererConfig>{
        AttachmentType.image: const RendererConfig(image: false),
        AttachmentType.pdf: const RendererConfig(pdf: false),
        AttachmentType.document: const RendererConfig(document: false),
        AttachmentType.office: const RendererConfig(office: false),
        AttachmentType.text: const RendererConfig(text: false),
        AttachmentType.csv: const RendererConfig(csv: false),
        AttachmentType.html: const RendererConfig(html: false),
        AttachmentType.scorm: const RendererConfig(scorm: false),
        AttachmentType.h5p: const RendererConfig(h5p: false),
        AttachmentType.video: const RendererConfig(video: false),
        AttachmentType.audio: const RendererConfig(audio: false),
        AttachmentType.archive: const RendererConfig(archive: false),
      };
      for (final e in disabled.entries) {
        for (final t in AttachmentType.values) {
          expect(
            e.value.isEnabled(t),
            t != e.key,
            reason: '${e.key.name} / ${t.name}',
          );
        }
      }
    });

    test('unknown can never be disabled', () {
      const c = RendererConfig(
        image: false,
        pdf: false,
        document: false,
        office: false,
        text: false,
        csv: false,
        html: false,
        scorm: false,
        h5p: false,
        video: false,
        audio: false,
        archive: false,
      );
      expect(c.isEnabled(AttachmentType.unknown), isTrue);
    });

    test('copyWith toggles each flag', () {
      const c = RendererConfig();
      expect(c.copyWith(image: false).image, isFalse);
      expect(c.copyWith(pdf: false).pdf, isFalse);
      expect(c.copyWith(document: false).document, isFalse);
      expect(c.copyWith(office: false).office, isFalse);
      expect(c.copyWith(text: false).text, isFalse);
      expect(c.copyWith(csv: false).csv, isFalse);
      expect(c.copyWith(html: false).html, isFalse);
      expect(c.copyWith(scorm: false).scorm, isFalse);
      expect(c.copyWith(h5p: false).h5p, isFalse);
      expect(c.copyWith(video: false).video, isFalse);
      expect(c.copyWith(audio: false).audio, isFalse);
      expect(c.copyWith(archive: false).archive, isFalse);
      expect(c.copyWith(), c);
      expect(c.copyWith(pdf: false).copyWith(pdf: true), c);
    });

    test('equality and hashCode', () {
      expect(const RendererConfig(), const RendererConfig());
      expect(const RendererConfig().hashCode, const RendererConfig().hashCode);
      expect(
        const RendererConfig() == const RendererConfig(archive: false),
        isFalse,
      );
    });
  });

  group('DownloadConfig', () {
    test('defaults', () {
      const c = DownloadConfig();
      expect(c.connectTimeout, const Duration(seconds: 15));
      expect(c.receiveTimeout, const Duration(seconds: 30));
      expect(c.maxRetries, 3);
      expect(c.retryBackoff, DownloadRetryBackoff.exponential);
      expect(c.retryBaseDelay, const Duration(milliseconds: 500));
      expect(c.maxConcurrentDownloads, 3);
      expect(c.resumeEnabled, isTrue);
    });

    test('copyWith overrides each field', () {
      const c = DownloadConfig();
      expect(
        c.copyWith(connectTimeout: const Duration(seconds: 1)).connectTimeout,
        const Duration(seconds: 1),
      );
      expect(
        c.copyWith(receiveTimeout: const Duration(seconds: 2)).receiveTimeout,
        const Duration(seconds: 2),
      );
      expect(c.copyWith(maxRetries: 9).maxRetries, 9);
      expect(
        c.copyWith(retryBackoff: DownloadRetryBackoff.none).retryBackoff,
        DownloadRetryBackoff.none,
      );
      expect(
        c.copyWith(retryBaseDelay: Duration.zero).retryBaseDelay,
        Duration.zero,
      );
      expect(c.copyWith(maxConcurrentDownloads: 1).maxConcurrentDownloads, 1);
      expect(c.copyWith(resumeEnabled: false).resumeEnabled, isFalse);
      expect(c.copyWith(), c);
    });

    test('equality and hashCode', () {
      expect(const DownloadConfig(), const DownloadConfig());
      expect(const DownloadConfig().hashCode, const DownloadConfig().hashCode);
      expect(
        const DownloadConfig() == const DownloadConfig(maxRetries: 4),
        isFalse,
      );
      expect(
        const DownloadConfig() ==
            const DownloadConfig(retryBackoff: DownloadRetryBackoff.linear),
        isFalse,
      );
    });

    test('validation: zero retry delay and zero retries are fine, negative '
        'values and non-positive durations are not', () {
      const AttachmentEngineConfig(
        download: DownloadConfig(retryBaseDelay: Duration.zero, maxRetries: 0),
      ).validate();
      AttachmentConfigValidationError? error;
      void check(DownloadConfig c) {
        try {
          AttachmentEngineConfig(download: c).validate();
        } on AttachmentConfigValidationError catch (e) {
          error = e;
        }
      }

      check(const DownloadConfig(retryBaseDelay: Duration(microseconds: -1)));
      expect(error?.message, contains('retryBaseDelay'));
      error = null;
      check(const DownloadConfig(connectTimeout: Duration.zero));
      expect(error?.message, contains('connectTimeout'));
      error = null;
      check(const DownloadConfig(receiveTimeout: Duration(seconds: -1)));
      expect(error?.message, contains('receiveTimeout'));
      error = null;
      check(const DownloadConfig(maxRetries: -1));
      expect(error?.message, contains('maxRetries'));
      error = null;
      check(const DownloadConfig(maxConcurrentDownloads: 0));
      expect(error?.message, contains('maxConcurrentDownloads'));
    });

    test('the error type is an ArgumentError carrying its message', () {
      final e = AttachmentConfigValidationError('bad');
      expect(e, isA<ArgumentError>());
      expect(e.message, 'bad');
      expect(e.toString(), contains('bad'));
    });
  });

  group('PreviewConfig', () {
    test('defaults, copyWith, equality', () {
      const c = PreviewConfig();
      expect(c.thumbnailsEnabled, isTrue);
      expect(c.lazyLoading, isTrue);
      expect(c.preloadPolicy, PreviewPreloadPolicy.none);
      expect(c.copyWith(thumbnailsEnabled: false).thumbnailsEnabled, isFalse);
      expect(c.copyWith(lazyLoading: false).lazyLoading, isFalse);
      expect(
        c.copyWith(preloadPolicy: PreviewPreloadPolicy.all).preloadPolicy,
        PreviewPreloadPolicy.all,
      );
      expect(c.copyWith(), c);
      expect(c.hashCode, const PreviewConfig().hashCode);
      expect(
        c == const PreviewConfig(preloadPolicy: PreviewPreloadPolicy.adjacent),
        isFalse,
      );
      expect(c == const PreviewConfig(lazyLoading: false), isFalse);
      expect(c == const PreviewConfig(thumbnailsEnabled: false), isFalse);
    });

    test('enum values', () {
      expect(PreviewPreloadPolicy.values, hasLength(3));
      expect(DownloadRetryBackoff.values, hasLength(3));
    });
  });

  group('ExternalOpenConfig', () {
    test('defaults, copyWith, equality', () {
      const c = ExternalOpenConfig();
      expect(c.allowExternalFallback, isTrue);
      expect(
        c.copyWith(allowExternalFallback: false).allowExternalFallback,
        isFalse,
      );
      expect(c.copyWith(), c);
      expect(
        c == const ExternalOpenConfig(allowExternalFallback: false),
        isFalse,
      );
      expect(c.hashCode, const ExternalOpenConfig().hashCode);
    });
  });

  group('AttachmentEngineConfig', () {
    test('defaults() equals the plain constructor', () {
      expect(
        const AttachmentEngineConfig.defaults(),
        const AttachmentEngineConfig(),
      );
    });

    test('copyWith replaces each sub-config independently', () {
      const base = AttachmentEngineConfig();
      const cache = CacheConfig(enabled: false);
      const renderers = RendererConfig(pdf: false);
      const download = DownloadConfig(maxRetries: 1);
      const preview = PreviewConfig(lazyLoading: false);
      const external = ExternalOpenConfig(allowExternalFallback: false);
      expect(base.copyWith(cache: cache).cache, cache);
      expect(base.copyWith(renderers: renderers).renderers, renderers);
      expect(base.copyWith(download: download).download, download);
      expect(base.copyWith(preview: preview).preview, preview);
      expect(base.copyWith(externalOpen: external).externalOpen, external);
      expect(base.copyWith(), base);
      expect(base.copyWith(cache: cache).renderers, base.renderers);
    });

    test('equality and hashCode cover every sub-config', () {
      expect(
        const AttachmentEngineConfig().hashCode,
        const AttachmentEngineConfig().hashCode,
      );
      expect(
        const AttachmentEngineConfig() ==
            const AttachmentEngineConfig(
              preview: PreviewConfig(lazyLoading: false),
            ),
        isFalse,
      );
      expect(
        const AttachmentEngineConfig() ==
            const AttachmentEngineConfig(
              externalOpen: ExternalOpenConfig(allowExternalFallback: false),
            ),
        isFalse,
      );
    });

    test('validate surfaces cache and download errors, ignores others', () {
      expect(
        () => const AttachmentEngineConfig(
          cache: CacheConfig(maxTotalSizeBytes: -1),
        ).validate(),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
      expect(
        () => const AttachmentEngineConfig(
          download: DownloadConfig(maxConcurrentDownloads: -3),
        ).validate(),
        throwsA(isA<AttachmentConfigValidationError>()),
      );
      const AttachmentEngineConfig(
        renderers: RendererConfig(pdf: false),
        preview: PreviewConfig(lazyLoading: false),
        externalOpen: ExternalOpenConfig(allowExternalFallback: false),
      ).validate();
    });
  });
}
