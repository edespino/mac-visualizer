//
// Copyright 2026 Ed Espino
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
// implied. See the License for the specific language governing
// permissions and limitations under the License.
//

import Foundation

/// One block of the small Markdown subset used by NOTICE and THIRD_PARTY_NOTICES.md.
/// Inline markup (bold, `code`, links) stays in the text; see `MarkdownInline`.
public enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case code(String)
    case rule
}

/// A deliberately small Markdown block parser: headings (levels clamped to 3), paragraphs,
/// bullet items (with indented continuation lines), fenced and 4-space-indented code blocks,
/// and horizontal rules. No tables, no nesting, no ordered lists.
public enum MarkdownParser {
    /// A paragraph whose lines are all shorter than this keeps its line breaks (a title /
    /// copyright block); longer lines are hard-wrapped prose and are re-flowed.
    static let shortLineLimit = 40

    public static func parse(_ text: String) -> [MarkdownBlock] {
        var out: [MarkdownBlock] = []
        var para: [String] = []
        var bullet: String?
        var code: [String]?
        var fence = false

        func flushPara() {
            guard !para.isEmpty else { return }
            let short = para.count >= 2 && para.allSatisfy { $0.count < shortLineLimit }
            out.append(.paragraph(para.joined(separator: short ? "\n" : " ")))
            para = []
        }
        func flushBullet() {
            if let b = bullet { out.append(.bullet(b)) }
            bullet = nil
        }
        func flushCode() {
            guard var c = code else { return }
            while let last = c.last, last.isEmpty { c.removeLast() }
            if !c.isEmpty || fence { out.append(.code(c.joined(separator: "\n"))) }
            code = nil
        }
        func flushAll() { flushPara(); flushBullet(); flushCode() }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if fence {
                if trimmed.hasPrefix("```") { flushCode(); fence = false } else { code?.append(raw) }
                continue
            }
            if trimmed.hasPrefix("```") {
                flushAll(); code = []; fence = true
                continue
            }
            if trimmed.isEmpty {
                flushPara(); flushBullet()
                if code != nil { code?.append("") }
                continue
            }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }
            let indented = indent.contains("\t") || indent.count >= 4
            if indented && para.isEmpty && bullet == nil {
                if code == nil { code = [] }
                code?.append(String(raw.dropFirst(raw.hasPrefix("\t") ? 1 : 4)))
                continue
            }
            flushCode()
            if bullet != nil && !indent.isEmpty {
                bullet! += " " + trimmed
                continue
            }
            if let level = headingLevel(trimmed) {
                flushPara(); flushBullet()
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                out.append(.heading(level: min(level, 3), text: title))
                continue
            }
            if isRule(trimmed) {
                flushPara(); flushBullet(); out.append(.rule)
                continue
            }
            if let item = bulletText(trimmed), indent.isEmpty {
                flushPara(); flushBullet(); bullet = item
                continue
            }
            if bullet != nil { flushBullet() }
            para.append(trimmed)
        }
        flushAll()
        return out
    }

    /// The whole text as one exact code block (for LICENSE): nothing re-flowed or stripped but
    /// leading/trailing blank lines.
    public static func preformatted(_ text: String) -> [MarkdownBlock] {
        let body = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
        return body.isEmpty ? [] : [.code(body)]
    }

    private static func headingLevel(_ s: String) -> Int? {
        let hashes = s.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = s.dropFirst(hashes)
        return rest.first == " " ? hashes : nil
    }

    private static func isRule(_ s: String) -> Bool {
        guard s.count >= 3, let c = s.first, "-*_".contains(c) else { return false }
        return s.allSatisfy { $0 == c }
    }

    private static func bulletText(_ s: String) -> String? {
        for marker in ["- ", "* ", "+ "] where s.hasPrefix(marker) {
            return String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

/// Inline Markdown (bold, italic, `code`, links) for one block, plus links for bare URLs.
public enum MarkdownInline {
    public static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        linkBareURLs(in: &result)
        return result
    }

    private static func linkBareURLs(in attr: inout AttributedString) {
        let plain = String(attr.characters)
        guard plain.contains("://"),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let full = NSRange(plain.startIndex..., in: plain)
        for match in detector.matches(in: plain, options: [], range: full) {
            guard let url = match.url, let r = Range(match.range, in: plain) else { continue }
            let lo = plain.distance(from: plain.startIndex, to: r.lowerBound)
            let hi = plain.distance(from: plain.startIndex, to: r.upperBound)
            let a = attr.characters.index(attr.startIndex, offsetBy: lo)
            let b = attr.characters.index(attr.startIndex, offsetBy: hi)
            let slice = attr[a..<b]
            let skip = slice.runs.contains { $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true }
            if !skip { attr[a..<b].link = url }
        }
    }
}
