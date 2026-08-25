/// Pure-Dart value types shared by [AttachmentEnginePlatform] and its
/// implementations. None of these types reference `dart:ffi`,
/// `MethodChannel`, or any other platform-specific transport — that keeps
/// the contract satisfiable by a future web implementation via
/// `dart:js_interop`.
library;

/// Result of opening a PDF document natively.
class PdfOpenResult {
  const PdfOpenResult({required this.handle, required this.pageCount});

  /// Opaque handle identifying the open document on the native side.
  final String handle;

  /// Number of pages in the document.
  final int pageCount;
}

/// Result of an "open externally" request (hand the file to another app).
class NativeOpenResult {
  const NativeOpenResult({required this.success, this.message});

  final bool success;
  final String? message;
}
