import SwiftUI
import UIKit

/// SwiftUI wrapper around a UITextView-based code editor with a line-number
/// gutter, syntax highlighting and an iPad touch shortcut key-bar.
struct CodeEditorView: UIViewRepresentable {
    @ObservedObject var document: EditorDocument
    let theme: EditorTheme

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    func makeUIView(context: Context) -> LineNumberTextView {
        let tv = LineNumberTextView()
        tv.delegate = context.coordinator
        tv.applyTheme(theme)
        tv.text = document.text
        SyntaxHighlighter.apply(to: tv, language: document.language, theme: theme)
        tv.setNeedsDisplay()
        return tv
    }

    func updateUIView(_ tv: LineNumberTextView, context: Context) {
        context.coordinator.document = document
        tv.applyTheme(theme)

        var needsHighlight = false
        if tv.text != document.text {
            let sel = tv.selectedRange
            tv.text = document.text
            // Validate the *whole* range against the new length; a selection
            // whose end ran past the shrunken text would crash UITextView.
            let newLength = (tv.text as NSString).length
            tv.selectedRange = (sel.location + sel.length <= newLength)
                ? sel
                : NSRange(location: min(sel.location, newLength), length: 0)
            needsHighlight = true
        }
        if context.coordinator.lastLanguage != document.language || context.coordinator.lastTheme != theme {
            context.coordinator.lastLanguage = document.language
            context.coordinator.lastTheme = theme
            needsHighlight = true
        }
        if needsHighlight {
            SyntaxHighlighter.apply(to: tv, language: document.language, theme: theme)
        }
        tv.setNeedsDisplay()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var document: EditorDocument
        var lastLanguage: Language
        var lastTheme: EditorTheme?
        private var highlightWorkItem: DispatchWorkItem?

        init(document: EditorDocument) {
            self.document = document
            self.lastLanguage = document.language
        }

        func textViewDidChange(_ textView: UITextView) {
            document.text = textView.text
            document.isDirty = true
            textView.setNeedsDisplay() // refresh gutter line numbers

            guard let tv = textView as? LineNumberTextView else { return }
            // Debounce re-highlighting so typing stays smooth.
            highlightWorkItem?.cancel()
            let theme = lastTheme ?? .dark
            let language = document.language
            let work = DispatchWorkItem { [weak tv] in
                guard let tv else { return }
                SyntaxHighlighter.apply(to: tv, language: language, theme: theme)
            }
            highlightWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView as? LineNumberTextView)?.setNeedsDisplay()
        }
    }
}

/// UITextView subclass that draws a line-number gutter and supplies a
/// horizontally scrolling shortcut bar above the on-screen keyboard.
final class LineNumberTextView: UITextView {

    let gutterWidth: CGFloat = 48
    var gutterTextColor: UIColor = UIColor(hex: 0x858585)
    var gutterBackgroundColor: UIColor = UIColor(hex: 0x1E1E1E)
    private var gutterFont: UIFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    private var currentTheme: EditorTheme = .dark

    func applyTheme(_ theme: EditorTheme) {
        currentTheme = theme
        backgroundColor = theme.background
        textColor = theme.foreground
        font = theme.font
        tintColor = theme.accent.uiColor
        gutterTextColor = theme.gutterText
        gutterBackgroundColor = theme.gutterBackground
        keyboardAppearance = (theme == .dark) ? .dark : .light
        styleShortcutBar(for: theme)
        configureBehaviour()
    }

    private func configureBehaviour() {
        autocorrectionType = .no
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        textContainerInset = UIEdgeInsets(top: 8, left: gutterWidth, bottom: 8, right: 8)
        if #available(iOS 17.0, *) {
            inlinePredictionType = .no
        }
    }

    // MARK: - Gutter drawing

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        gutterBackgroundColor.setFill()
        ctx.fill(CGRect(x: bounds.minX, y: rect.minY, width: gutterWidth, height: rect.height))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: gutterTextColor
        ]

        let ns = (text ?? "") as NSString
        let length = ns.length
        var charIndex = 0
        var lineNumber = 1

        while charIndex < length {
            let lineRange = ns.lineRange(for: NSRange(location: charIndex, length: 0))
            drawNumber(lineNumber, forCharacterRange: lineRange, attrs: attrs, dirtyRect: rect)
            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
        }
        // Trailing line: empty document, or text ending in a newline.
        if length == 0 || ns.character(at: length - 1) == 0x0A {
            drawTrailingNumber(lineNumber, attrs: attrs, dirtyRect: rect)
        }
    }

    private func drawNumber(_ n: Int, forCharacterRange charRange: NSRange,
                            attrs: [NSAttributedString.Key: Any], dirtyRect: CGRect) {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound else { return }
        let fragRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        paint(n, atY: fragRect.minY + textContainerInset.top, height: fragRect.height, attrs: attrs, dirtyRect: dirtyRect)
    }

    private func drawTrailingNumber(_ n: Int, attrs: [NSAttributedString.Key: Any], dirtyRect: CGRect) {
        let r = layoutManager.extraLineFragmentRect
        let height = r.height > 0 ? r.height : (font?.lineHeight ?? 18)
        paint(n, atY: r.minY + textContainerInset.top, height: height, attrs: attrs, dirtyRect: dirtyRect)
    }

    private func paint(_ n: Int, atY y: CGFloat, height: CGFloat,
                       attrs: [NSAttributedString.Key: Any], dirtyRect: CGRect) {
        guard y + height >= dirtyRect.minY, y <= dirtyRect.maxY else { return }
        let s = "\(n)" as NSString
        let size = s.size(withAttributes: attrs)
        let x = gutterWidth - size.width - 8
        s.draw(at: CGPoint(x: x, y: y + (height - size.height) / 2), withAttributes: attrs)
    }

    // MARK: - Shortcut key-bar (input accessory)

    private lazy var shortcutBar: UIView = makeShortcutBar()
    override var inputAccessoryView: UIView? { shortcutBar }

    // References kept so the bar can be re-coloured when the theme changes.
    private weak var shortcutScrollView: UIScrollView?
    private var shortcutButtons: [UIButton] = []
    private weak var dismissButton: UIButton?

    private let shortcuts: [(label: String, insert: String)] = [
        ("Tab", "    "), ("{", "{"), ("}", "}"), ("[", "["), ("]", "]"),
        ("(", "("), (")", ")"), ("<", "<"), (">", ">"), ("\"", "\""),
        ("'", "'"), ("`", "`"), ("=", "="), ("+", "+"), ("-", "-"),
        ("*", "*"), ("/", "/"), (":", ":"), (";", ";"), (".", "."),
        (",", ","), ("|", "|"), ("&", "&"), ("$", "$"), ("#", "#"),
        ("_", "_"), ("!", "!"), ("?", "?"), ("@", "@"), ("%", "%"),
    ]

    private func makeShortcutBar() -> UIView {
        let bar = UIScrollView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        bar.autoresizingMask = [.flexibleWidth]
        bar.showsHorizontalScrollIndicator = false
        bar.alwaysBounceHorizontal = true
        shortcutScrollView = bar

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: bar.frameLayoutGuide.heightAnchor),
        ])

        for item in shortcuts {
            stack.addArrangedSubview(makeKey(label: item.label, insert: item.insert))
        }
        // Dismiss-keyboard key on the far right.
        let dismiss = UIButton(type: .system)
        dismiss.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        dismiss.addAction(UIAction { [weak self] _ in self?.resignFirstResponder() }, for: .touchUpInside)
        dismiss.widthAnchor.constraint(equalToConstant: 44).isActive = true
        dismiss.heightAnchor.constraint(equalToConstant: 32).isActive = true
        stack.addArrangedSubview(dismiss)
        dismissButton = dismiss

        styleShortcutBar(for: currentTheme)
        return bar
    }

    private func makeKey(label: String, insert: String) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = label
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        // UIButton.Configuration ignores titleLabel.font, so set the monospaced
        // font through the configuration's title attributes transformer.
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in
            self?.insertText(insert)
        }, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        shortcutButtons.append(button)
        return button
    }

    /// Recolours the shortcut bar to match the active editor theme.
    private func styleShortcutBar(for theme: EditorTheme) {
        guard let bar = shortcutScrollView else { return }
        let dark = theme == .dark
        bar.backgroundColor = dark ? UIColor(hex: 0x2D2D2D) : UIColor(hex: 0xD1D4DB)
        let keyBackground = dark ? UIColor(hex: 0x3A3A3A) : UIColor.white
        let keyForeground = dark ? UIColor.white : UIColor(hex: 0x1A1A1A)
        for button in shortcutButtons {
            button.configuration?.background.backgroundColor = keyBackground
            button.configuration?.baseForegroundColor = keyForeground
        }
        dismissButton?.tintColor = keyForeground
    }
}

private extension Color {
    var uiColor: UIColor { UIColor(self) }
}
