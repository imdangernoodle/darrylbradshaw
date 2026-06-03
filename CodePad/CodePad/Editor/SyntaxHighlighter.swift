import Foundation
import UIKit

/// A single highlighting rule: a precompiled pattern and the token kind it paints.
struct HighlightRule {
    let regex: NSRegularExpression
    let kind: TokenKind

    init?(_ pattern: String, _ kind: TokenKind, options: NSRegularExpression.Options = []) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        self.regex = re
        self.kind = kind
    }
}

/// Lightweight regex-based highlighter. Rules are ordered so that later rules
/// (strings, then comments) override earlier ones (keywords, numbers).
enum SyntaxHighlighter {
    private static var cache: [Language: [HighlightRule]] = [:]

    static func apply(to textView: UITextView, language: Language, theme: EditorTheme) {
        // Don't disturb in-progress IME composition.
        guard textView.markedTextRange == nil else { return }
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }
        // Keep highlighting responsive on very large files.
        guard fullRange.length <= 200_000 else {
            storage.addAttribute(.foregroundColor, value: theme.foreground, range: fullRange)
            return
        }

        let selected = textView.selectedRange
        let string = storage.string
        storage.beginEditing()
        storage.setAttributes([.foregroundColor: theme.foreground, .font: theme.font], range: fullRange)
        for rule in rules(for: language) {
            rule.regex.enumerateMatches(in: string, options: [], range: fullRange) { match, _, _ in
                guard let r = match?.range, r.location != NSNotFound else { return }
                storage.addAttribute(.foregroundColor, value: theme.color(for: rule.kind), range: r)
            }
        }
        storage.endEditing()
        textView.selectedRange = selected
    }

    private static func rules(for language: Language) -> [HighlightRule] {
        if let cached = cache[language] { return cached }
        let built = build(for: language)
        cache[language] = built
        return built
    }

    private static func build(for language: Language) -> [HighlightRule] {
        var rules: [HighlightRule?] = []

        func keywords(_ words: [String]) -> HighlightRule? {
            let alt = words.joined(separator: "|")
            return HighlightRule("\\b(?:\(alt))\\b", .keyword)
        }
        func types() -> HighlightRule? {
            // Capitalized identifiers read as types/classes in most languages.
            HighlightRule("\\b[A-Z][A-Za-z0-9_]*\\b", .type)
        }
        let numberRule = HighlightRule("\\b\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", .number)
        let dquote = HighlightRule("\"(?:\\\\.|[^\"\\\\])*\"", .string)
        let squote = HighlightRule("'(?:\\\\.|[^'\\\\])*'", .string)
        let backtick = HighlightRule("`(?:\\\\.|[^`\\\\])*`", .string)
        let slashComment = HighlightRule("//[^\\n]*", .comment)
        let blockComment = HighlightRule("/\\*[\\s\\S]*?\\*/", .comment)
        let hashComment = HighlightRule("#[^\\n]*", .comment)
        let htmlComment = HighlightRule("<!--[\\s\\S]*?-->", .comment)

        switch language {
        case .swift:
            rules += [keywords(["func","let","var","if","else","guard","return","for","while","in","switch","case","default","break","continue","struct","class","enum","protocol","extension","import","init","self","nil","true","false","public","private","internal","fileprivate","static","final","override","mutating","throws","try","catch","throw","async","await","weak","lazy","some","any","where","do","defer","typealias","associatedtype"])]
            rules += [types(), numberRule, dquote, slashComment, blockComment]
        case .javascript, .typescript:
            rules += [keywords(["function","let","const","var","if","else","return","for","while","switch","case","default","break","continue","class","extends","new","this","null","undefined","true","false","async","await","try","catch","finally","throw","import","export","from","as","of","in","typeof","instanceof","interface","type","enum","public","private","readonly"])]
            rules += [types(), numberRule, dquote, squote, backtick, slashComment, blockComment]
        case .python:
            rules += [keywords(["def","class","if","elif","else","return","for","while","in","import","from","as","try","except","finally","raise","with","lambda","None","True","False","and","or","not","is","pass","break","continue","global","nonlocal","yield","async","await","self"])]
            rules += [types(), numberRule, dquote, squote, hashComment]
        case .json:
            rules += [numberRule, dquote, keywords(["true","false","null"])]
        case .html, .xml:
            rules += [HighlightRule("</?[A-Za-z][^>]*>", .keyword), dquote, htmlComment]
        case .css:
            rules += [HighlightRule("[.#]?[-A-Za-z_][\\w-]*\\s*(?=\\{)", .type), HighlightRule("[-A-Za-z]+(?=\\s*:)", .keyword), numberRule, dquote, blockComment]
        case .markdown:
            rules += [HighlightRule("^#{1,6}\\s.*$", .keyword, options: [.anchorsMatchLines]), HighlightRule("`[^`]*`", .string), HighlightRule("\\*\\*[^*]+\\*\\*", .type)]
        case .shell:
            rules += [keywords(["if","then","else","elif","fi","for","while","do","done","case","esac","function","return","export","local","echo","cd","exit"])]
            rules += [numberRule, dquote, squote, hashComment]
        case .yaml:
            rules += [HighlightRule("^\\s*[-\\w]+(?=:)", .keyword, options: [.anchorsMatchLines]), numberRule, dquote, squote, hashComment]
        case .c, .cpp, .java, .go, .rust, .ruby:
            let base = ["if","else","for","while","return","switch","case","default","break","continue","struct","class","enum","void","int","float","double","char","bool","new","delete","public","private","protected","static","const","true","false","null","import","package","func","let","var","fn","mut","def","end","module","require"]
            rules += [keywords(base), types(), numberRule, dquote, squote]
            rules += [slashComment, blockComment]
            if language == .ruby { rules += [hashComment] }
        case .plaintext:
            break
        }

        return rules.compactMap { $0 }
    }
}
