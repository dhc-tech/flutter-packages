import 'dart:typed_data';

import '../models/attachment_type.dart';

/// A single magic-byte signature: bytes to match at a given [offset].
class MagicSignature {
  const MagicSignature(this.type, this.bytes, {this.offset = 0});

  final AttachmentType type;
  final List<int> bytes;
  final int offset;

  bool matches(Uint8List data) {
    if (data.length < offset + bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (data[offset + i] != bytes[i]) return false;
    }
    return true;
  }
}

/// Known magic-byte signatures for common attachment formats. Checked in
/// order; more specific signatures should be listed before generic ones
/// (e.g. zip-based office/scorm formats are disambiguated by extension
/// after the generic zip signature matches).
final List<MagicSignature> kMagicSignatures = [
  MagicSignature(AttachmentType.image, [0x89, 0x50, 0x4E, 0x47]), // PNG
  MagicSignature(AttachmentType.image, [0xFF, 0xD8, 0xFF]), // JPEG
  MagicSignature(AttachmentType.image, [0x47, 0x49, 0x46, 0x38]), // GIF8
  MagicSignature(AttachmentType.image, [
    0x52,
    0x49,
    0x46,
    0x46,
  ], offset: 0), // RIFF (webp container)
  MagicSignature(AttachmentType.pdf, [0x25, 0x50, 0x44, 0x46]), // %PDF
  MagicSignature(AttachmentType.video, [
    0x66,
    0x74,
    0x79,
    0x70,
  ], offset: 4), // ftyp -> mp4/mov
  MagicSignature(AttachmentType.audio, [0x49, 0x44, 0x33]), // ID3 (mp3)
  MagicSignature(AttachmentType.audio, [0xFF, 0xFB]), // mp3 frame sync
  MagicSignature(AttachmentType.audio, [
    0x52,
    0x49,
    0x46,
    0x46,
  ]), // RIFF (wav container)
  MagicSignature(AttachmentType.archive, [
    0x50,
    0x4B,
    0x03,
    0x04,
  ]), // ZIP/office/scorm
  MagicSignature(AttachmentType.archive, [0x50, 0x4B, 0x05, 0x06]), // empty ZIP
];

/// Detects a type from raw bytes using [kMagicSignatures]. Returns null if
/// no signature matches. Note WEBP and WAV both use a RIFF container; the
/// caller should disambiguate further using bytes 8-11 if needed.
AttachmentType? detectTypeFromMagicBytes(Uint8List bytes) {
  for (final sig in kMagicSignatures) {
    if (sig.matches(bytes)) {
      if (sig.bytes.length == 4 &&
          sig.bytes[0] == 0x52 &&
          sig.bytes[1] == 0x49 &&
          sig.bytes[2] == 0x46 &&
          sig.bytes[3] == 0x46) {
        // RIFF: disambiguate WEBP vs WAV using the format tag at byte 8.
        if (bytes.length >= 12) {
          final tag = String.fromCharCodes(bytes.sublist(8, 12));
          if (tag == 'WEBP') return AttachmentType.image;
          if (tag == 'WAVE') return AttachmentType.audio;
        }
        continue;
      }
      return sig.type;
    }
  }
  return null;
}
