# Bundled third-party libraries

These files are vendored, unmodified, browser-ready builds fetched directly
from their official distribution channels — no CDN calls happen at runtime;
they ship inside the app so the `Offline*Viewer` renderers can render
DOCX/XLSX/PPTX with zero network access.

| File | Project | Version source | License |
|---|---|---|---|
| `docx-preview.min.js` | [docxjs](https://github.com/VolodymyrBaydalka/docxjs) | `https://unpkg.com/docx-preview/dist/docx-preview.min.js` | Apache-2.0 |
| `jszip.min.js` | [JSZip](https://github.com/Stuk/jszip) | `https://unpkg.com/jszip@3/dist/jszip.min.js` | MIT (dual MIT/GPLv3, MIT terms used here) |
| `xlsx.full.min.js` | [SheetJS](https://github.com/SheetJS/sheetjs) | `https://unpkg.com/xlsx/dist/xlsx.full.min.js` | Apache-2.0 |
| `pptxjs.min.js`, `pptxjs.css` | [PPTXjs](https://github.com/meshesha/PPTXjs) | `raw.githubusercontent.com/meshesha/PPTXjs/master/js\|css/...` | MIT |
| `jquery-1.11.3.min.js` | [jQuery](https://jquery.com) | same PPTXjs repo (`js/jquery-1.11.3.min.js`) | MIT — PPTXjs' declared dependency |
| `filereader.js` | [FileReader.js](https://github.com/dwightjack/filereader.js) | same PPTXjs repo (`js/filereader.js`) | MIT — PPTXjs' declared dependency |
| `d3.min.js`, `nv.d3.min.js`, `nv.d3.min.css` | [D3](https://d3js.org)/[NVD3](http://nvd3.org) | same PPTXjs repo (`js/`, `css/`) | BSD-3-Clause / Apache-2.0 — PPTXjs' declared chart-rendering dependencies |

`docx_viewer.html`, `xlsx_viewer.html` and `pptx_viewer.html` are this
package's own code (same license as the rest of `attachment_engine`) —
they only load the files above locally and call into
`docx-preview`'s/SheetJS's/PPTXjs' public APIs. `pptx_viewer.html` hands
the document to PPTXjs as a local `blob:` URL (created in-page from the
bytes Dart provides) rather than raw bytes, since PPTXjs only accepts a
URL to fetch from — `blob:` URLs are resolved by the WebView itself with
no network request.

**Not yet covered by an offline renderer** (uses the Office
Online/conversion/external-open fallback chain in `office_renderer.dart`
instead): legacy `.doc`/`.ppt` (binary OLE format, no browser-ready
renderer was found for either) and OpenDocument formats
(`.odt`/`.odp`/`.ods`, different XML schema, unsupported by the libraries
above). Revisit if a suitable single-file/UMD library appears.

To refresh a vendored file to a newer upstream release, re-download from
the same URL and diff before replacing — these are not managed by pub or
npm, so updates are manual.
