import Foundation

/// The on-screen modifier keys and special keys the toolbar can emit. Each maps to
/// the raw bytes a terminal expects. Plain printable characters are sent directly
/// (and optionally transformed by a sticky `Ctrl`), so they live outside this enum.
enum TerminalSpecialKey: Hashable {
    case escape
    case tab
    case up
    case down
    case left
    case right

    /// The byte sequence to transmit. Arrow keys use the canonical xterm
    /// "cursor key" application-mode-agnostic CSI sequences (`ESC [ A`, etc.).
    var bytes: [UInt8] {
        switch self {
        case .escape: return [0x1b]
        case .tab:    return [0x09]
        case .up:     return [0x1b, 0x5b, 0x41] // ESC [ A
        case .down:   return [0x1b, 0x5b, 0x42] // ESC [ B
        case .right:  return [0x1b, 0x5b, 0x43] // ESC [ C
        case .left:   return [0x1b, 0x5b, 0x44] // ESC [ D
        }
    }

    var data: Data { Data(bytes) }
}

/// Translates a printable character under a held `Ctrl` modifier into the
/// corresponding control byte (e.g. `c` -> 0x03 / SIGINT, `[` -> 0x1b / ESC).
///
/// Follows the standard ASCII control mapping: a letter `A...Z`/`a...z` becomes
/// `value & 0x1f`; the symbols `@ [ \ ] ^ _ ?` map to 0x00, 0x1b...0x1f, 0x7f.
/// Returns `nil` when the character has no control equivalent, so callers can fall
/// back to sending it verbatim.
enum CtrlKeyEncoder {
    static func controlByte(for character: Character) -> UInt8? {
        guard let ascii = character.asciiValue else { return nil }
        switch ascii {
        case 0x40...0x5f:           // @ A...Z [ \ ] ^ _
            return ascii & 0x1f
        case 0x61...0x7a:           // a...z -> same as uppercase control codes
            return (ascii - 0x20) & 0x1f
        case 0x3f:                  // ? -> DEL (0x7f)
            return 0x7f
        default:
            return nil
        }
    }
}
