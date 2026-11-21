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

import SwiftUI
import AppKit
import MacVisualizerCore

// MARK: - Sections and documents

/// The three panes of the Acknowledgements window, each backed by a file bundled as an app resource.
enum AcknowledgementsSection: String, CaseIterable, Identifiable {
    case credits, thirdParty, license

    var id: String { rawValue }

    var title: String {
        switch self {
        case .credits: return "Credits"
        case .thirdParty: return "Third-Party Licenses"
        case .license: return "License"
        }
    }

    /// File name as bundled (the single source of truth for the text).
    var fileName: String {
        switch self {
        case .credits: return "NOTICE"
        case .thirdParty: return "THIRD_PARTY_NOTICES.md"
        case .license: return "LICENSE"
        }
    }

    /// LICENSE is hard-wrapped plain text: shown verbatim in one monospaced block.
    var isPreformatted: Bool { self == .license }
}

/// A block ready to draw: inline markup already interpreted, so a view body does no parsing.
enum AckBlock {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case bullet(AttributedString)
    case code(String)
    case rule
}

extension AckBlock {
    var isBullet: Bool {
        if case .bullet = self { return true }
        return false
    }
}

enum AckDocument {
    case blocks([AckBlock])
    case missing(fileName: String)
}

/// Loads and parses the three documents once, when the window's content is created.
final class AcknowledgementsModel: ObservableObject {
    let documents: [AcknowledgementsSection: AckDocument]

    init(bundle: Bundle = .main) {
        var docs: [AcknowledgementsSection: AckDocument] = [:]
        for section in AcknowledgementsSection.allCases {
            docs[section] = Self.load(section, bundle: bundle)
        }
        documents = docs
    }

    static func load(_ section: AcknowledgementsSection, bundle: Bundle) -> AckDocument {
        let name = section.fileName as NSString
        guard let url = bundle.url(forResource: name.deletingPathExtension,
                                   withExtension: name.pathExtension.isEmpty ? nil : name.pathExtension),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return .missing(fileName: section.fileName) }
        let blocks = section.isPreformatted ? MarkdownParser.preformatted(text) : MarkdownParser.parse(text)
        return .blocks(blocks.map(Self.render))
    }

    private static func render(_ block: MarkdownBlock) -> AckBlock {
        switch block {
        case .heading(let level, let text):
            return .heading(level: level, text: styled(text, codeSize: level == 3 ? 12.5 : 14, weight: .semibold))
        case .paragraph(let text): return .paragraph(styled(text, codeSize: 12))
        case .bullet(let text): return .bullet(styled(text, codeSize: 12))
        case .code(let text): return .code(text)
        case .rule: return .rule
        }
    }

    /// Interprets inline Markdown and gives `code` spans a monospaced face.
    private static func styled(_ text: String, codeSize: CGFloat, weight: Font.Weight = .regular) -> AttributedString {
        var attr = MarkdownInline.attributed(text)
        for run in attr.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attr[run.range].font = .system(size: codeSize, weight: weight, design: .monospaced)
        }
        return attr
    }
}

// MARK: - Opening the window from AppKit

/// Lets AppKit code (the right-click menu) open the `Window(id: "acknowledgements")` scene.
final class AcknowledgementsRouter {
    static let shared = AcknowledgementsRouter()
    /// Set by a view in the main scene (the only place `OpenWindowAction` is available).
    var openWindow: (() -> Void)?

    func open() {
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum AppIdentity {
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "MacVisualizer"
    }
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "Version \(short) (\(build))"
    }
    static let repositoryURL = URL(string: "https://github.com/edespino/mac-visualizer")!
    static let copyright = "Copyright 2026 Ed Espino"
    static let licenseLine = "Licensed under the Apache License, Version 2.0"
}

// MARK: - View

struct AcknowledgementsView: View {
    @StateObject private var model: AcknowledgementsModel
    @State private var section: AcknowledgementsSection

    init(initialSection: AcknowledgementsSection = .credits) {
        _model = StateObject(wrappedValue: AcknowledgementsModel())
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            AckHeader()
            sectionPicker
            Divider()
            AckBody(document: model.documents[section] ?? .missing(fileName: section.fileName))
                .id(section)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $section) {
            ForEach(AcknowledgementsSection.allCases) { s in
                Text(s.title).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }
}

private struct AckHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppIdentity.name)
                    .font(.system(size: 22, weight: .semibold))
                Text(AppIdentity.versionLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(AppIdentity.copyright)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(AppIdentity.licenseLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Link("github.com/edespino/mac-visualizer", destination: AppIdentity.repositoryURL)
                    .font(.system(size: 12))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
}

private struct AckBody: View {
    let document: AckDocument

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: 704, alignment: .leading)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder private var content: some View {
        switch document {
        case .blocks(let blocks):
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    AckBlockView(block: block, isFirst: index == 0,
                                 afterBullet: index > 0 && blocks[index - 1].isBullet)
                }
            }
        case .missing(let name):
            Text("\(name) could not be found in the app bundle.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AckBlockView: View {
    let block: AckBlock
    let isFirst: Bool
    var afterBullet: Bool = false

    var body: some View {
        switch block {
        case .heading(let level, let text): heading(level, text)
        case .paragraph(let text): paragraph(text)
        case .bullet(let text): bullet(text)
        case .code(let text): codeBlock(text)
        case .rule: rule
        }
    }

    private func heading(_ level: Int, _ text: AttributedString) -> some View {
        let size: CGFloat = level == 1 ? 24 : (level == 2 ? 18 : 14)
        let weight: Font.Weight = level == 3 ? .semibold : (level == 1 ? .bold : .semibold)
        let top: CGFloat = isFirst ? 0 : (level == 1 ? 26 : (level == 2 ? 26 : 20))
        return Text(text)
            .font(.system(size: size, weight: weight))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, top)
            .padding(.bottom, level == 3 ? 6 : 10)
    }

    private func paragraph(_ text: AttributedString) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, afterBullet ? 10 : 0)
            .padding(.bottom, 12)
    }

    private func bullet(_ text: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\u{2022}")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .center)
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.bottom, 6)
    }

    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
            .padding(.top, 4)
            .padding(.bottom, 16)
    }

    private var rule: some View {
        Divider()
            .padding(.vertical, 14)
    }
}

// MARK: - About panel

enum AboutPanel {
    /// Shows the standard About panel with credits (description, licence, repository, a pointer to Acknowledgements).
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
        NSApp.activate(ignoringOtherApps: true)
    }

    static func credits() -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.paragraphSpacing = 4
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: "A macOS audio visualizer for Spotify and Apple Music.\n", attributes: base))
        out.append(NSAttributedString(string: "\(AppIdentity.licenseLine)\n", attributes: base))
        var link = base
        link[.link] = AppIdentity.repositoryURL
        out.append(NSAttributedString(string: "github.com/edespino/mac-visualizer\n", attributes: link))
        out.append(NSAttributedString(string: "Third-party credits and licenses: \(AppIdentity.name) \u{203A} Acknowledgements\u{2026}", attributes: base))
        return out
    }
}

/// App-menu items: About (with credits) and Acknowledgements.
struct AboutAndAcknowledgementsMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About \(AppIdentity.name)") { AboutPanel.show() }
        Button("Acknowledgements\u{2026}") { openWindow(id: "acknowledgements") }
    }
}
