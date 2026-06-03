import SwiftUI
import Combine

/// Owns workspace state: open tabs, the active document, the file tree,
/// and UI flags. A single shared instance is used so that menu commands
/// (driven by the hardware keyboard) and the view hierarchy stay in sync.
@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published var openDocuments: [EditorDocument] = []
    @Published var activeDocumentID: UUID?
    @Published var workspaceURL: URL?
    @Published var fileTree: [FileNode] = []

    @Published var sidebarVisible: Bool = true
    @Published var theme: EditorTheme = .dark
    @Published var showCommandPalette: Bool = false

    // File-importer triggers, bound to .fileImporter modifiers in ContentView.
    @Published var importFile: Bool = false
    @Published var importFolder: Bool = false
    @Published var errorMessage: String?

    /// Whether we currently hold an active security scope on `workspaceURL`.
    private var workspaceAccessing = false

    /// Scopes of previously opened workspaces kept alive because documents from
    /// them are still open. Released once their last document closes.
    private var retainedWorkspaceScopes: Set<URL> = []

    private let bookmarkKey = "workspaceBookmark"

    var activeDocument: EditorDocument? {
        openDocuments.first { $0.id == activeDocumentID }
    }

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        restoreWorkspace()
    }

    // MARK: - Theme

    func toggleTheme() {
        theme = (theme == .dark) ? .light : .dark
    }

    // MARK: - Opening documents

    func open(_ url: URL) {
        // Already open? Just activate it.
        if let existing = openDocuments.first(where: { $0.url == url }) {
            activeDocumentID = existing.id
            return
        }
        // Start the security scope for this file. Files inside an open
        // workspace are already covered by the folder's scope, so this returns
        // false for them and only standalone files get a scope we must balance.
        let didStartAccess = url.startAccessingSecurityScopedResource()

        guard let text = readText(at: url) else {
            // The file isn't decodable as text (e.g. binary). Refuse to open it
            // rather than show empty content and clobber the file on the next save.
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            errorMessage = "Can't open “\(url.lastPathComponent)”: it doesn't appear to be a text file."
            return
        }

        let doc = EditorDocument(
            name: url.lastPathComponent,
            text: text,
            url: url,
            language: .detect(from: url)
        )
        doc.isSecurityScoped = didStartAccess
        openDocuments.append(doc)
        activeDocumentID = doc.id
    }

    func handleOpenFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        // `open(_:)` owns starting (and the matching stopping) of the scope.
        urls.forEach(open)
    }

    /// Reads a file as text, trying UTF-8 and then encoding auto-detection.
    /// Returns nil for content that can't be decoded (e.g. binary files).
    private func readText(at url: URL) -> String? {
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        var used: String.Encoding = .utf8
        if let s = try? String(contentsOf: url, usedEncoding: &used) { return s }
        return nil
    }

    func handleOpenFolder(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        setWorkspace(url, accessing: true)
        saveBookmark(for: url)
    }

    // MARK: - Tabs

    func activate(_ doc: EditorDocument) {
        activeDocumentID = doc.id
    }

    func close(_ doc: EditorDocument) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == doc.id }) else { return }
        // Balance the security scope started in open(_:).
        if doc.isSecurityScoped, let url = doc.url {
            url.stopAccessingSecurityScopedResource()
        }
        openDocuments.remove(at: idx)
        // If this was the last open document under a retained old workspace,
        // release that workspace's scope too.
        releaseRetainedScopeIfUnused(for: doc.url)
        if activeDocumentID == doc.id {
            let next = min(idx, openDocuments.count - 1)
            activeDocumentID = openDocuments.indices.contains(next) ? openDocuments[next].id : nil
        }
    }

    func closeActive() {
        if let doc = activeDocument { close(doc) }
    }

    // MARK: - Saving

    func saveActive() {
        guard let doc = activeDocument, let url = doc.url else { return }
        do {
            try doc.text.write(to: url, atomically: true, encoding: .utf8)
            doc.isDirty = false
        } catch {
            // Best-effort save; a production app would surface this to the user.
            print("Save failed: \(error)")
        }
    }

    // MARK: - New file

    func createNewFile() {
        let baseDir = workspaceURL ?? documentsURL
        let url = uniqueURL(in: baseDir, base: "untitled", ext: "txt")
        try? "".write(to: url, atomically: true, encoding: .utf8)
        let doc = EditorDocument(name: url.lastPathComponent, text: "", url: url, language: .plaintext)
        openDocuments.append(doc)
        activeDocumentID = doc.id
        refreshTree()
    }

    private func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        var n = 1
        var candidate = dir.appendingPathComponent("\(base)-\(n).\(ext)")
        while FileManager.default.fileExists(atPath: candidate.path) {
            n += 1
            candidate = dir.appendingPathComponent("\(base)-\(n).\(ext)")
        }
        return candidate
    }

    // MARK: - File tree

    private func setWorkspace(_ url: URL, accessing: Bool) {
        // Handle the previous workspace's security scope, if any.
        if workspaceAccessing, let old = workspaceURL, old != url {
            if openDocuments.contains(where: { isURL($0.url, under: old) }) {
                // Documents from the old workspace are still open and rely on
                // its scope to save — keep it alive until they all close.
                retainedWorkspaceScopes.insert(old)
            } else {
                old.stopAccessingSecurityScopedResource()
            }
        }
        workspaceURL = url
        workspaceAccessing = accessing
        refreshTree()
    }

    /// True if `url` is `base` or lives inside it.
    private func isURL(_ url: URL?, under base: URL) -> Bool {
        guard let url else { return false }
        let target = url.standardizedFileURL.path
        let root = base.standardizedFileURL.path
        return target == root || target.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// Releases any retained old-workspace scope that no open document needs.
    private func releaseRetainedScopeIfUnused(for url: URL?) {
        guard let url else { return }
        for scope in retainedWorkspaceScopes where isURL(url, under: scope) {
            if !openDocuments.contains(where: { isURL($0.url, under: scope) }) {
                scope.stopAccessingSecurityScopedResource()
                retainedWorkspaceScopes.remove(scope)
            }
        }
    }

    func refreshTree() {
        guard let root = workspaceURL else { fileTree = []; return }
        fileTree = buildTree(at: root)
    }

    private func buildTree(at url: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let nodes: [FileNode] = contents.compactMap { child in
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileNode(
                url: child,
                name: child.lastPathComponent,
                isDirectory: isDir,
                children: isDir ? buildTree(at: child) : nil
            )
        }

        // Directories first, then files, both alphabetical.
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Security-scoped bookmark persistence

    private func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    private func restoreWorkspace() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        setWorkspace(url, accessing: true)
    }

    // MARK: - Command palette commands

    var paletteCommands: [PaletteCommand] {
        var cmds: [PaletteCommand] = [
            PaletteCommand(title: "New File", shortcut: "⌘N") { [weak self] in self?.createNewFile() },
            PaletteCommand(title: "Open File…", shortcut: "⌘O") { [weak self] in self?.importFile = true },
            PaletteCommand(title: "Open Folder…", shortcut: "⌘⇧O") { [weak self] in self?.importFolder = true },
            PaletteCommand(title: "Save", shortcut: "⌘S") { [weak self] in self?.saveActive() },
            PaletteCommand(title: "Close Tab", shortcut: "⌘W") { [weak self] in self?.closeActive() },
            PaletteCommand(title: "Toggle Sidebar", shortcut: "⌘B") { [weak self] in self?.sidebarVisible.toggle() },
            PaletteCommand(title: "Toggle Theme", shortcut: "⌘⇧K") { [weak self] in self?.toggleTheme() },
        ]
        if activeDocument != nil {
            for lang in Language.allCases {
                cmds.append(PaletteCommand(title: "Change Language: \(lang.displayName)", shortcut: nil) { [weak self] in
                    self?.activeDocument?.language = lang
                })
            }
        }
        return cmds
    }
}

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let shortcut: String?
    let action: () -> Void
}
