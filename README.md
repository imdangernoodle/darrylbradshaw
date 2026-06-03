# CodePad — a VS Code–style code editor for iPad

A native **SwiftUI / iPadOS** code editor inspired by Visual Studio Code. It is
*not* a port of Microsoft's Electron app (that can't run natively on iPadOS, and
the App Store wouldn't allow the desktop bundle). Instead it recreates the parts
of VS Code that matter on an iPad as a real native app.

## What's included

- **VS Code–style layout** — activity bar, collapsible file-explorer sidebar,
  editor tabs, and a dark/light theme that mirrors VS Code's *Dark+* / *Light+*.
- **Native code editor** built on `UITextView` with:
  - a **line-number gutter**,
  - **syntax highlighting** for Swift, JS/TS, Python, JSON, HTML/XML, CSS,
    Markdown, shell, C/C++, Java, Go, Rust, Ruby, and YAML,
  - a horizontally scrolling **symbol key-bar** above the on-screen keyboard
    (Tab, brackets, quotes, operators…) so coding works without a hardware
    keyboard.
- **File access via the Files app** — open any folder (security-scoped, and
  remembered across launches via a bookmark) or individual files, edit, and save
  in place.
- **Command palette** (`⌘⇧P`) and full hardware-keyboard shortcuts.
- **Tabs** with dirty-state indicators.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘N` | New file |
| `⌘O` | Open file… |
| `⌘⇧O` | Open folder… |
| `⌘S` | Save |
| `⌘W` | Close tab |
| `⌘B` | Toggle sidebar |
| `⌘⇧P` | Command palette |
| `⌘⇧K` | Toggle dark/light theme |

## Building & running

> Requires **Xcode 16 or newer** on a Mac (the project uses Xcode's
> file-system-synchronized group format, `objectVersion = 77`).

1. Open `CodePad/CodePad.xcodeproj` in Xcode.
2. Select the **CodePad** scheme.
3. To run on your **iPad**:
   - Connect the iPad (or use a wireless device).
   - In **Signing & Capabilities**, pick your Apple ID team. The bundle id is
     `com.darrylbradshaw.CodePad` — change it if Xcode reports it's taken.
   - Choose your iPad as the run destination and press **⌘R**.
   - First launch on a personal (free) Apple ID: trust the developer profile in
     **Settings → General → VPN & Device Management** on the iPad.
4. To try it without hardware, run on the **iPad Pro simulator**.

## Project layout

```
CodePad/
  CodePad.xcodeproj/
  CodePad/
    CodePadApp.swift          # @main App + keyboard command menus
    ContentView.swift         # Root 3-pane layout + file importers
    Models/
      WorkspaceStore.swift    # Shared state: tabs, tree, theme, commands
      EditorDocument.swift    # One open file/tab
      FileNode.swift          # File-tree node
      Language.swift          # Language detection + icons
    Editor/
      CodeEditorView.swift    # UITextView editor + gutter + key-bar
      SyntaxHighlighter.swift # Regex token highlighter
      Theme.swift             # Dark+/Light+ colors
    Views/
      ActivityBarView.swift
      SidebarView.swift
      TabBarView.swift
      TabBarView / WelcomeView / CommandPaletteView
    Assets.xcassets/
```

## Roadmap / ideas

- Find & replace, multi-cursor, code folding.
- A proper tokenizer (e.g. Tree-sitter) for richer highlighting.
- Git integration and an integrated terminal (via SSH).
- File rename/delete from the sidebar.

This is a solid, hackable starting point rather than a finished product — PRs
welcome.
