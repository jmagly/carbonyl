# PDF Rendering In Carbonyl

Issue: #213

## Current State

Carbonyl's Chromium args leave `enable_pdf` and `enable_printing` at their
platform defaults. In the current local GN configuration, both resolve to
`true`.

That does not mean the terminal runtime includes Chrome's in-browser PDF
viewer. The active `//headless:headless_browser` dependency graph only exposes
PDF build flags/constants and PDFium public headers:

```text
//pdf:buildflags
//pdf:pdf_accessibility_constants
//third_party/pdfium:pdfium_public_headers
//third_party/pdfium:pdfium_public_headers_impl
```

There is no `chrome/browser/resources/pdf`, Chrome PDF extension/viewer, or
other browser PDF viewer target in the headless runtime graph. The printing
path exists for browser-driven print/PDF output, but that is not the same as
rendering an arbitrary `application/pdf` response inside a web page or iframe.

## Why Overleaf Is Affected

Overleaf's normal preview pane serves compiled PDFs through browser PDF viewing
behavior. A full Chrome build can hand that response to the Chrome PDF viewer.
Carbonyl's patched headless shell does not carry that viewer surface, so the
PDF response has no equivalent terminal-renderable document view.

## Recommended Path

Treat PDF viewing as an explicit Carbonyl feature, not a one-line GN flag:

1. Keep `enable_pdf=true` and `enable_printing=true`; they are already enabled
   in the current GN config.
2. Use #182 download support as the immediate escape hatch for `application/pdf`
   responses.
3. For interactive PDF viewing, add a dedicated PDF document path:
   - either integrate a PDFium-backed raster/text extraction flow into
     Carbonyl's renderer, or
   - embed a small browser-side PDF.js-style viewer resource that can render a
     PDF URL into normal DOM/canvas content.
4. Add a local repro fixture before implementation: a static page with an
   iframe or object pointing to a small local PDF, plus a verifier that checks
   the terminal/dump output for visible page content.

Avoid pulling Chrome's full PDF viewer stack into headless blindly. It is
tightly coupled to Chrome resources/extensions and would materially increase the
Chromium patch surface.

## Verification Commands Used

From `chromium/src`:

```sh
buildtools/linux64/gn args out/Default --list=enable_pdf --short
buildtools/linux64/gn args out/Default --list=enable_printing --short
buildtools/linux64/gn desc out/Default //headless:headless_browser deps --all \
  | rg '(^|/)pdf|pdfium|chrome/browser/resources/pdf|chrome_pdf|pdf_viewer|components/pdf'
```
