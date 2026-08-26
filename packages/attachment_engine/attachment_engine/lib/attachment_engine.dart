// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// Universal Attachment Management Engine.
///
/// A single reusable Flutter plugin for resolving, caching, downloading,
/// detecting, rendering, previewing, sharing and managing attachments of
/// every common type (image, pdf, video, audio, html, text, office,
/// archive, scorm, and more). See README.md for architecture and usage.
library;

// Config
export 'src/config/attachment_engine_config.dart';

// Models
export 'src/models/attachment.dart';
export 'src/models/attachment_capabilities.dart';
export 'src/models/attachment_failure.dart';
export 'src/models/attachment_source.dart';
export 'src/models/attachment_status.dart';
export 'src/models/attachment_type.dart';
export 'src/models/resolved_attachment.dart';

// Detection
export 'src/detection/format_detector.dart';
export 'src/detection/magic_bytes.dart';
export 'src/detection/mime_table.dart';

// Archive
export 'src/archive/zip_reader.dart';

// Native channel wrappers
export 'src/native/native_audio_channel.dart';
export 'src/native/native_download_channel.dart';
export 'src/native/native_open_channel.dart';
export 'src/native/native_paths_channel.dart';
export 'src/native/native_pdf_channel.dart';
export 'src/native/native_share_channel.dart';
export 'src/native/native_video_channel.dart';

// Cache
export 'src/cache/attachment_cache_manager.dart';
export 'src/cache/cache_metadata_store.dart';
export 'src/cache/cache_policy.dart';

// Download
export 'src/download/download_manager.dart';
export 'src/download/download_queue.dart';

// Concurrency
export 'src/concurrency/in_flight_registry.dart';

// Resolver
export 'src/resolver/attachment_resolver.dart';

// Capability
export 'src/capability/capability_engine.dart';

// Renderers
export 'src/renderers/archive_renderer.dart';
export 'src/renderers/audio_renderer.dart';
export 'src/renderers/csv_renderer.dart';
export 'src/renderers/html_renderer.dart';
export 'src/renderers/image_renderer.dart';
export 'src/renderers/office_renderer.dart';
export 'src/renderers/pdf_renderer.dart';
export 'src/renderers/renderer.dart';
export 'src/renderers/scorm_renderer.dart';
export 'src/renderers/text_renderer.dart';
export 'src/renderers/unknown_renderer.dart';
export 'src/renderers/video_renderer.dart';

// Manager
export 'src/manager/attachment_manager.dart';

// UI
export 'src/ui/attachment_actions.dart';
export 'src/ui/attachment_download_progress.dart';
export 'src/ui/attachment_error_view.dart';
export 'src/ui/attachment_grid.dart';
export 'src/ui/attachment_list.dart';
export 'src/ui/attachment_preview.dart';
export 'src/ui/attachment_thumbnail.dart';
export 'src/ui/attachment_tile.dart';
export 'src/ui/attachment_viewer.dart';

// Observability
export 'src/observability/attachment_diagnostics.dart';
