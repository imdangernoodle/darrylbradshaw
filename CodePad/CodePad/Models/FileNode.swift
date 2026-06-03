import Foundation

/// A node in the file-explorer tree. `children == nil` marks a leaf (file).
struct FileNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    var id: URL { url }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
