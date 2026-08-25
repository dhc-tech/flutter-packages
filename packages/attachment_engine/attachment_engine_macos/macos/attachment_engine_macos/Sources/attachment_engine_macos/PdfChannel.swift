// Copyright 2026 DHC Tech
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Cocoa
import FlutterMacOS
import PDFKit

/// Uses PDFKit (`PDFDocument`, `PDFPage.thumbnail`) to open a PDF and
/// render pages to PNG bitmaps, keyed by an opaque handle string so the
/// Dart side can hold multiple documents open concurrently. Identical
/// contract to the iOS implementation; only the bitmap-to-PNG encoding
/// step differs (`NSBitmapImageRep` instead of `UIImage.pngData()`, since
/// `PDFPage.thumbnail(of:for:)` returns `NSImage` on macOS).
///
/// Implements the Pigeon-generated `PdfHostApi` (see `Messages.g.swift`,
/// codegen'd from
/// `attachment_engine_platform_interface/pigeons/messages.dart`) instead
/// of a hand-written `FlutterMethodChannel`.
class PdfChannel: NSObject, PdfHostApi {
  private var openDocs: [String: PDFDocument] = [:]

  func register(with messenger: FlutterBinaryMessenger) {
    PdfHostApiSetup.setUp(binaryMessenger: messenger, api: self)
  }

  func unregister(with messenger: FlutterBinaryMessenger) {
    PdfHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    openDocs.removeAll()
  }

  func open(path: String) async throws -> PdfOpenResultMessage {
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
      throw PigeonError(code: "open_failed", message: "Could not open PDF at \(path)", details: nil)
    }
    let handle = UUID().uuidString
    openDocs[handle] = document
    return PdfOpenResultMessage(handle: handle, pageCount: Int64(document.pageCount))
  }

  func renderPage(handle: String, index: Int64, width: Int64, height: Int64) async throws
    -> FlutterStandardTypedData
  {
    guard let document = openDocs[handle] else {
      throw PigeonError(code: "bad_handle", message: "Unknown PDF handle", details: nil)
    }
    guard let page = document.page(at: Int(index)) else {
      throw PigeonError(code: "render_failed", message: "Invalid page index \(index)", details: nil)
    }

    let pageRect = page.bounds(for: .mediaBox)
    let scale = min(
      Double(width) / Double(pageRect.width), Double(height) / Double(pageRect.height))
    let targetSize = CGSize(
      width: max(pageRect.width * CGFloat(scale), 1), height: max(pageRect.height * CGFloat(scale), 1))

    let image = page.thumbnail(of: targetSize, for: .mediaBox)
    guard let data = Self.pngData(from: image) else {
      throw PigeonError(code: "render_failed", message: "PNG encoding failed", details: nil)
    }
    return FlutterStandardTypedData(bytes: data)
  }

  func close(handle: String) async throws {
    openDocs.removeValue(forKey: handle)
  }

  /// `NSImage` has no `pngData()` equivalent to `UIImage`; go through its
  /// best (largest) bitmap representation and `NSBitmapImageRep`'s PNG
  /// encoder instead.
  private static func pngData(from image: NSImage) -> Data? {
    guard
      let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData)
    else {
      return nil
    }
    return bitmap.representation(using: .png, properties: [:])
  }
}
