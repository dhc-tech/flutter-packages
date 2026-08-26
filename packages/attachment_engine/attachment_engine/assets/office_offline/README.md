# Bundled third-party libraries

These files are vendored, unmodified, browser-ready builds fetched directly
from their official distribution channels — no CDN calls happen at runtime;
they ship inside the app so [OfflineDocxViewer](../../lib/src/renderers/offline_docx_viewer.dart)
can render DOCX files with zero network access.

| File | Project | Version source | License |
|---|---|---|---|
| `docx-preview.min.js` | [docxjs](https://github.com/VolodymyrBaydalka/docxjs) | `https://unpkg.com/docx-preview/dist/docx-preview.min.js` | Apache-2.0 |
| `jszip.min.js` | [JSZip](https://github.com/Stuk/jszip) | `https://unpkg.com/jszip@3/dist/jszip.min.js` | MIT (dual MIT/GPLv3, MIT terms used here) |
| `xlsx.full.min.js` | [SheetJS](https://github.com/SheetJS/sheetjs) | `https://unpkg.com/xlsx/dist/xlsx.full.min.js` | Apache-2.0 |

`docx_viewer.html` and `xlsx_viewer.html` are this package's own code (same
license as the rest of `attachment_engine`) — they only load the files
above locally and call into `docx-preview`'s / SheetJS's public APIs.

**Not yet covered by an offline renderer** (uses the Office
Online/conversion/external-open fallback chain in `office_renderer.dart`
instead): `.pptx`/`.ppt` (no sufficiently lightweight, dependency-free,
UMD-distributable JS renderer was found — the closest options are ES-module
libraries with non-trivial bundled dependency graphs), legacy `.doc`
(binary OLE format, no browser-ready renderer), and OpenDocument formats
(`.odt`/`.odp`/`.ods`, different XML schema, unsupported by the libraries
above). Revisit if a suitable single-file/UMD library appears.

To refresh either vendored file to a newer upstream release, re-download
from the same URL and diff before replacing — these are not managed by pub
or npm, so updates are manual.
