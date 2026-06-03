import Foundation

/// Supported source languages, used for syntax highlighting and the editor icon.
enum Language: String, CaseIterable, Identifiable {
    case swift, javascript, typescript, python, json, html, css
    case markdown, shell, c, cpp, java, go, rust, ruby, yaml, xml
    case plaintext

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .json: return "JSON"
        case .html: return "HTML"
        case .css: return "CSS"
        case .cpp: return "C++"
        case .c: return "C"
        case .yaml: return "YAML"
        case .xml: return "XML"
        case .plaintext: return "Plain Text"
        default: return rawValue.capitalized
        }
    }

    /// SF Symbol shown next to files of this language.
    var symbolName: String {
        switch self {
        case .swift: return "swift"
        case .markdown: return "text.alignleft"
        case .json, .yaml, .xml: return "curlybraces"
        case .html, .css: return "chevron.left.forwardslash.chevron.right"
        case .plaintext: return "doc.text"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Detect a language from a file URL's extension.
    static func detect(from url: URL) -> Language {
        switch url.pathExtension.lowercased() {
        case "swift": return .swift
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "py": return .python
        case "json": return .json
        case "html", "htm": return .html
        case "css", "scss", "less": return .css
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh": return .shell
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp": return .cpp
        case "java": return .java
        case "go": return .go
        case "rs": return .rust
        case "rb": return .ruby
        case "yml", "yaml": return .yaml
        case "xml", "plist": return .xml
        default: return .plaintext
        }
    }
}
