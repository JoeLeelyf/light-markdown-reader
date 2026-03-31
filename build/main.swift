import AppKit
import WebKit

// MARK: - Window Controller (per-window state)

class MarkViewWindowController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var messageHandler: ScriptMessageHandler!
    var pageLoaded = false
    var state_currentFile: String?
    var state_folderFiles: [String: URL] = [:]
    var pendingLoad: (() -> Void)?
    let windowId: String

    init(windowId: String? = nil) {
        self.windowId = windowId ?? UUID().uuidString
        super.init()
    }

    func setupWindow(at point: NSPoint? = nil) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowWidth: CGFloat = min(1200, screenFrame.width * 0.75)
        let windowHeight: CGFloat = min(850, screenFrame.height * 0.85)

        let windowX: CGFloat
        let windowY: CGFloat
        if let pt = point {
            // Position near the drop point (convert screen coords)
            windowX = pt.x - windowWidth / 2
            windowY = pt.y - windowHeight / 2
        } else {
            windowX = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            windowY = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2
        }

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
        window.delegate = self

        // WKWebView with per-window message handler
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        messageHandler = ScriptMessageHandler(windowController: self)
        contentController.add(messageHandler, name: "markview")
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: "localfile")

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self

        let dragOverlay = DragOverlayView(frame: window.contentView!.bounds, windowController: self)
        dragOverlay.autoresizingMask = [.width, .height]

        window.contentView!.addSubview(webView)
        window.contentView!.addSubview(dragOverlay)

        // Load bundled index.html
        if let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        NSLog("Page loaded for window \(windowId)")
        if let load = pendingLoad {
            pendingLoad = nil
            load()
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        let appDel = NSApp.delegate as? AppDelegate
        appDel?.removeWindowController(self)
    }

    // MARK: - Menu Actions (routed from AppDelegate)

    func openDocument() {
        NSLog("openDocument called, window: \(window != nil ? "exists" : "nil")")
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "md")!,
            .init(filenameExtension: "markdown")!,
            .init(filenameExtension: "mdown")!,
            .init(filenameExtension: "mkd")!,
            .init(filenameExtension: "txt")!,
            .init(filenameExtension: "json")!,
            .init(filenameExtension: "jsonl")!,
            .init(filenameExtension: "ndjson")!,
            .init(filenameExtension: "xml")!,
            .init(filenameExtension: "toml")!,
            .init(filenameExtension: "yaml")!,
            .init(filenameExtension: "yml")!,
            .init(filenameExtension: "parquet")!,
            .init(filenameExtension: "csv")!,
            .init(filenameExtension: "tsv")!,
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

    func openFolder() {
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
        let exts: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt", "json", "jsonl", "ndjson", "xml", "toml", "yaml", "yml", "parquet", "csv", "tsv"]

        guard let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]),
              let files = enumerator.allObjects as? [URL] else { return }

        let mdFiles = files
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard !mdFiles.isEmpty else { return }

        state_folderFiles = Dictionary(uniqueKeysWithValues: mdFiles.map { ($0.lastPathComponent, $0) })

        let names = mdFiles.map { $0.lastPathComponent }
        let namesJSON = names.map { "\"\(escapeJSString($0))\"" }.joined(separator: ",")

        let firstFile = mdFiles[0]
        loadMarkdownFile(url: firstFile)

        let js = "receiveFilesFromApp([\(namesJSON)])"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func setTheme(_ themeName: String) {
        webView.evaluateJavaScript("setTheme('\(themeName)')", completionHandler: nil)
    }

    func toggleSidebar() {
        webView.evaluateJavaScript("document.getElementById('btnSidebar').click()", completionHandler: nil)
    }

    func toggleSource() {
        webView.evaluateJavaScript("toggleSourceMode()", completionHandler: nil)
    }

    func toggleFocusMode() {
        webView.evaluateJavaScript("document.getElementById('btnFocus').click()", completionHandler: nil)
    }

    func toggleSearch() {
        webView.evaluateJavaScript("document.getElementById('btnSearch').click()", completionHandler: nil)
    }

    func closeActiveTab() {
        webView.evaluateJavaScript("closeTab(state.activeTabId)", completionHandler: nil)
    }

    func toggleSplitView() {
        webView.evaluateJavaScript("if(typeof toggleSplitView==='function')toggleSplitView('vertical')", completionHandler: nil)
    }

    func closeSplitView() {
        webView.evaluateJavaScript("if(typeof closeSplitView==='function')closeSplitView()", completionHandler: nil)
    }

    // MARK: - PDF

    // A4 dimensions in points (72 dpi)
    static let a4Width: CGFloat = 595.28
    static let a4Height: CGFloat = 841.89

    func exportPDF() {
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

    func generatePaginatedPDF(completion: @escaping (Data?) -> Void) {
        let enterJS = "document.body.classList.add('pdf-export-mode')"
        webView.evaluateJavaScript(enterJS) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let pdfConfig = WKPDFConfiguration()
                self.webView.createPDF(configuration: pdfConfig) { pdfResult in
                    let exitJS = "document.body.classList.remove('pdf-export-mode')"
                    self.webView.evaluateJavaScript(exitJS, completionHandler: nil)

                    switch pdfResult {
                    case .success(let singlePageData):
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

    func paginatePDF(data: Data) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData),
              let sourcePDF = CGPDFDocument(provider),
              let sourcePage = sourcePDF.page(at: 1) else { return nil }

        let sourceRect = sourcePage.getBoxRect(.mediaBox)
        let sourceWidth = sourceRect.width
        let sourceHeight = sourceRect.height
        let pageHeight = MarkViewWindowController.a4Height
        let pageWidth = MarkViewWindowController.a4Width

        let scale = pageWidth / sourceWidth
        let scaledHeight = sourceHeight * scale

        let contentPageHeight = pageHeight
        let pageCount = max(1, Int(ceil(scaledHeight / contentPageHeight)))

        if pageCount == 1 {
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
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

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

    func printDocument() {
        webView.evaluateJavaScript("window.print()", completionHandler: nil)
    }

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

    // MARK: - Load Markdown File

    static let binaryExtensions: Set<String> = ["parquet"]

    func loadMarkdownFile(url: URL) {
        NSLog("loadMarkdownFile: \(url.path), pageLoaded=\(pageLoaded)")
        let filename = url.lastPathComponent
        let filePath = url.path
        let ext = url.pathExtension.lowercased()
        state_currentFile = filename
        window.title = "\(filename) - MarkView"

        if MarkViewWindowController.binaryExtensions.contains(ext) {
            // Binary file: read as Data and send base64 to JS
            do {
                let data = try Data(contentsOf: url)
                let base64 = data.base64EncodedString()
                let js = "loadBinaryFromApp(\"\(escapeJSString(filename))\", \"\(base64)\", \"\(escapeJSString(filePath))\")"

                if pageLoaded {
                    webView.evaluateJavaScript(js) { _, error in
                        if let error = error {
                            NSLog("JS Error: \(error.localizedDescription)")
                        }
                    }
                } else {
                    pendingLoad = { [weak self] in
                        self?.webView.evaluateJavaScript(js) { _, error in
                            if let error = error {
                                NSLog("JS Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Cannot open file"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window, completionHandler: nil)
            }
        } else {
            // Text file: read as UTF-8
            do {
                let content = try String(contentsOf: url, encoding: .utf8)

                let escaped = content
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\t", with: "\\t")

                let js = "loadMarkdownFromApp(\"\(escapeJSString(filename))\", \"\(escaped)\", \"\(escapeJSString(filePath))\")"

                if pageLoaded {
                    webView.evaluateJavaScript(js) { _, error in
                        if let error = error {
                            NSLog("JS Error: \(error.localizedDescription)")
                        }
                    }
                } else {
                    pendingLoad = { [weak self] in
                        self?.webView.evaluateJavaScript(js) { _, error in
                            if let error = error {
                                NSLog("JS Error: \(error.localizedDescription)")
                            }
                        }
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
    }

    func escapeJSString(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Script Message Handler (per-window)

class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var windowController: MarkViewWindowController?

    init(windowController: MarkViewWindowController) {
        self.windowController = windowController
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        NSLog("ScriptMessageHandler received action: \(action), windowController is \(windowController == nil ? "nil" : "alive")")

        switch action {
        case "updateTitle":
            if let title = body["title"] as? String {
                windowController?.window.title = title
            }
        case "openFile":
            windowController?.openDocument()
        case "openFolder":
            windowController?.openFolder()
        case "openFileByName":
            if let name = body["filename"] as? String,
               let url = windowController?.state_folderFiles[name] {
                windowController?.loadMarkdownFile(url: url)
            }
        case "exportPDF":
            windowController?.exportPDF()
        case "detachTab":
            // Tab dragged out — create new window with this tab's content
            if let filename = body["filename"] as? String,
               let filePath = body["filePath"] as? String,
               let rawContent = body["rawContent"] as? String,
               let screenX = body["screenX"] as? Double,
               let screenY = body["screenY"] as? Double {
                let appDel = NSApp.delegate as? AppDelegate
                // Convert screen coordinates (JS screenY has 0 at top, macOS has 0 at bottom)
                // Use the screen containing the point, not just the main screen
                let jsPoint = NSPoint(x: CGFloat(screenX), y: CGFloat(screenY))
                let targetScreen = NSScreen.screens.first { screen in
                    let frame = screen.frame
                    return jsPoint.x >= frame.minX && jsPoint.x <= frame.maxX
                } ?? NSScreen.main
                let screenHeight = targetScreen?.frame.height ?? 900
                let screenOriginY = targetScreen?.frame.origin.y ?? 0
                let macY = screenOriginY + screenHeight - CGFloat(screenY)
                let pt = NSPoint(x: CGFloat(screenX), y: macY)
                appDel?.createNewWindow(withFilename: filename, filePath: filePath, rawContent: rawContent, at: pt)
            }
        case "themeChanged":
            // Broadcast theme to all other windows
            if let theme = body["theme"] as? String {
                let appDel = NSApp.delegate as? AppDelegate
                appDel?.broadcastTheme(theme, except: windowController)
            }
        default:
            break
        }
    }
}

// MARK: - Local File Scheme Handler (loads local images for WKWebView)

class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // Convert localfile:///path to /path
        let filePath = components.path
        let fileURL = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = LocalFileSchemeHandler.mimeType(for: fileURL.pathExtension)
            let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "ico": return "image/x-icon"
        case "tif", "tiff": return "image/tiff"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Drag Overlay View (handles file drops)

class DragOverlayView: NSView {
    weak var windowController: MarkViewWindowController?

    init(frame: NSRect, windowController: MarkViewWindowController) {
        self.windowController = windowController
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

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
                if ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt", "json", "jsonl", "ndjson", "xml", "toml", "yaml", "yml", "parquet", "csv", "tsv"].contains(ext) {
                    windowController?.loadMarkdownFile(url: url)
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
                if ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt", "json", "jsonl", "ndjson", "xml", "toml", "yaml", "yml", "parquet", "csv", "tsv"].contains(ext) {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowControllers: [MarkViewWindowController] = []
    var pendingFileURL: URL?
    var cliExportPDFPath: String? = nil

    var activeWindowController: MarkViewWindowController? {
        if let keyWindow = NSApp.keyWindow {
            return windowControllers.first { $0.window === keyWindow }
        }
        return windowControllers.first
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for --export-pdf CLI flag
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--export-pdf"), idx + 1 < args.count {
            cliExportPDFPath = args[idx + 1]
        }

        setupMenuBar()

        let wc = createWindowController()
        wc.setupWindow()

        // Handle file opened via double-click / Open With (before launch)
        if let url = pendingFileURL {
            pendingFileURL = nil
            wc.pendingLoad = { wc.loadMarkdownFile(url: url) }
        }

        // Handle CLI mode
        if let exportPath = cliExportPDFPath {
            let cliArgs = CommandLine.arguments
            var mdPath: String? = nil
            var i = 1
            while i < cliArgs.count {
                if cliArgs[i] == "--export-pdf" { i += 2; continue }
                if !cliArgs[i].hasPrefix("-") {
                    mdPath = cliArgs[i]
                    break
                }
                i += 1
            }

            let capturedMdPath = mdPath
            let capturedExportPath = exportPath

            wc.pendingLoad = {
                if let path = capturedMdPath {
                    let url = URL(fileURLWithPath: path)
                    wc.loadMarkdownFile(url: url)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    wc.exportPDFToFile(path: capturedExportPath)
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
        NSLog("application openFile: \(filename)")
        let url = URL(fileURLWithPath: filename)
        if let wc = activeWindowController, wc.pageLoaded {
            wc.loadMarkdownFile(url: url)
        } else if let wc = windowControllers.first {
            wc.pendingLoad = { wc.loadMarkdownFile(url: url) }
        } else {
            pendingFileURL = url
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        NSLog("application openFiles: \(filenames)")
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            NSLog("  openFiles: activeWC=\(activeWindowController != nil), pageLoaded=\(activeWindowController?.pageLoaded ?? false), wc.count=\(windowControllers.count)")
            if let wc = activeWindowController, wc.pageLoaded {
                wc.loadMarkdownFile(url: url)
            } else if let wc = windowControllers.first {
                NSLog("  openFiles: setting pendingLoad for \(url.path)")
                let capturedURL = url
                wc.pendingLoad = { wc.loadMarkdownFile(url: capturedURL) }
            } else {
                NSLog("  openFiles: no window controllers, setting pendingFileURL")
                pendingFileURL = url
            }
        }
    }

    // MARK: - Window Management

    @discardableResult
    func createWindowController() -> MarkViewWindowController {
        let wc = MarkViewWindowController()
        windowControllers.append(wc)
        return wc
    }

    func removeWindowController(_ wc: MarkViewWindowController) {
        windowControllers.removeAll { $0 === wc }
    }

    func createNewWindow(withFilename filename: String, filePath: String, rawContent: String, at point: NSPoint?) {
        let wc = createWindowController()
        wc.setupWindow(at: point)

        let escapedContent = rawContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        let escapedFilename = wc.escapeJSString(filename)
        let escapedFilePath = wc.escapeJSString(filePath)

        wc.state_currentFile = filename
        wc.window.title = "\(filename) - MarkView"

        wc.pendingLoad = {
            let js = "loadMarkdownFromApp(\"\(escapedFilename)\", \"\(escapedContent)\", \"\(escapedFilePath)\")"
            wc.webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    NSLog("JS Error loading detached tab: \(error.localizedDescription)")
                }
            }
        }
    }

    func broadcastTheme(_ theme: String, except sender: MarkViewWindowController?) {
        for wc in windowControllers {
            if wc !== sender {
                wc.setTheme(theme)
            }
        }
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
        fileMenu.addItem(withTitle: "Open...", action: #selector(menuOpenDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Open Folder...", action: #selector(menuOpenFolder(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        let exportPdfItem = NSMenuItem(title: "Export as PDF...", action: #selector(menuExportPDF(_:)), keyEquivalent: "e")
        exportPdfItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(exportPdfItem)
        fileMenu.addItem(withTitle: "Print...", action: #selector(menuPrintDocument(_:)), keyEquivalent: "p")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(menuCloseTab(_:)), keyEquivalent: "w")
        let closeWindowItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindowItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(closeWindowItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Find...", action: #selector(menuToggleSearch(_:)), keyEquivalent: "f")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = NSMenu(title: "View")
        let viewMenu = viewMenuItem.submenu!

        let themeMenuItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeSubmenu = NSMenu(title: "Theme")
        let themes = ["Light", "Dark", "Sepia", "Nord", "Dracula", "Solarized"]
        for theme in themes {
            let item = NSMenuItem(title: theme, action: #selector(menuSetTheme(_:)), keyEquivalent: "")
            item.representedObject = theme.lowercased()
            themeSubmenu.addItem(item)
        }
        themeMenuItem.submenu = themeSubmenu
        viewMenu.addItem(themeMenuItem)
        viewMenu.addItem(NSMenuItem.separator())

        viewMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(menuToggleSidebar(_:)), keyEquivalent: "\\")
        viewMenu.addItem(withTitle: "Toggle Source", action: #selector(menuToggleSource(_:)), keyEquivalent: "/")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Split Right", action: #selector(menuSplitView(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Close Split", action: #selector(menuCloseSplit(_:)), keyEquivalent: "")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Focus Mode", action: #selector(menuToggleFocusMode(_:)), keyEquivalent: "")
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "New Window", action: #selector(menuNewWindow(_:)), keyEquivalent: "n")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Menu Action Routing

    @objc func menuOpenDocument(_ sender: Any?) {
        NSLog("menuOpenDocument called, activeWindowController: \(activeWindowController != nil ? "exists" : "nil")")
        activeWindowController?.openDocument()
    }

    @objc func menuOpenFolder(_ sender: Any?) {
        activeWindowController?.openFolder()
    }

    @objc func menuExportPDF(_ sender: Any?) {
        activeWindowController?.exportPDF()
    }

    @objc func menuPrintDocument(_ sender: Any?) {
        activeWindowController?.printDocument()
    }

    @objc func menuCloseTab(_ sender: Any?) {
        activeWindowController?.closeActiveTab()
    }

    @objc func menuSetTheme(_ sender: NSMenuItem) {
        guard let themeName = sender.representedObject as? String else { return }
        activeWindowController?.setTheme(themeName)
    }

    @objc func menuToggleSidebar(_ sender: Any?) {
        activeWindowController?.toggleSidebar()
    }

    @objc func menuToggleSource(_ sender: Any?) {
        activeWindowController?.toggleSource()
    }

    @objc func menuToggleFocusMode(_ sender: Any?) {
        activeWindowController?.toggleFocusMode()
    }

    @objc func menuToggleSearch(_ sender: Any?) {
        activeWindowController?.toggleSearch()
    }

    @objc func menuSplitView(_ sender: Any?) {
        activeWindowController?.toggleSplitView()
    }

    @objc func menuCloseSplit(_ sender: Any?) {
        activeWindowController?.closeSplitView()
    }

    @objc func menuNewWindow(_ sender: Any?) {
        let wc = createWindowController()
        wc.setupWindow()
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
