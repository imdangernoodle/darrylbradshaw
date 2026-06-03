import SwiftUI
import UIKit

/// Token categories produced by the highlighter.
enum TokenKind {
    case keyword, type, string, number, comment
}

/// VS Code–inspired editor themes (Dark+ and Light+).
enum EditorTheme: Equatable {
    case dark, light

    var font: UIFont {
        UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    }

    var background: UIColor {
        switch self {
        case .dark: return UIColor(hex: 0x1E1E1E)
        case .light: return UIColor(hex: 0xFFFFFF)
        }
    }

    var foreground: UIColor {
        switch self {
        case .dark: return UIColor(hex: 0xD4D4D4)
        case .light: return UIColor(hex: 0x333333)
        }
    }

    var gutterBackground: UIColor {
        switch self {
        case .dark: return UIColor(hex: 0x1E1E1E)
        case .light: return UIColor(hex: 0xFFFFFF)
        }
    }

    var gutterText: UIColor {
        switch self {
        case .dark: return UIColor(hex: 0x858585)
        case .light: return UIColor(hex: 0xAFAFAF)
        }
    }

    func color(for kind: TokenKind) -> UIColor {
        switch self {
        case .dark:
            switch kind {
            case .keyword: return UIColor(hex: 0x569CD6)
            case .type:    return UIColor(hex: 0x4EC9B0)
            case .string:  return UIColor(hex: 0xCE9178)
            case .number:  return UIColor(hex: 0xB5CEA8)
            case .comment: return UIColor(hex: 0x6A9955)
            }
        case .light:
            switch kind {
            case .keyword: return UIColor(hex: 0x0000FF)
            case .type:    return UIColor(hex: 0x267F99)
            case .string:  return UIColor(hex: 0xA31515)
            case .number:  return UIColor(hex: 0x098658)
            case .comment: return UIColor(hex: 0x008000)
            }
        }
    }

    // SwiftUI conveniences
    var swiftBackground: Color { Color(background) }
    var chrome: Color { self == .dark ? Color(hex: 0x252526) : Color(hex: 0xF3F3F3) }
    var chromeBar: Color { self == .dark ? Color(hex: 0x333333) : Color(hex: 0xDDDDDD) }
    var accent: Color { Color(hex: 0x007ACC) }
    var foregroundColor: Color { Color(foreground) }
    var dim: Color { self == .dark ? Color(hex: 0x8A8A8A) : Color(hex: 0x6C6C6C) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(UIColor(hex: hex)) }
}
