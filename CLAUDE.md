# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MarkView is a lightweight macOS Markdown reader (Typora-style). It's a native Swift app (AppKit + WKWebView) that wraps a single self-contained HTML file. No Electron, no npm, no package manager — just Swift compilation and a single HTML with embedded CSS/JS.

## Build & Run

```bash
cd build && bash build.sh
open ~/Downloads/MarkView.app
```

Requirements: macOS 13.0+, Xcode Command Line Tools (`swiftc`), Python 3 (icon generation).

The build script outputs `MarkView.app` to `~/Downloads/`. There is no incremental build — it regenerates icons, recompiles Swift, and reassembles the .app bundle every time.

CLI PDF export: `~/Downloads/MarkView.app/Contents/MacOS/MarkView file.md --export-pdf output.pdf`

There are no tests, no linter, and no CI configured.

## Architecture

### Two-layer design

1. **`index.html`** — The entire frontend in one file (~1700 lines). Contains all HTML structure, CSS (6 themes via CSS custom properties), and vanilla JS (~700 lines). External libraries loaded via CDN: marked.js (v12.0.1), highlight.js (v11.9.0), KaTeX (v0.16.9).

2. **`build/main.swift`** — Native macOS shell (~600 lines). Handles window management, file dialogs, menu bar, drag & drop, and PDF export with A4 pagination. Renders `index.html` inside a WKWebView.

### JS ↔ Swift bridge

- **JS → Swift**: `window.webkit.messageHandlers.markview.postMessage({ action: '...' })` with actions: `openFile`, `openFolder`, `openFileByName`, `exportPDF`, `updateTitle`
- **Swift → JS**: `webView.evaluateJavaScript()` calling global functions: `loadMarkdownFromApp(filename, content)`, `receiveFilesFromApp(files)`, `setTheme(name)`

### Key patterns

- **Math placeholder strategy**: LaTeX expressions (`$...$` / `$$...$$`) are replaced with UUID placeholders before markdown parsing, then restored and rendered with KaTeX after.
- **Reading progress**: Scroll position saved per file path in localStorage (`markview-reading-progress`), max 100 entries with LRU pruning.
- **PDF generation** (Swift): Renders full-height single page, then slices it into A4 pages using CGContext clipping and coordinate transforms.
- **State**: JS uses a plain `state` object with direct DOM manipulation (no framework reactivity). Swift tracks `state_currentFile`, `state_folderFiles`, and pending file URLs.

### File associations

Registered as viewer for `.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`, `.mdx` via `Info.plist` CFBundleDocumentTypes.
