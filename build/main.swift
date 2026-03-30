import AppKit
import WebKit

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var pendingFileURL: URL?
    var cliExportPDFPath: String? = nil
    var pageLoaded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for --export-pdf CLI flag
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--export-pdf"), idx + 1 < args.count {
            cliExportPDFPath = args[idx + 1]
        }

        setupMenuBar()
        setupWindow()

        // Handle file opened via double-click / Open With
        if let url = pendingFileURL {
            pendingFileURL = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.loadMarkdownFile(url: url)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        // Handle CLI-driven file open + PDF export
        if let exportPath = cliExportPDFPath {
            let args = CommandLine.arguments
            // Find the .md file arg (first arg that's not a flag or flag value)
            var mdPath: String? = nil
            if let url = pendingFileURL {
                mdPath = url.path
            } else {
                var i = 1
                while i < args.count {
                    if args[i] == "--export-pdf" { i += 2; continue }
                    if !args[i].hasPrefix("-") {
                        mdPath = args[i]
                        break
                    }
                    i += 1
                }
            }

            if let mdPath = mdPath {
                let url = URL(fileURLWithPath: mdPath)
                self.loadMarkdownFile(url: url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.exportPDFToFile(path: exportPath)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        NSApp.terminate(nil)
                    }
                }
            } else {
                // Export the demo content
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.exportPDFToFile(path: exportPath)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        NSApp.terminate(nil)
                    }
                }
            }
            cliExportPDFPath = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if webView != nil {
            loadMarkdownFile(url: url)
        } else {
            pendingFileURL = url
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first {
            let url = URL(fileURLWithPath: first)
            if webView != nil {
                loadMarkdownFile(url: url)
            } else {
                pendingFileURL = url
            }
        }
    }

    // MARK: - Window Setup

    func setupWindow() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowWidth: CGFloat = min(1200, screenFrame.width * 0.75)
        let windowHeight: CGFloat = min(850, screenFrame.height * 0.85)
        let windowX = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let windowY = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2

        let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MarkView"
        window.minSize = NSSize(width: 600, height: 400)
        window.isReleasedWhenClosed = false

        // WKWebView with message handler
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(ScriptMessageHandler.shared, name: "markview")
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        ScriptMessageHandler.shared.appDelegate = self

        // We use a transparent overlay to catch drag events
        let dragOverlay = DragOverlayView(frame: window.contentView!.bounds, appDelegate: self)
        dragOverlay.autoresizingMask = [.width, .height]

        window.contentView!.addSubview(webView)
        window.contentView!.addSubview(dragOverlay)

        // Load bundled index.html
        if let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About MarkView", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit MarkView", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Open Folder...", action: #selector(openFolder(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        let exportPdfItem = NSMenuItem(title: "Export as PDF...", action: #selector(exportPDF(_:)), keyEquivalent: "e")
        exportPdfItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(exportPdfItem)
        fileMenu.addItem(withTitle: "Print...", action: #selector(printDocument(_:)), keyEquivalent: "p")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Find...", action: #selector(toggleSearch(_:)), keyEquivalent: "f")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = NSMenu(title: "View")
        let viewMenu = viewMenuItem.submenu!

        // Theme submenu
        let themeMenuItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeSubmenu = NSMenu(title: "Theme")
        let themes = ["Light", "Dark", "Sepia", "Nord", "Dracula", "Solarized"]
        for theme in themes {
            let item = NSMenuItem(title: theme, action: #selector(setTheme(_:)), keyEquivalent: "")
            item.representedObject = theme.lowercased()
            themeSubmenu.addItem(item)
        }
        themeMenuItem.submenu = themeSubmenu
        viewMenu.addItem(themeMenuItem)
        viewMenu.addItem(NSMenuItem.separator())

        viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(toggleSidebar(_:)), keyEquivalent: "\\")
        viewMenu.addItem(withTitle: "Toggle Source", action: #selector(toggleSource(_:)), keyEquivalent: "/")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Focus Mode", action: #selector(toggleFocusMode(_:)), keyEquivalent: "")
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Menu Actions

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!,
            .init(filenameExtension: "mdown")!,
            .init(filenameExtension: "mkd")!,
            .init(filenameExtension: "txt")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                self.loadMarkdownFile(url: url)
            }
        }
    }

    @objc func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let dirURL = panel.url {
                self.openFolderAt(dirURL)
            }
        }
    }

    func openFolderAt(_ dirURL: URL) {
        let fm = FileManager.default
        let exts: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt"]

        guard let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]),
              let files = enumerator.allObjects as? [URL] else { return }

        let mdFiles = files
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !mdFiles.isEmpty else { return }

        // Store file URL mapping for later lookup
        state_folderFiles = Dictionary(uniqueKeysWithValues: mdFiles.map { ($0.lastPathComponent, $0) })

        // Build filenames JSON array
        let names = mdFiles.map { $0.lastPathComponent }
        let namesJSON = names.map { "\"\(escapeJSString($0))\"" }.joined(separator: ",")

        // Read first file content
        let firstFile = mdFiles[0]
        loadMarkdownFile(url: firstFile)

        // Send file list to JS for sidebar display
        let js = "receiveFilesFromApp([\(namesJSON)])"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc func setTheme(_ sender: NSMenuItem) {
        guard let themeName = sender.representedObject as? String else { return }
        webView.evaluateJavaScript("setTheme('\(themeName)')", completionHandler: nil)
    }

    @objc func toggleSidebar(_ sender: Any?) {
        webView.evaluateJavaScript("document.getElementById('btnSidebar').click()", completionHandler: nil)
    }

    @objc func toggleSource(_ sender: Any?) {
        webView.evaluateJavaScript("toggleSourceMode()", completionHandler: nil)
    }

    @objc func toggleFocusMode(_ sender: Any?) {
        webView.evaluateJavaScript("document.getElementById('btnFocus').click()", completionHandler: nil)
    }

    @objc func toggleSearch(_ sender: Any?) {
        webView.evaluateJavaScript("document.getElementById('btnSearch').click()", completionHandler: nil)
    }

    // A4 dimensions in points (72 dpi)
    static let a4Width: CGFloat = 595.28
    static let a4Height: CGFloat = 841.89
    static let a4Margin: CGFloat = 40.0
    static let a4ContentWidth: CGFloat = a4Width - a4Margin * 2

    @objc func exportPDF(_ sender: Any?) {
        let panel = NSSavePanel()
        let defaultName = (state_currentFile ?? "export").replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
        panel.nameFieldStringValue = defaultName + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                self.generatePaginatedPDF { data in
                    if let data = data {
                        do {
                            try data.write(to: url)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } catch {
                            let alert = NSAlert()
                            alert.messageText = "Export failed"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.beginSheetModal(for: self.window, completionHandler: nil)
                        }
                    }
                }
            }
        }
    }

    /// Generate a paginated A4 PDF from the current web content
    func generatePaginatedPDF(completion: @escaping (Data?) -> Void) {
        // Step 1: Enter PDF export mode and resize web view to A4 content width
        let enterJS = "document.body.classList.add('pdf-export-mode')"
        webView.evaluateJavaScript(enterJS) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Step 2: Get full single-page PDF (no rect = full content height)
                let pdfConfig = WKPDFConfiguration()
                self.webView.createPDF(configuration: pdfConfig) { pdfResult in
                    // Restore UI
                    let exitJS = "document.body.classList.remove('pdf-export-mode')"
                    self.webView.evaluateJavaScript(exitJS, completionHandler: nil)

                    switch pdfResult {
                    case .success(let singlePageData):
                        // Step 3: Split the single long page into A4-sized pages
                        let paginated = self.paginatePDF(data: singlePageData)
                        completion(paginated)
                    case .failure(let error):
                        NSLog("PDF generation error: \(error.localizedDescription)")
                        let alert = NSAlert()
                        alert.messageText = "PDF generation failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.beginSheetModal(for: self.window, completionHandler: nil)
                        completion(nil)
                    }
                }
            }
        }
    }

    /// Slice a single tall PDF page into A4-sized pages
    func paginatePDF(data: Data) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let sourcePDF = CGPDFDocument(provider),
              let sourcePage = sourcePDF.page(at: 1) else { return nil }

        let sourceRect = sourcePage.getBoxRect(.mediaBox)
        let sourceWidth = sourceRect.width
        let sourceHeight = sourceRect.height
        let pageHeight = AppDelegate.a4Height
        let pageWidth = AppDelegate.a4Width

        // Scale factor: fit source width into A4 width
        let scale = pageWidth / sourceWidth
        let scaledHeight = sourceHeight * scale

        // How many pages do we need?
        let contentPageHeight = pageHeight  // full A4 height per page
        let pageCount = max(1, Int(ceil(scaledHeight / contentPageHeight)))

        if pageCount == 1 {
            // Content fits on one page, return as-is but at A4 size
            let pdfData = NSMutableData()
            guard let consumer = CGDataConsumer(data: pdfData),
                  let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }

            var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: min(scaledHeight, pageHeight))
            context.beginPage(mediaBox: &mediaBox)
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(sourcePage)
            context.endPage()
            context.closePDF()
            return pdfData as Data
        }

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }

        for i in 0..<pageCount {
            var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            context.beginPage(mediaBox: &mediaBox)

            // Save state, clip to page bounds
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

            // The source PDF has origin at bottom-left.
            // We need to show slice i: from top of content, page i starts at y = i * contentPageHeight
            // In PDF coordinates (bottom-left origin), we translate so the correct slice is visible.
            let yOffset = scaledHeight - CGFloat(i + 1) * contentPageHeight
            context.translateBy(x: 0, y: -yOffset)
            context.scaleBy(x: scale, y: scale)
            context.drawPDFPage(sourcePage)

            context.restoreGState()
            context.endPage()
        }

        context.closePDF()
        return pdfData as Data
    }

    @objc func printDocument(_ sender: Any?) {
        webView.evaluateJavaScript("window.print()", completionHandler: nil)
    }

    /// Export PDF directly to a file path (for testing / CLI usage)
    func exportPDFToFile(path: String) {
        let url = URL(fileURLWithPath: path)
        generatePaginatedPDF { data in
            if let data = data {
                do {
                    try data.write(to: url)
                    NSLog("PDF exported to: \(path)")
                } catch {
                    NSLog("PDF write error: \(error.localizedDescription)")
                }
            }
        }
    }

    // Track current file name for export default filename
    var state_currentFile: String? = nil
    // Track files in the currently opened folder (filename -> full URL)
    var state_folderFiles: [String: URL] = [:]

    // MARK: - Load Markdown File

    func loadMarkdownFile(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let filename = url.lastPathComponent
            let filePath = url.path // Full path for reading progress key
            state_currentFile = filename
            window.title = "\(filename) - MarkView"

            // Escape for JavaScript string
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")

            let js = "loadMarkdownFromApp(\"\(escapeJSString(filename))\", \"\(escaped)\", \"\(escapeJSString(filePath))\")"
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    NSLog("JS Error: \(error.localizedDescription)")
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cannot open file"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    func escapeJSString(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

// MARK: - Script Message Handler

class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let shared = ScriptMessageHandler()
    weak var appDelegate: AppDelegate?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "updateTitle":
            if let title = body["title"] as? String {
                appDelegate?.window.title = title
            }
        case "openFile":
            appDelegate?.openDocument(nil)
        case "openFolder":
            appDelegate?.openFolder(nil)
        case "openFileByName":
            if let name = body["filename"] as? String,
               let url = appDelegate?.state_folderFiles[name] {
                appDelegate?.loadMarkdownFile(url: url)
            }
        case "exportPDF":
            appDelegate?.exportPDF(nil)
        default:
            break
        }
    }
}

// MARK: - Drag Overlay View (handles file drops)

class DragOverlayView: NSView {
    weak var appDelegate: AppDelegate?

    init(frame: NSRect, appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // Pass all mouse/keyboard events through to the web view
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    // But still handle drag operations
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasMdFile(sender) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                let ext = url.pathExtension.lowercased()
                if ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt"].contains(ext) {
                    appDelegate?.loadMarkdownFile(url: url)
                    return true
                }
            }
        }
        return false
    }

    private func hasMdFile(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                let ext = url.pathExtension.lowercased()
                if ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt"].contains(ext) {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
