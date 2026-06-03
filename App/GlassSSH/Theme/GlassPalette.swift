import SwiftUI

/// Semantic color tokens for the GlassSSH Liquid Glass design system.
///
/// These are the single source of truth for accent and status colors used across
/// the app. Components in the Theme kit and downstream UI units should reference
/// these tokens rather than hard-coding colors, so the palette can evolve in one
/// place. Colors adapt to light/dark appearance where appropriate.
public enum GlassPalette {
    /// Primary brand / interactive accent. Used to tint glass controls.
    public static let accent = Color.accentColor

    /// Background fill for terminal content. Deliberately near-black so terminal
    /// text and ANSI colors read with high contrast behind glass chrome.
    public static let terminalBackground = Color(
        red: 0.04,
        green: 0.05,
        blue: 0.07
    )

    /// Default foreground (text) color for terminal content.
    public static let terminalForeground = Color(
        red: 0.90,
        green: 0.92,
        blue: 0.95
    )

    /// Positive / connected status (e.g. an established session).
    public static let success = Color.green

    /// Cautionary status (e.g. a host key change awaiting confirmation).
    public static let warning = Color.orange

    /// Destructive / error status (e.g. a failed connection or rejected key).
    public static let danger = Color.red
}
