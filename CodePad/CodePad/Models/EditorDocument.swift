import Foundation

/// A single open file/tab in the editor.
final class EditorDocument: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL?
    @Published var name: String
    @Published var text: String
    @Published var language: Language
    @Published var isDirty: Bool = false

    /// True when `url` is a security-scoped resource we started accessing and
    /// must `stopAccessingSecurityScopedResource()` on when this tab closes.
    var isSecurityScoped: Bool = false

    init(name: String, text: String, url: URL?, language: Language) {
        self.name = name
        self.text = text
        self.url = url
        self.language = language
    }
}
