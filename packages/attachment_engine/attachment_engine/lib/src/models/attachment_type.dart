/// The high-level kind of content an [Attachment] represents.
///
/// Detection is performed by `FormatDetector` using a priority order of
/// explicit mime type, magic bytes, extension, url extension, then
/// http content-type.
enum AttachmentType {
  image,
  pdf,
  document,
  office,
  text,
  html,
  scorm,
  h5p,
  video,
  audio,
  archive,
  unknown,
}
