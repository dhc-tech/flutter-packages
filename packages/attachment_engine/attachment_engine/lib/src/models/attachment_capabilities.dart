// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import '../util/value_equatable.dart';

/// Set of actions available for a given attachment, derived by
/// `CapabilityEngine` from its type, status and source.
class AttachmentCapabilities extends ValueEquatable {
  const AttachmentCapabilities({
    this.canPreview = false,
    this.canOpen = false,
    this.canPlay = false,
    this.canDownload = false,
    this.canShare = false,
    this.canCache = false,
    this.canOpenExternally = false,
    this.canDeleteCache = false,
    this.rendererDisabledByConfig = false,
  });

  /// No actions available at all (e.g. unresolvable / failed permanently).
  static const AttachmentCapabilities none = AttachmentCapabilities();

  final bool canPreview;
  final bool canOpen;
  final bool canPlay;
  final bool canDownload;
  final bool canShare;
  final bool canCache;
  final bool canOpenExternally;
  final bool canDeleteCache;

  /// True when this attachment's type has a renderer, but it was explicitly
  /// disabled via `RendererConfig` (as opposed to having no renderer at
  /// all). Host UI can use this to show a "disabled by configuration"
  /// message distinct from "unsupported format".
  final bool rendererDisabledByConfig;

  AttachmentCapabilities copyWith({
    bool? canPreview,
    bool? canOpen,
    bool? canPlay,
    bool? canDownload,
    bool? canShare,
    bool? canCache,
    bool? canOpenExternally,
    bool? canDeleteCache,
    bool? rendererDisabledByConfig,
  }) {
    return AttachmentCapabilities(
      canPreview: canPreview ?? this.canPreview,
      canOpen: canOpen ?? this.canOpen,
      canPlay: canPlay ?? this.canPlay,
      canDownload: canDownload ?? this.canDownload,
      canShare: canShare ?? this.canShare,
      canCache: canCache ?? this.canCache,
      canOpenExternally: canOpenExternally ?? this.canOpenExternally,
      canDeleteCache: canDeleteCache ?? this.canDeleteCache,
      rendererDisabledByConfig:
          rendererDisabledByConfig ?? this.rendererDisabledByConfig,
    );
  }

  @override
  List<Object?> get props => [
    canPreview,
    canOpen,
    canPlay,
    canDownload,
    canShare,
    canCache,
    canOpenExternally,
    canDeleteCache,
    rendererDisabledByConfig,
  ];
}
