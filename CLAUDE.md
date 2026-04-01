# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FView is a lightweight native macOS file viewer for Markdown and ML data files. It's a native Swift app (AppKit + WKWebView) that wraps a single self-contained HTML file. No Electron, no npm, no package manager — just Swift compilation and a single HTML with embedded CSS/JS.

## Build & Run

```bash
cd build && bash build.sh
open ~/Downloads/FView.app
```

Requirements: macOS 13.0+, Xcode Command Line Tools (`swiftc`), Python 3 (icon generation).

The build script outputs `FView.app` to `~/Downloads/`. There is no incremental build — it regenerates icons, recompiles Swift, and reassembles the .app bundle every time.

CLI PDF export: `~/Downloads/FView.app/Contents/MacOS/FView file.md --export-pdf output.pdf`

There are no tests, no linter, and no CI configured.

## Architecture

### Two-layer design

1. **`index.html`** — The entire frontend in one file (~3600 lines). Contains all HTML structure, CSS (6 themes via CSS custom properties), and vanilla JS (~2000 lines). External libraries loaded via CDN: marked.js (v12.0.1), highlight.js (v11.9.0), KaTeX (v0.16.9), Papa Parse (v5, CSV/TSV parsing), hyparquet (dynamic import, Parquet parsing).

2. **`build/main.swift`** — Native macOS shell (~880 lines). Handles window management, file dialogs, menu bar, drag & drop, and PDF export with A4 pagination. Renders `index.html` inside a WKWebView. Supports both text (UTF-8) and binary (base64-encoded) file loading paths.

### JS ↔ Swift bridge

- **JS → Swift**: `window.webkit.messageHandlers.fview.postMessage({ action: '...' })` with actions: `openFile`, `openFolder`, `openFileByName`, `exportPDF`, `updateTitle`
- **Swift → JS**: `webView.evaluateJavaScript()` calling global functions: `loadMarkdownFromApp(filename, content)`, `loadBinaryFromApp(filename, base64data, filePath)`, `receiveFilesFromApp(files)`, `setTheme(name)`

### Key patterns

- **Math placeholder strategy**: LaTeX expressions (`$...$` / `$$...$$`) are replaced with UUID placeholders before markdown parsing, then restored and rendered with KaTeX after.
- **Reading progress**: Scroll position saved per file path in localStorage (`fview-reading-progress`), max 100 entries with LRU pruning.
- **PDF generation** (Swift): Renders full-height single page, then slices it into A4 pages using CGContext clipping and coordinate transforms.
- **State**: JS uses a plain `state` object with direct DOM manipulation (no framework reactivity). Tab objects track `format`, `rawContent`, `binaryData` (for Parquet), `cachedHTML`, and `parquetMeta`. Swift tracks `state_currentFile`, `state_folderFiles`, and pending file URLs.
- **Binary file loading**: Parquet files are read as `Data` in Swift, base64-encoded, and sent to JS via `loadBinaryFromApp()`. JS decodes to ArrayBuffer and uses hyparquet (ESM dynamic import) for parsing.
- **Table rendering**: Parquet and CSV/TSV share the same table CSS (`.parquet-table`). Both support pagination (100 rows/batch), base64 image/video inline preview, and structured outlines.

### File associations

Registered as viewer for `.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`, `.mdx`, `.txt`, `.json`, `.jsonl`, `.ndjson`, `.xml`, `.yaml`, `.yml`, `.toml`, `.csv`, `.tsv`, `.parquet` via `Info.plist` CFBundleDocumentTypes.
