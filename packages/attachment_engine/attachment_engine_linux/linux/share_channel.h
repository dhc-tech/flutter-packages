// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.
//
// NOTE: This file has NOT been compiled or verified on this machine.
//
// Deliberately empty of a real implementation. There is no universal
// Linux OS-level share mechanism analogous to Android's
// `Intent.ACTION_SEND` or Windows's `DataTransferManager`/
// `IDataTransferManagerInterop`:
//
//   - `xdg-desktop-portal`'s `org.freedesktop.portal.OpenURI` interface
//     (https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.OpenURI.html)
//     only exposes `OpenURI`/`OpenFile`/`OpenDirectory` — "opens with a
//     user-chosen application", not a content-share broadcast to
//     share-target apps. There is no `org.freedesktop.portal.Share`
//     interface in the portal spec.
//   - Desktop-environment-specific mechanisms exist (e.g. GNOME's
//     `Nautilus` "send to" extensions, KDE's Purpose framework/KShareData),
//     but none of them is a portal-mediated, sandboxed, DE-agnostic API —
//     shelling out to one would silently do nothing (or crash) on every
//     other desktop environment, which is worse than throwing.
//
// This matches the conclusion the existing pure-Dart fallback in
// `attachment_engine_desktop_impl.dart` already reached before this native
// pass. `shareFile`/`shareText` are therefore intentionally left
// unregistered on Linux; the Dart side (`attachment_engine_linux.dart`)
// keeps throwing `UnimplementedError` directly rather than round-tripping
// through a method channel with no native handler.

#ifndef PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_SHARE_CHANNEL_H_
#define PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_SHARE_CHANNEL_H_

// Intentionally no declarations: see the file comment above.

#endif  // PACKAGES_ATTACHMENT_ENGINE_LINUX_LINUX_SHARE_CHANNEL_H_
