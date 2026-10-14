// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:attachment_engine/attachment_engine.dart';
import 'package:attachment_engine/src/platform/platform_info.dart';
import 'package:attachment_engine/src/util/value_equatable.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pair extends ValueEquatable {
  const _Pair(this.a, this.b);
  final Object? a;
  final Object? b;

  @override
  List<Object?> get props => [a, b];
}

class _Loud extends _Pair {
  const _Loud(super.a, super.b);

  @override
  bool get stringify => true;
}

class _OtherPair extends _Pair {
  const _OtherPair(super.a, super.b);
}

void main() {
  group('ValueEquatable', () {
    test('identical instances and equal props are equal with equal hashes', () {
      const a = _Pair(1, 'x');
      expect(a == a, isTrue);
      expect(const _Pair(1, 'x'), const _Pair(1, 'x'));
      expect(const _Pair(1, 'x').hashCode, const _Pair(1, 'x').hashCode);
    });

    test('different props or different runtimeType are not equal', () {
      expect(const _Pair(1, 'x') == const _Pair(2, 'x'), isFalse);
      expect(const _Pair(1, 'x') == const _OtherPair(1, 'x'), isFalse);
      expect(const _Pair(1, 'x') == (Object()), isFalse);
      expect(const _Pair(null, null) == const _Pair(null, 0), isFalse);
    });

    test('nested lists are compared and hashed deeply', () {
      final a = _Pair([1, 2, 3], const [4]);
      final b = _Pair([1, 2, 3], const [4]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == _Pair([1, 2], const [4]), isFalse);
      expect(a == _Pair([1, 2, 4], const [4]), isFalse);
    });

    test('maps are order-insensitive and compared deeply', () {
      final a = _Pair({
        'k': 1,
        'j': [1, 2],
      }, null);
      final b = _Pair({
        'j': [1, 2],
        'k': 1,
      }, null);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(_Pair({'k': 1}, null) == _Pair({'k': 2}, null), isFalse);
      expect(_Pair({'k': 1}, null) == _Pair({'z': 1}, null), isFalse);
      expect(_Pair({'k': 1}, null) == _Pair({'k': 1, 'z': 2}, null), isFalse);
    });

    test('sets are order-insensitive and compared by membership', () {
      final a = _Pair({1, 2, 3}, null);
      final b = _Pair({3, 2, 1}, null);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == _Pair({1, 2}, null), isFalse);
      expect(a == _Pair({1, 2, 9}, null), isFalse);
    });

    test('empty collections are equal to each other, not to null', () {
      expect(_Pair(const [], null), _Pair(<Object?>[], null));
      expect(_Pair(const {}, null), _Pair(<Object?, Object?>{}, null));
      expect(_Pair(const [], null) == const _Pair(null, null), isFalse);
    });

    test('a list is never equal to a set with the same elements', () {
      expect(_Pair([1], null) == _Pair({1}, null), isFalse);
    });

    test('toString prints only the type unless stringify is true', () {
      expect(const _Pair(1, 2).toString(), '_Pair');
      expect(const _Loud(1, 'two').toString(), '_Loud(1, two)');
      expect(const _Loud(null, null).toString(), '_Loud(null, null)');
    });
  });

  group('AttachmentSource', () {
    test('factories return the matching concrete subtype', () {
      expect(
        const AttachmentSource.url('u'),
        isA<UrlAttachmentSource>().having((s) => s.url, 'url', 'u'),
      );
      expect(
        const AttachmentSource.file('/p'),
        isA<FileAttachmentSource>().having((s) => s.path, 'path', '/p'),
      );
      expect(
        AttachmentSource.bytes(Uint8List(0), suggestedName: 'n'),
        isA<BytesAttachmentSource>().having(
          (s) => s.suggestedName,
          'suggestedName',
          'n',
        ),
      );
      expect(
        const AttachmentSource.cache('k'),
        isA<CacheAttachmentSource>().having((s) => s.cacheKey, 'key', 'k'),
      );
      expect(
        const AttachmentSource.serverAttachment('s'),
        isA<ServerAttachmentSource>().having((s) => s.attachmentId, 'id', 's'),
      );
      expect(
        const AttachmentSource.stream('st'),
        isA<StreamAttachmentSource>().having((s) => s.streamId, 'id', 'st'),
      );
    });

    test('equality and hashCode are value-based per subtype', () {
      expect(const AttachmentSource.url('u'), const AttachmentSource.url('u'));
      expect(
        const AttachmentSource.url('u').hashCode,
        const AttachmentSource.url('u').hashCode,
      );
      expect(
        const AttachmentSource.url('x') == const AttachmentSource.file('x'),
        isFalse,
      );
      expect(
        const AttachmentSource.cache('x') ==
            const AttachmentSource.serverAttachment('x'),
        isFalse,
      );
      expect(
        const AttachmentSource.stream('x') == const AttachmentSource.cache('x'),
        isFalse,
      );
      expect(
        const AttachmentSource.file('/a') == const AttachmentSource.file('/b'),
        isFalse,
      );
      expect(
        const AttachmentSource.serverAttachment('1'),
        const AttachmentSource.serverAttachment('1'),
      );
      expect(
        const AttachmentSource.stream('1'),
        const AttachmentSource.stream('1'),
      );
      expect(
        const AttachmentSource.cache('1'),
        const AttachmentSource.cache('1'),
      );
      expect(
        const AttachmentSource.file('1'),
        const AttachmentSource.file('1'),
      );
    });

    test('bytes sources compare contents, not buffer identity', () {
      final a = AttachmentSource.bytes(Uint8List.fromList([1, 2, 3]));
      final b = AttachmentSource.bytes(Uint8List.fromList([1, 2, 3]));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a == AttachmentSource.bytes(Uint8List.fromList([1, 2, 4])),
        isFalse,
      );
      expect(
        a ==
            AttachmentSource.bytes(
              Uint8List.fromList([1, 2, 3]),
              suggestedName: 'n',
            ),
        isFalse,
      );
      expect(
        AttachmentSource.bytes(Uint8List(0)),
        AttachmentSource.bytes(Uint8List(0)),
      );
    });

    test('empty and very long string payloads are accepted verbatim', () {
      expect((const AttachmentSource.url('') as UrlAttachmentSource).url, '');
      final long = 'a' * 100000;
      expect((AttachmentSource.url(long) as UrlAttachmentSource).url, long);
    });
  });

  group('Attachment', () {
    const base = Attachment(
      id: 'id-1',
      name: 'n',
      source: AttachmentSource.url('https://x/y'),
    );

    test('defaults are the minimal-usage values', () {
      expect(base.attachmentType, AttachmentType.unknown);
      expect(base.status, AttachmentStatus.discovered);
      expect(base.capabilities, AttachmentCapabilities.none);
      expect(base.metadata, isEmpty);
      expect(base.localPath, isNull);
      expect(base.fileName, isNull);
      expect(base.duration, isNull);
    });

    test('stableIdentity prefers cacheKey, then id, never the URL', () {
      expect(base.stableIdentity, 'id-1');
      expect(base.copyWith(cacheKey: 'ck').stableIdentity, 'ck');
      expect(
        base.copyWith(remoteUrl: 'https://signed?x=1').stableIdentity,
        'id-1',
      );
      expect(base.copyWith(cacheKey: '').stableIdentity, '');
    });

    test('copyWith replaces every field and keeps the others', () {
      final now = DateTime.utc(2026, 1, 2);
      final full = base.copyWith(
        id: 'i2',
        name: 'n2',
        source: const AttachmentSource.file('/f'),
        fileName: 'f.pdf',
        extension: 'pdf',
        mimeType: 'application/pdf',
        size: 10,
        remoteUrl: 'https://r',
        localPath: '/l',
        cacheKey: 'ck',
        checksum: 'abc',
        createdAt: now,
        updatedAt: now,
        expiresAt: now,
        duration: const Duration(seconds: 3),
        width: 4,
        height: 5,
        attachmentType: AttachmentType.pdf,
        status: AttachmentStatus.ready,
        capabilities: const AttachmentCapabilities(canShare: true),
        metadata: const {'k': 1},
      );
      expect(full.id, 'i2');
      expect(full.name, 'n2');
      expect(full.source, const AttachmentSource.file('/f'));
      expect(full.fileName, 'f.pdf');
      expect(full.extension, 'pdf');
      expect(full.mimeType, 'application/pdf');
      expect(full.size, 10);
      expect(full.remoteUrl, 'https://r');
      expect(full.localPath, '/l');
      expect(full.cacheKey, 'ck');
      expect(full.checksum, 'abc');
      expect(full.createdAt, now);
      expect(full.updatedAt, now);
      expect(full.expiresAt, now);
      expect(full.duration, const Duration(seconds: 3));
      expect(full.width, 4);
      expect(full.height, 5);
      expect(full.attachmentType, AttachmentType.pdf);
      expect(full.status, AttachmentStatus.ready);
      expect(full.capabilities.canShare, isTrue);
      expect(full.metadata, {'k': 1});
      expect(full.copyWith(), full);
    });

    test('copyWith cannot clear a nullable field back to null', () {
      final withPath = base.copyWith(localPath: '/p');
      expect(withPath.copyWith(localPath: null).localPath, '/p');
    });

    test('equality covers every prop incl. nested metadata', () {
      final a = base.copyWith(
        metadata: {
          'a': [1, 2],
        },
      );
      final b = base.copyWith(
        metadata: {
          'a': [1, 2],
        },
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a ==
            base.copyWith(
              metadata: {
                'a': [1, 3],
              },
            ),
        isFalse,
      );
      expect(base == base.copyWith(name: 'other'), isFalse);
      expect(base == base.copyWith(size: 0), isFalse);
      expect(base.toString(), 'Attachment');
    });

    test('boundary values: zero size, empty id/name, extreme dimensions', () {
      final a = const Attachment(
        id: '',
        name: '',
        source: AttachmentSource.url(''),
        size: 0,
        width: 0,
        height: 0,
        duration: Duration.zero,
      );
      expect(a.stableIdentity, '');
      expect(a.size, 0);
      final huge = a.copyWith(size: 1 << 62, width: 1 << 30);
      expect(huge.size, 1 << 62);
    });
  });

  group('AttachmentCapabilities', () {
    test('none has every flag false', () {
      const c = AttachmentCapabilities.none;
      expect(c.canPreview, isFalse);
      expect(c.canOpen, isFalse);
      expect(c.canPlay, isFalse);
      expect(c.canDownload, isFalse);
      expect(c.canShare, isFalse);
      expect(c.canCache, isFalse);
      expect(c.canOpenExternally, isFalse);
      expect(c.canDeleteCache, isFalse);
      expect(c.rendererDisabledByConfig, isFalse);
    });

    test('copyWith overrides each flag independently', () {
      const none = AttachmentCapabilities.none;
      expect(none.copyWith(canPreview: true).canPreview, isTrue);
      expect(none.copyWith(canOpen: true).canOpen, isTrue);
      expect(none.copyWith(canPlay: true).canPlay, isTrue);
      expect(none.copyWith(canDownload: true).canDownload, isTrue);
      expect(none.copyWith(canShare: true).canShare, isTrue);
      expect(none.copyWith(canCache: true).canCache, isTrue);
      expect(none.copyWith(canOpenExternally: true).canOpenExternally, isTrue);
      expect(none.copyWith(canDeleteCache: true).canDeleteCache, isTrue);
      expect(
        none.copyWith(rendererDisabledByConfig: true).rendererDisabledByConfig,
        isTrue,
      );
      final all = const AttachmentCapabilities(
        canPreview: true,
        canShare: true,
      );
      expect(all.copyWith(canPreview: false).canShare, isTrue);
      expect(all.copyWith(), all);
    });

    test('equality and hashCode follow the flags', () {
      expect(
        const AttachmentCapabilities(canPlay: true),
        const AttachmentCapabilities(canPlay: true),
      );
      expect(
        const AttachmentCapabilities(canPlay: true).hashCode,
        const AttachmentCapabilities(canPlay: true).hashCode,
      );
      expect(
        const AttachmentCapabilities(canPlay: true) ==
            const AttachmentCapabilities(canOpen: true),
        isFalse,
      );
    });
  });

  group('ResolvedAttachment', () {
    const attachment = Attachment(
      id: 'a',
      name: 'a',
      source: AttachmentSource.file('/a'),
    );

    test('fromCache defaults to false and participates in equality', () {
      const r = ResolvedAttachment(
        attachment: attachment,
        localPath: '/a',
        capabilities: AttachmentCapabilities.none,
      );
      expect(r.fromCache, isFalse);
      expect(
        r,
        const ResolvedAttachment(
          attachment: attachment,
          localPath: '/a',
          capabilities: AttachmentCapabilities.none,
        ),
      );
      expect(
        r.hashCode,
        const ResolvedAttachment(
          attachment: attachment,
          localPath: '/a',
          capabilities: AttachmentCapabilities.none,
        ).hashCode,
      );
      expect(
        r ==
            const ResolvedAttachment(
              attachment: attachment,
              localPath: '/a',
              capabilities: AttachmentCapabilities.none,
              fromCache: true,
            ),
        isFalse,
      );
      expect(
        r ==
            const ResolvedAttachment(
              attachment: attachment,
              localPath: '/b',
              capabilities: AttachmentCapabilities.none,
            ),
        isFalse,
      );
    });
  });

  group('AttachmentFailure', () {
    final all = <AttachmentFailure>[
      const AttachmentNotFound(),
      const UnsupportedAttachment(),
      const InvalidSource(),
      const NetworkUnavailable(),
      const DownloadFailed(),
      const CacheFailed(),
      const ExpiredUrl(),
      const Unauthorized(),
      const PermissionDenied(),
      const CorruptedFile(),
      const InsufficientStorage(),
      const RendererFailed(),
      const PlaybackFailed(),
      const ConversionFailed(),
      const UnknownFailure(),
      const RendererDisabledByConfig(),
      const ExternalOpenDisabled(),
    ];

    tearDown(() => AttachmentLocalizations.messageOverride = null);

    test('every failure has a distinct non-empty default message', () {
      final messages = all.map((f) => f.localizedMessage).toList();
      expect(messages.every((m) => m.isNotEmpty), isTrue);
      expect(messages.toSet().length, all.length);
    });

    test('equality is by runtime type and cause', () {
      expect(const DownloadFailed(), const DownloadFailed());
      expect(const DownloadFailed().hashCode, const DownloadFailed().hashCode);
      expect(const DownloadFailed() == const CacheFailed(), isFalse);
      expect(
        const DownloadFailed(cause: 'a') == const DownloadFailed(),
        isFalse,
      );
      expect(
        const DownloadFailed(cause: 'a'),
        const DownloadFailed(cause: 'a'),
      );
      expect(const CorruptedFile().cause, isNull);
      expect(const UnknownFailure(cause: 42).cause, 42);
    });

    test('messageOverride wins and a null return falls back to default', () {
      AttachmentLocalizations.messageOverride = (f) =>
          f is NetworkUnavailable ? 'offline!' : null;
      expect(const NetworkUnavailable().localizedMessage, 'offline!');
      expect(
        const DownloadFailed().localizedMessage,
        'The attachment failed to download.',
      );
      AttachmentLocalizations.messageOverride = (_) => '';
      expect(const DownloadFailed().localizedMessage, '');
    });

    test('AttachmentResolutionException carries its failure', () {
      final e = AttachmentResolutionException(const ExpiredUrl());
      expect(e.failure, const ExpiredUrl());
    });
  });

  group('AttachmentType / AttachmentStatus', () {
    test('enums expose stable names', () {
      expect(AttachmentType.values.map((t) => t.name), contains('scorm'));
      expect(AttachmentType.values.last, AttachmentType.unknown);
      expect(AttachmentStatus.values.first, AttachmentStatus.discovered);
      expect(AttachmentStatus.values.last, AttachmentStatus.cleaned);
    });
  });

  group('sanitizeForLog', () {
    test('strips query strings and signed-url params', () {
      expect(
        sanitizeForLog('https://cdn.example.com/f.pdf?token=secret&x=1'),
        'https://cdn.example.com/f.pdf',
      );
    });

    test('leaves query-less urls unchanged', () {
      expect(
        sanitizeForLog('https://cdn.example.com/a/b.pdf'),
        'https://cdn.example.com/a/b.pdf',
      );
    });

    test('drops userinfo credentials', () {
      expect(
        sanitizeForLog('https://user:pw@host.example/p?q=1'),
        'https://host.example/p',
      );
    });

    test('empty string, lone question mark and unparsable input', () {
      expect(sanitizeForLog(''), '');
      expect(sanitizeForLog('?secret=1'), '');
      expect(sanitizeForLog('http://[bad'), 'http://[bad');
    });

    test('very long url is processed without truncation of the path', () {
      final path = 'a' * 20000;
      expect(sanitizeForLog('https://h/$path?x=1'), 'https://h/$path');
    });
  });

  group('NoopAttachmentDiagnosticsSink', () {
    test('accepts every callback without throwing', () {
      const sink = NoopAttachmentDiagnosticsSink();
      sink
        ..onResolutionStart('a')
        ..onResolutionComplete('a', duration: Duration.zero, cacheHit: false)
        ..onResolutionFailed('a', failureType: 'X')
        ..onDownloadStart('a')
        ..onDownloadComplete('a', duration: Duration.zero, bytes: 0)
        ..onDownloadFailed('a', failureType: 'X')
        ..onPlaybackError('a', failureType: 'X');
    });
  });

  group('DefaultPlatformInfo', () {
    test('mirrors dart:io Platform', () {
      const info = DefaultPlatformInfo();
      expect(info.isIOS, Platform.isIOS);
      expect(info.isAndroid, Platform.isAndroid);
    });
  });
}
