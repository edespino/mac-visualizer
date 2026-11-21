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

/// The Lyrics section of the Settings form: overlay appearance tweaks,
/// the Gemini key and model, and a status line for the current track.
/// Lyrics settings are app-wide, so this binds straight to
/// `settings.lyrics` instead of the per-style profile.
struct LyricsSettingsSection: View {
    @Binding var settings: LyricsSettings
    /// Owner of the reset baseline; the `.resettable(\.lyrics.x, model)` rows read and write through it.
    let model: RenderModel
    @ObservedObject var lyrics: LyricsModel
    let keyStore: GeminiKeyStore

    @State private var keyText = ""
    @State private var hasKey = false
    @State private var keyError: String?
    @State private var confirmClearKey = false

    var body: some View {
        Section("Lyrics") {
            Toggle("Show lyrics", isOn: $settings.enabled)
                .help("Shows time-synced lyrics with an English translation over the visualizer.")
                .resettable(\.lyrics.enabled, model)

            Slider(value: $settings.textSize, in: 12...72, step: 1) {
                Text("Text size: \(Int(settings.textSize)) pt")
            } minimumValueLabel: { Text("12") } maximumValueLabel: { Text("72") }
                .resettable(\.lyrics.textSize, model)
            Slider(value: $settings.blockWidthFraction, in: 0.3...1.0) {
                Text("Block width: \(Int((settings.blockWidthFraction * 100).rounded()))%")
            } minimumValueLabel: { Text("30%") } maximumValueLabel: { Text("100%") }
                .resettable(\.lyrics.blockWidthFraction, model)
            Slider(value: $settings.activeLinePosition, in: 0.1...0.9) {
                Text("Active line position: \(Int((settings.activeLinePosition * 100).rounded()))% from top")
            } minimumValueLabel: { Text("Top") } maximumValueLabel: { Text("Bottom") }
            .help("Where the highlighted line is held in the window. Drag toward Top to place it higher; 50% centers it.")
                .resettable(\.lyrics.activeLinePosition, model)

            ColorPicker("Active line", selection: colorBinding(\.activeColor), supportsOpacity: false)

                .resettable(\.lyrics.activeColor, model)
            ColorPicker("Other lines", selection: colorBinding(\.otherColor), supportsOpacity: false)
                .resettable(\.lyrics.otherColor, model)
            Slider(value: $settings.otherOpacity, in: 0.1...1.0) {
                Text("Other lines opacity: \(Int((settings.otherOpacity * 100).rounded()))%")
            } minimumValueLabel: { Text("10%") } maximumValueLabel: { Text("100%") }
                .resettable(\.lyrics.otherOpacity, model)
            Picker("Past lines", selection: $settings.pastMode) {
                Text("Dim").tag(LyricsPastMode.dim)
                Text("Bright").tag(LyricsPastMode.bright)
                Text("Neutral").tag(LyricsPastMode.neutral)
            }
            .help("How lines already sung look compared with upcoming lines.")
                .resettable(\.lyrics.pastMode, model)
            Slider(value: fadeLinesBinding, in: 0...12, step: 1) {
                Text(settings.fadeLines == 0
                     ? "Fade by distance: off"
                     : "Fade by distance: \(settings.fadeLines) lines each side")
            } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("12") }
            .help("Non-active lines fade in as they approach the active line and fade out as they leave. This is how many lines stay visible on each side; Off shows every line at the same opacity.")
            .resettable(\.lyrics.fadeLines, model)

            Toggle("Drop shadow", isOn: $settings.shadowEnabled)
                .resettable(\.lyrics.shadowEnabled, model)
            Group {
                ColorPicker("Shadow color", selection: colorBinding(\.shadowColor), supportsOpacity: false)
                    .resettable(\.lyrics.shadowColor, model)
                Slider(value: $settings.shadowOpacity, in: 0...1) {
                    Text("Shadow opacity: \(Int((settings.shadowOpacity * 100).rounded()))%")
                } minimumValueLabel: { Text("0%") } maximumValueLabel: { Text("100%") }
                    .resettable(\.lyrics.shadowOpacity, model)
                Slider(value: $settings.shadowRadius, in: 0...20) {
                    Text(String(format: "Shadow blur: %.1f", settings.shadowRadius))
                } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("20") }
                    .resettable(\.lyrics.shadowRadius, model)
                Slider(value: $settings.shadowOffsetX, in: -10...10) {
                    Text(String(format: "Shadow offset X: %.1f", settings.shadowOffsetX))
                } minimumValueLabel: { Text("-10") } maximumValueLabel: { Text("10") }
                    .resettable(\.lyrics.shadowOffsetX, model)
                Slider(value: $settings.shadowOffsetY, in: -10...10) {
                    Text(String(format: "Shadow offset Y: %.1f", settings.shadowOffsetY))
                } minimumValueLabel: { Text("-10") } maximumValueLabel: { Text("10") }
                    .resettable(\.lyrics.shadowOffsetY, model)
            }
            .disabled(!settings.shadowEnabled)

            Picker("Beat bounce", selection: $settings.beatBounceMode) {
                Text("Off").tag(LyricBounceMode.off)
                Text("Lift").tag(LyricBounceMode.lift)
                Text("Glow").tag(LyricBounceMode.glow)
                Text("Both").tag(LyricBounceMode.both)
            }
            .disabled(!settings.shadowEnabled)
            .help("Pulses the active line's drop shadow to the beat: Lift raises it, Glow blurs it, Both does both. Needs Drop shadow on; reacts to live audio, not Demo Mode.")
                .resettable(\.lyrics.beatBounceMode, model)
            Slider(value: $settings.beatBounceStrength, in: 0.2...3) {
                Text(String(format: "Bounce strength: %.1f", settings.beatBounceStrength))
            } minimumValueLabel: { Text("Subtle") } maximumValueLabel: { Text("Strong") }
            .disabled(!settings.shadowEnabled)
                .resettable(\.lyrics.beatBounceStrength, model)

            LabeledContent("Local lyrics folder") {
                HStack {
                    Text(settings.localLyricsFolder.isEmpty
                         ? "None"
                         : (settings.localLyricsFolder as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                    Button("Clear") { settings.localLyricsFolder = "" }
                        .disabled(settings.localLyricsFolder.isEmpty)
                }
            }
            .help("A folder of .lrc files consulted before LRCLIB. A file named for the song (for example \"Artist - Title.lrc\") fills a song LRCLIB lacks or overrides what it returns.")

            Toggle("Use approximate matches", isOn: $settings.acceptApproximateMatches)
                .help("When LRCLIB has no recording of the exact length, show the closest one (a different edit of the song). Its timing may drift; use Lyric timing to nudge it. The status line flags an approximate match.")
                .resettable(\.lyrics.acceptApproximateMatches, model)

            Slider(value: timingOffsetBinding, in: -10_000...10_000, step: 100) {
                Text(timingOffsetLabel)
            } minimumValueLabel: { Text("-10s") } maximumValueLabel: { Text("+10s") }
            .help("Shifts the lyric timing against playback. Positive pulls lines earlier. Leave at synced (0) for an exact match.")
            .resettable(\.lyrics.timingOffsetMs, model)

            HStack {
                SecureField("Gemini API key", text: $keyText, prompt: Text(hasKey ? "Key saved" : "Not set"))
                    .onSubmit(saveKey)
                Button("Save", action: saveKey)
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Clear") { confirmClearKey = true }
                    .disabled(!hasKey)
            }
            .help("Used to translate lyrics. Stored in a private file on this Mac, not in settings.json.")
            .alert("Remove the Gemini API key?", isPresented: $confirmClearKey) {
                Button("Remove Key", role: .destructive) { clearKey() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This deletes the saved key file on this Mac. Lyrics translation will stop until you enter a key again.")
            }
            if let keyError {
                Text(keyError).font(.caption).foregroundStyle(.red)
            }
            TextField("Gemini model", text: $settings.geminiModel)

            LabeledContent("Status") {
                Text(statusText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onAppear { hasKey = keyStore.read() != nil }
    }

    private var statusText: String {
        lyrics.approximateMatch
            ? lyrics.status.message + "\nApproximate match - timing may drift"
            : lyrics.status.message
    }

    private var fadeLinesBinding: Binding<Float> {
        Binding(get: { Float(settings.fadeLines) }, set: { settings.fadeLines = Int($0.rounded()) })
    }

    private var timingOffsetBinding: Binding<Float> {
        Binding(get: { Float(settings.timingOffsetMs) },
                set: { settings.timingOffsetMs = Int(($0 / 100).rounded()) * 100 })
    }

    private var timingOffsetLabel: String {
        settings.timingOffsetMs == 0
            ? "Lyric timing: synced"
            : String(format: "Lyric timing: %+.1f s", Double(settings.timingOffsetMs) / 1000)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder of .lrc lyric files"
        if !settings.localLyricsFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (settings.localLyricsFolder as NSString).expandingTildeInPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            settings.localLyricsFolder = url.path
        }
    }

    private func saveKey() {
        let trimmed = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        writeKey(trimmed)
    }

    private func clearKey() {
        writeKey("")
    }

    private func writeKey(_ value: String) {
        do {
            try keyStore.write(value)
            keyError = nil
            keyText = ""
        } catch {
            // Keep what was typed so it does not have to be pasted again.
            keyError = "Could not save the key: \(error.localizedDescription)"
        }
        hasKey = keyStore.read() != nil
        lyrics.keyDidChange()
    }

    private func colorBinding(_ keyPath: WritableKeyPath<LyricsSettings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(settings[keyPath: keyPath]) },
            set: { settings[keyPath: keyPath] = RGBAColor($0) }
        )
    }
}

extension Color {
    /// SwiftUI color from stored sRGB components (alpha ignored: lyrics
    /// colors carry opacity separately).
    init(_ c: RGBAColor) {
        self.init(.sRGB, red: Double(c.r), green: Double(c.g), blue: Double(c.b), opacity: 1)
    }
}

extension RGBAColor {
    /// sRGB components of a SwiftUI color; alpha forced to 1.
    init(_ color: Color) {
        // The fallback must itself be an RGB color: reading red/green/blue
        // from a grayscale NSColor raises an Objective-C exception.
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        self.init(r: Float(ns.redComponent), g: Float(ns.greenComponent), b: Float(ns.blueComponent), a: 1)
    }
}
