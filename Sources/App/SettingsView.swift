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

/// Active-visualizer-aware Settings (single resizable window, no tabs).
///
/// IA:
///  • A persistent header: the active-style picker (primary control), the
///    "Apply to all styles" toggle, and the Reset menu.
///  • A single scrolling grouped `Form`:
///     1. A DYNAMIC `"<Style> Controls"` section driven by `visualizerStyle`
///        (`controls(for:)`), showing only that style's knobs (or a quiet
///        placeholder for styles with none).
///     2. ALWAYS-visible global sections: Appearance, Effects, Audio,
///        Track Overlay, Window.
///
/// Most knobs edit the CURRENT style's profile via `bind(_:)` (so each style
/// remembers its own settings); style-specific tunables (Ribbon Wave count,
/// Polartone controls, particle tweaks, etc.) are top-level fields on
/// `VisualizerSettings` and bind directly to `$model.settings.*`.
struct SettingsView: View {
    @ObservedObject var model: RenderModel
    /// Not observed here: only `LyricsSettingsSection` needs its changes.
    let lyrics: LyricsModel

    @State private var confirmResetThisStyle = false
    @State private var confirmResetAllStyles = false
    @State private var confirmResetThisStyleFactory = false
    @State private var confirmResetAllFactory = false

    /// Selected sidebar category (nil falls back to the style's Controls).
    @State private var selection: SettingsCategory? = .styleControls
    /// Sidebar filter text (⌘F focuses it); narrows the category list.
    @State private var filter: String = ""
    @FocusState private var filterFocused: Bool

    // Populated from the palette registry so newly-added presets (e.g. the
    // viridis/plasma/... set) appear in the picker automatically.
    private let palettes = ColorPalette.orderedPresetNames
    private let fpsOptions = [30, 60, 120]

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 224, ideal: 248, max: 320)
        } detail: {
            detail
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: .infinity,
               minHeight: 500, idealHeight: 600, maxHeight: .infinity)
        // ⌘1–⌘9 / ⌘0 jump to the Nth visible category, ⌘F focuses the filter.
        // A key handler (not hidden buttons) so it has no pointer footprint.
        .onKeyPress(keys: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "f"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.characters == "f" {
                filterFocused = true
                return .handled
            }
            guard let n = Int(press.characters) else { return .ignored }
            let idx = (n == 0 ? 10 : n) - 1            // ⌘1→0 … ⌘9→8, ⌘0→9
            let cats = visibleCategories
            guard idx < cats.count else { return .ignored }
            selection = cats[idx]
            return .handled
        }
        // Lets the bare visualizer keys (h/l, j/k, …) work while Settings is active.
        .background(SettingsWindowRegistrar())
        // Deep links from the main window's right-click menu.
        .onAppear { applyRequestedCategory() }
        .onReceive(SettingsRouter.shared.requests) { applyRequestedCategory() }
        .alert("Reset \(model.settings.visualizerStyle.displayName) to \(baselineTargetName)?",
               isPresented: $confirmResetThisStyle) {
            Button("Reset", role: .destructive) { model.resetCurrentStyle(toFactory: false) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(resetThisStyleAlertMessage(target: baselineTargetName))
        }
        .alert("Reset \(model.settings.visualizerStyle.displayName) to factory defaults?",
               isPresented: $confirmResetThisStyleFactory) {
            Button("Reset", role: .destructive) { model.resetCurrentStyle(toFactory: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(resetThisStyleAlertMessage(target: "factory defaults"))
        }
        .alert("Reset ALL styles to \(baselineTargetName)?",
               isPresented: $confirmResetAllStyles) {
            Button("Reset All", role: .destructive) { model.resetEverything(toFactory: false) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(resetAllAlertMessage(target: baselineTargetName))
        }
        .alert("Reset ALL styles to factory defaults?",
               isPresented: $confirmResetAllFactory) {
            Button("Reset All", role: .destructive) { model.resetEverything(toFactory: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(resetAllAlertMessage(target: "factory defaults"))
        }
    }

    private func applyRequestedCategory() {
        if let cat = SettingsRouter.shared.takePending() {
            filter = ""
            selection = cat
        }
    }

    /// "your saved defaults" when a snapshot exists, otherwise "factory defaults".
    private var baselineTargetName: String {
        model.baseline.hasUserDefaults ? "your saved defaults" : "factory defaults"
    }

    private func resetAllAlertMessage(target: String) -> String {
        "This restores every visualizer style — each style's profile and all of its controls — and every app-wide setting to \(target). Your saved defaults file is not changed. Undo Change (⌘Z) restores the previous settings."
    }

    private func resetThisStyleAlertMessage(target: String) -> String {
        resetThisStyleBaseMessage.replacingOccurrences(of: "to defaults.", with: "to \(target).")
    }

    private var resetThisStyleBaseMessage: String {
        if model.settings.visualizerStyle == .ribbonWave {
            return "This restores the Ribbon Wave profile AND all its tunables (wave count, tilt, depth, sample count, height, amplitude, opacity, frequency, motion, smoothing, gain, stereo pan) to defaults. Other styles are unchanged."
        }
        if model.settings.visualizerStyle == .joyPlot {
            return "This restores the Joy Plot profile AND all its tunables (sample count, row spacing, row height, baseline offset, horizontal extent, bottom dim, opacity, beat boost, and beat half-life) to defaults. Other styles are unchanged."
        }
        if model.settings.visualizerStyle == .polartone {
            return "This restores the Polartone profile AND all its controls (radius, amplitude, color floor, rotation, point count, phase, line thickness, waveform clamp, and spiral options) to defaults. Other styles are unchanged."
        }
        if model.settings.visualizerStyle == .starNest {
            return "This restores the Star Nest profile AND all its controls (zoom, speed, formuparam, tile, step size, brightness, dark matter, distance fading, saturation, and density) to defaults. Other styles are unchanged."
        }
        if model.settings.visualizerStyle == .fireworks {
            return "This restores the Fireworks profile AND all its controls (max particles, base size, burst count and floor, beat scale base and intensity, burst area, angle jitter, base and spread speed, gravity, drag, and lifetime) to defaults. Shared particle size/speed are unchanged. Other styles are unchanged."
        }
        if model.settings.visualizerStyle == .particles {
            return "This restores the Particles profile AND all its controls (max particles, base size, initial and respawn velocity, respawn bounds, base brightness and jitter, brightness cap, bass threshold, low-band percent, bass impulse, bass brightness and size gain, size cap, velocity damping, return rate, and beat half-life and pulse) to defaults. Shared particle size/speed are unchanged. Other styles are unchanged."
        }
        return "This restores the \(model.settings.visualizerStyle.displayName) profile to defaults. Other styles are unchanged."
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        // Rows are explicit Buttons that set `selection` themselves, rather than
        // relying on List/NavigationSplitView selection (which did not respond to
        // the mouse here). The List takes no selection binding.
        List {
            Section {
                Picker("Active Visualizer", selection: $model.settings.visualizerStyle) {
                    ForEach(model.settings.enabledStyles, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                    .resettable(\.visualizerStyle, model)
                Toggle("Apply edits to all styles", isOn: $model.applyToAllStyles)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("When on, per-visualization edits (palette, gain, glow, bands) fan out to every style's profile at once.")
                TextField("Filter (⌘F)", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .focused($filterFocused)
            }
            let globals = visibleCategories.filter(\.isGlobal)
            let perViz = visibleCategories.filter { !$0.isGlobal }
            if !globals.isEmpty {
                Section {
                    ForEach(globals) { navRow($0) }
                } header: {
                    sectionHeader("Global")
                }
            }
            if !perViz.isEmpty {
                Section {
                    ForEach(perViz) { navRow($0) }
                } header: {
                    sectionHeader(model.settings.visualizerStyle.displayName)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
    }

    /// App logo + version pinned at the bottom of the sidebar.
    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacVisualizer")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Section header: a touch larger than the rows and in the primary color,
    /// so the Global / <style> groupings read as the dominant structure.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3).fontWeight(.semibold)
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    /// A sidebar row (hover-highlighted, selected-filled). The Styles & Presets
    /// row carries a count of disabled styles, so a style that drops out of the
    /// picker is still visibly recoverable there.
    private func navRow(_ cat: SettingsCategory) -> some View {
        SidebarRow(
            cat: cat,
            title: label(for: cat),
            badge: cat == .styles && !disabledStyles.isEmpty ? disabledStyles.count : nil,
            shortcut: shortcut(for: cat),
            selected: (selection ?? .styleControls) == cat
        ) { selection = cat }
        .listRowBackground(Color.clear)
    }

    /// The ⌘-number that jumps to this category (⌘1…⌘9, ⌘0 for the 10th), or nil
    /// past the first ten visible rows. Mirrors the `.onKeyPress` handler.
    private func shortcut(for cat: SettingsCategory) -> String? {
        guard let idx = visibleCategories.firstIndex(of: cat), idx < 10 else { return nil }
        return "⌘\((idx + 1) % 10)"
    }

    /// Categories shown in the sidebar: Position only for styles that support
    /// a position offset, and everything narrowed by the filter text.
    private var visibleCategories: [SettingsCategory] {
        var cats = SettingsCategory.allOrdered
        let q = filter.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            cats = cats.filter { label(for: $0).localizedCaseInsensitiveContains(q) }
        }
        return cats
    }

    private func label(for cat: SettingsCategory) -> String { cat.title }

    // MARK: - Detail

    private var detail: some View {
        Form {
            detailSections
        }
        .formStyle(.grouped)
        .navigationTitle(label(for: selection ?? .styleControls))
    }

    @ViewBuilder private var detailSections: some View {
        switch selection ?? .styleControls {
        case .styles:       stylesCategory
        case .paletteCycle: paletteCycleCategory
        case .postFX:       postFXCategory
        case .analysis:     analysisCategory
        case .trackOverlay: trackOverlayCategory
        case .lyrics:
            LyricsSettingsSection(settings: $model.settings.lyrics,
                                  model: model,
                                  lyrics: lyrics,
                                  keyStore: GeminiKeyStore(fileURL: GeminiKeyStore.defaultFileURL()))
        case .layout:       layoutCategory
        case .window:       windowCategory
        case .appearance:   appearanceCategory
        case .glow:         glowCategory
        case .bands:        bandsCategory
        case .styleControls:
            styleResetSection
            Section("\(model.settings.visualizerStyle.displayName) Controls") {
                styleEnabledToggle
                styleFrameRatePicker
                controls(for: model.settings.visualizerStyle)
            }
            if model.settings.visualizerStyle == .spinner {
                SpinnerSettingsSections(model: model)
            }
        }
    }

    /// Whole-style reset, a second entry point to the actions in "Styles & Presets".
    @ViewBuilder private var styleResetSection: some View {
        let name = model.settings.visualizerStyle.displayName
        let atBaseline = !model.baseline.currentStyleDiffersFromBaseline(model.settings)
        let atFactory = !model.baseline.currentStyleDiffersFromFactory(model.settings)
        Section {
            Button("Save \(name) settings as my defaults") { model.saveCurrentStyleAsUserDefaults() }
                .disabled(atBaseline)
                .help(atBaseline
                      ? "\(name) already matches \(baselineTargetName); nothing to save."
                      : "Saves only \(name). Other visualizations and app-wide settings in your saved defaults are unchanged.")
            Button("Reset all \(name) settings…") { confirmResetThisStyle = true }
                .disabled(atBaseline)
                .help(atBaseline ? "\(name) is already at \(baselineTargetName)." : "Also resets tunables used only by \(name). App-wide settings and other styles are unchanged.")
            Button("Reset all \(name) settings to Factory…") { confirmResetThisStyleFactory = true }
                .disabled(!model.baseline.hasUserDefaults || atFactory)
                .help(!model.baseline.hasUserDefaults
                      ? "No saved defaults, so the button above already resets to factory."
                      : (atFactory ? "\(name) is already at factory defaults." : ""))
            Text("Save or reset this style across Controls, Appearance, Glow and Bands. Undo a reset with ⌘Z.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Global categories

    @ViewBuilder private var stylesCategory: some View {
        Section("My Defaults") {
            if model.baseline.hasUserDefaults {
                if let saved = model.baseline.savedAt {
                    Text("Saved \(saved.formatted(date: .abbreviated, time: .shortened)). Reset buttons restore these values.")
                } else {
                    Text("Saved. Reset buttons restore these values.")
                }
            } else {
                Text("None saved. Reset buttons restore factory defaults.")
            }
            Button("Save Current Settings as My Defaults") { model.saveCurrentAsUserDefaults() }
            Button("Clear My Defaults…") { UserDefaultsPrompts.confirmClear(model) }
                .disabled(!model.baseline.hasUserDefaults)
            Text("A ↺ button appears next to any control that differs from its default. Click it to restore your saved default (factory if none saved); Option-click for the factory default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Reset") {
            Button("Reset \(model.settings.visualizerStyle.displayName) to \(model.baseline.hasUserDefaults ? "My Defaults" : "Defaults")…") {
                confirmResetThisStyle = true
            }
            Button("Reset \(model.settings.visualizerStyle.displayName) to Factory…") {
                confirmResetThisStyleFactory = true
            }
            .disabled(!model.baseline.hasUserDefaults)
            .help(model.baseline.hasUserDefaults ? "" : "No saved defaults, so the button above already resets to factory.")
            Button("Reset All Styles to \(model.baseline.hasUserDefaults ? "My Defaults" : "Defaults")…", role: .destructive) {
                confirmResetAllStyles = true
            }
            Button("Reset All Styles to Factory…", role: .destructive) { confirmResetAllFactory = true }
                .disabled(!model.baseline.hasUserDefaults)
                .help(model.baseline.hasUserDefaults ? "" : "No saved defaults, so the button above already resets to factory.")
        }
        if disabledStyles.isEmpty {
            Section { Text("All styles are enabled.").foregroundStyle(.secondary) }
        } else {
            Section("Disabled Styles") {
                ForEach(disabledStyles, id: \.self) { style in
                    HStack {
                        Text(style.displayName)
                        Spacer()
                        Button("Enable") { model.settings.setStyleEnabled(style, true) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var paletteCycleCategory: some View {
        Section("Palette Cycle") {
            Toggle("Auto-cycle palettes", isOn: $model.settings.paletteCycleEnabled)
                .resettable(\.paletteCycleEnabled, model)
            if model.settings.paletteCycleEnabled {
                Slider(value: $model.settings.paletteCycleInterval, in: 5...600) {
                    Text("Interval: \(Int(model.settings.paletteCycleInterval))s")
                } minimumValueLabel: { Text("5s") } maximumValueLabel: { Text("600s") }
                    .resettable(\.paletteCycleInterval, model)
                Slider(value: $model.settings.paletteCycleFadeDuration, in: 0.1...10) {
                    Text(String(format: "Fade: %.1fs", model.settings.paletteCycleFadeDuration))
                } minimumValueLabel: { Text("0.1s") } maximumValueLabel: { Text("10s") }
                    .resettable(\.paletteCycleFadeDuration, model)
            }
        }
    }

    @ViewBuilder private var postFXCategory: some View {
        Section("Post-FX") {
            Slider(value: $model.settings.trailPersistence, in: 0...0.97) {
                Text("Trails")
            } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Long") }
                .resettable(\.trailPersistence, model)
            Slider(value: $model.settings.vignetteAmount, in: 0...1) {
                Text("Vignette")
            } minimumValueLabel: { Text("Off") } maximumValueLabel: { Text("Heavy") }
                .resettable(\.vignetteAmount, model)
            Slider(value: $model.settings.outputBrightness, in: 0.05...1.0) {
                Text("Brightness (dimmer)")
            } minimumValueLabel: { Text("Dim") } maximumValueLabel: { Text("Full") }
                .resettable(\.outputBrightness, model)
            Stepper(model.settings.kaleidoscopeFolds == 0
                    ? "Kaleidoscope: Off"
                    : "Kaleidoscope: \(model.settings.kaleidoscopeFolds)-fold",
                    value: $model.settings.kaleidoscopeFolds, in: 0...12)
                .resettable(\.kaleidoscopeFolds, model)
        }
    }

    @ViewBuilder private var analysisCategory: some View {
        Section("Analysis") {
            Picker("FFT window", selection: $model.settings.fftWindow) {
                ForEach(FFTWindow.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .disabled(!activeStyle.usesFrequencyBands)
            .help(activeStyle.usesFrequencyBands ? "App-wide FFT analysis window."
                  : "No effect on \(activeStyle.displayName) (it doesn't read the frequency bands). Applies to band-reading styles.")
                .resettable(\.fftWindow, model)
            Toggle("Use stereo image", isOn: $model.settings.useStereoImage)
                .disabled(!activeStyle.usesStereoImage)
                .help(activeStyle.usesStereoImage
                      ? "Splits left/right channels for the stereo-aware styles."
                      : "No effect on \(activeStyle.displayName). Applies to Bars, Radial, Ribbon Wave, Joy Plot, Heightfield, Voronoi, Lava Lamp and Iris.")
                .resettable(\.useStereoImage, model)
            if !activeStyle.usesFrequencyBands || !activeStyle.usesStereoImage {
                Text("These are app-wide — dimmed here only because \(activeStyle.displayName) ignores them. Switch to a style that uses them to edit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var trackOverlayCategory: some View {
        Section("Track Overlay") {
            Toggle("Show overlay", isOn: $model.settings.overlayEnabled)
                .resettable(\.overlayEnabled, model)
            Picker("Position", selection: $model.settings.overlayPosition) {
                Text("Top Left").tag(OverlayCorner.topLeading)
                Text("Top Right").tag(OverlayCorner.topTrailing)
                Text("Bottom Left").tag(OverlayCorner.bottomLeading)
                Text("Bottom Right").tag(OverlayCorner.bottomTrailing)
            }
                .resettable(\.overlayPosition, model)
            Slider(value: $model.settings.overlayOpacity, in: 0.2...1) {
                Text("Opacity")
            } minimumValueLabel: { Text("20%") } maximumValueLabel: { Text("100%") }
                .resettable(\.overlayOpacity, model)
            Text("Shows the current track's title and artist. App-wide — the same for every visualization.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var layoutCategory: some View {
        Section("Layout") {
            Toggle("Center below lyrics", isOn: $model.settings.centerBelowLyrics)
                .help("When lyrics are on screen, center the visualization in the clear space below the lowest line instead of the whole window. Applies to all centered styles. The position offset below is added on top.")
                .resettable(\.centerBelowLyrics, model)
            Text("App-wide. Lyric position, lines visible and text size (Lyrics settings) also move the visualization.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Position: \(model.settings.visualizerStyle.displayName) only") {
            Slider(value: $model.settings.positionOffsetX, in: -1...1) {
                Text(String(format: "Horizontal: %.2f", model.settings.positionOffsetX))
            } minimumValueLabel: { Text("Left") } maximumValueLabel: { Text("Right") }
                .resettable(profile: \.positionOffsetX, model, fanOut: false)
            Slider(value: $model.settings.positionOffsetY, in: -1...1) {
                Text(String(format: "Vertical: %.2f", model.settings.positionOffsetY))
            } minimumValueLabel: { Text("Down") } maximumValueLabel: { Text("Up") }
                .resettable(profile: \.positionOffsetY, model, fanOut: false)
            Button("Center") {
                model.settings.positionOffsetX = 0
                model.settings.positionOffsetY = 0
            }
            .disabled(model.settings.positionOffsetX == 0 && model.settings.positionOffsetY == 0)
            Text(styleSupportsPositionOffset
                 ? "Moves the current visualization, \(model.settings.visualizerStyle.displayName), within the window. Each visualization remembers its own position; the other styles are not affected. Center and the style's Reset restore its default."
                 : "Moves centered visualizations within the window. The active style, \(model.settings.visualizerStyle.displayName), fills the window, so it isn't affected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var windowCategory: some View {
        Section("Window") {
            Toggle("Always on top", isOn: $model.settings.alwaysOnTop)
                .resettable(\.alwaysOnTop, model)
            Picker("Frame rate", selection: $model.settings.targetFPS) {
                ForEach(fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
            }
                .resettable(\.targetFPS, model)
            Picker("Transparency", selection: $model.settings.windowTransparencyMode) {
                Text("Opaque").tag(WindowTransparencyMode.opaque)
                Text("Window Opacity").tag(WindowTransparencyMode.windowOpacity)
                Text("Per-Pixel Alpha").tag(WindowTransparencyMode.perPixelAlpha)
            }
                .resettable(\.windowTransparencyMode, model)
            if model.settings.windowTransparencyMode != .opaque {
                VStack(alignment: .leading) {
                    Text("Opacity: \(Int(model.settings.windowOpacity * 100))%")
                    Slider(value: $model.settings.windowOpacity,
                           in: model.settings.windowTransparencyMode == .perPixelAlpha
                               ? 0.05...1.0 : 0.2...1.0)
                        .resettable(\.windowOpacity, model)
                    if model.settings.windowTransparencyMode == .perPixelAlpha {
                        Text("Scales the whole per-pixel-alpha result, so low values give a very subtle ghost of the visualizer over your desktop.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Picker("Mouse control modifier", selection: $model.settings.mouseControlModifier) {
                Text("Off").tag(MouseControlModifier.off)
                Text("Shift").tag(MouseControlModifier.shift)
                Text("Option").tag(MouseControlModifier.option)
                Text("Command").tag(MouseControlModifier.command)
            }
            .help("Holding this key turns mouse actions into visualizer controls. Off disables only this; the keyboard shortcuts, right-click menu and double-click full screen stay.")
                .resettable(\.mouseControlModifier, model)
            Text("Hold the modifier: click = previous visualization, right-click = next, middle-click = random, scroll = change palette (down = next). With the Spinner active, Option+drag always rotates the disc; with Option as the modifier, a press that never moves still counts as the click. Press ? in the visualizer window for all shortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Click-through (mouse events pass through to apps below)",
                   isOn: $model.settings.clickThroughEnabled)
                .resettable(\.clickThroughEnabled, model)
            Toggle("Borderless window (hide title bar + buttons)",
                   isOn: $model.settings.borderlessWindow)
                .help("Drag the window by clicking and dragging anywhere on its surface. Close via ⌘W or quit via ⌘Q.")
                .resettable(\.borderlessWindow, model)
            Picker("Window border", selection: $model.settings.windowBorderMode) {
                Text("Off").tag(WindowBorderMode.off)
                Text("Auto (fade when idle)").tag(WindowBorderMode.auto)
                Text("Always on").tag(WindowBorderMode.always)
            }
            .help("Off: never shown. Auto: appears, with the window shadow, when you click in the window or resize it, then fades out when idle — so you can see the resize edge on demand without a permanent frame. Moving the pointer or switching back to the app does not reveal it. Always on: a permanent outline. Works in both normal and borderless mode.")
                .resettable(\.windowBorderMode, model)
            Group {
                ColorPicker("Border color",
                            selection: windowColorBinding(\.windowBorderColor),
                            supportsOpacity: false)
                    .resettable(\.windowBorderColor, model)
                Slider(value: $model.settings.windowBorderOpacity, in: 0...1) {
                    Text("Border opacity: \(Int((model.settings.windowBorderOpacity * 100).rounded()))%")
                } minimumValueLabel: { Text("0%") } maximumValueLabel: { Text("100%") }
                    .resettable(\.windowBorderOpacity, model)
                Slider(value: $model.settings.windowBorderWidth, in: 0.5...8) {
                    Text(String(format: "Border width: %.1f pt", model.settings.windowBorderWidth))
                } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("8") }
                    .resettable(\.windowBorderWidth, model)
            }
            .disabled(model.settings.windowBorderMode == .off)
        }
    }

    // MARK: - Per-visualization categories

    /// The style being edited (controls disable against its capability flags).
    private var activeStyle: VisualizerStyle { model.settings.visualizerStyle }

    @ViewBuilder private var appearanceCategory: some View {
        Section("Appearance") {
            Picker("Color palette", selection: bind(\.paletteName)) {
                ForEach(palettes, id: \.self) { Text($0.capitalized).tag($0) }
            }
                .disabled(!activeStyle.usesPalette)
                .help(activeStyle.usesPalette ? ""
                      : "\(activeStyle.displayName)'s colours come from its metal, so Palette has no effect on RealityKit and only a faint tint on the classic shader.")
                .resettable(profile: \.paletteName, model)
            Slider(value: bind(\.gain), in: 0.5...4) {
                Text("Gain")
            } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("4") }
                .disabled(!activeStyle.usesFrequencyBands)
                .help(activeStyle.usesFrequencyBands ? ""
                      : "\(activeStyle.displayName) reacts to raw loudness or the waveform, so Gain has no effect.")
                .resettable(profile: \.gain, model)
            Toggle("Peak-hold caps", isOn: bind(\.peakHoldEnabled))
                .disabled(!activeStyle.usesPeakHold)
                .help(activeStyle.usesPeakHold ? "" : "Only Bars draws peak-hold caps.")
                .resettable(profile: \.peakHoldEnabled, model)
        }
    }

    @ViewBuilder private var glowCategory: some View {
        Section("Glow") {
            Toggle("Enable glow", isOn: bind(\.glowEnabled))
                .resettable(profile: \.glowEnabled, model)
            Slider(value: bind(\.glowIntensity), in: 0...1.5) {
                Text("Glow intensity")
            } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1.5") }
                .resettable(profile: \.glowIntensity, model)
        }
    }

    @ViewBuilder private var bandsCategory: some View {
        Section("Bands") {
            Stepper("Bars: \(model.settings.barCount)",
                    value: bind(\.barCount), in: 16...96, step: 4)
                .disabled(!activeStyle.usesBarCount)
                .help(barsHelp)
                .resettable(profile: \.barCount, model)
            Slider(value: bind(\.smoothing), in: 0...0.95) {
                Text("Smoothing")
            } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.95") }
                .disabled(!activeStyle.usesFrequencyBands)
                .help(activeStyle.usesFrequencyBands ? ""
                      : "\(activeStyle.displayName) doesn't read the frequency bands, so Smoothing has no effect.")
                .resettable(profile: \.smoothing, model)
        }
    }

    private var barsHelp: String {
        if activeStyle.usesBarCount { return "" }
        if activeStyle == .musicalSpectrum {
            return "Musical Spectrum sets its band count from its note range (octaves × 12), so Bars has no effect."
        }
        return "\(activeStyle.displayName) doesn't read the frequency bands, so Bars has no effect."
    }

    // MARK: - Per-style enable/disable

    /// True when the active style is the only enabled one; the Enabled toggle
    /// greys out so the enabled set can never go empty from the UI.
    private var isLastEnabledStyle: Bool {
        model.settings.enabledStyles == [model.settings.visualizerStyle]
    }

    private var disabledStyles: [VisualizerStyle] {
        VisualizerStyle.availableCases.filter { !model.settings.isStyleEnabled($0) }  // unavailable styles are not listed
    }

    /// Disabling the active style immediately switches to the effective
    /// (first enabled) style — the picker, ⌘]/⌘[ cycling, and this Controls
    /// section all follow. Re-enable from the Disabled Styles section.
    private var styleEnabledToggle: some View {
        Toggle("Enabled", isOn: Binding(
            get: { model.settings.isStyleEnabled(model.settings.visualizerStyle) },
            set: { newValue in
                let style = model.settings.visualizerStyle
                if !newValue && model.settings.enabledStyles == [style] { return }
                model.settings.setStyleEnabled(style, newValue)
                if !newValue {
                    model.settings.visualizerStyle = model.settings.effectiveStyle
                }
            }))
            .disabled(isLastEnabledStyle)
            .help("Disabled styles are hidden from the style picker and skipped by ⌘]/⌘[ cycling. Re-enable them from the Disabled Styles section at the bottom.")
    }

    // MARK: - Dynamic per-style controls

    /// Renders only the active style's style-specific knobs. Styles with no
    /// style-specific controls fall through to a quiet placeholder row.
    @ViewBuilder
    private func controls(for style: VisualizerStyle) -> some View {
        switch style {
        case .bars, .mirrored:
            Slider(value: $model.settings.barGap, in: 0...0.5) {
                Text("Bar gap")
            } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
                .resettable(\.barGap, model)

        case .oscilloscope:
            Slider(value: $model.settings.oscilloscopeThickness, in: 0.5...3.0) {
                Text("Line thickness")
            } minimumValueLabel: { Text("0.5×") } maximumValueLabel: { Text("3×") }
                .resettable(\.oscilloscopeThickness, model)

        case .particles:
            particleSharedControls
            particlesControls

        case .fireworks:
            particleSharedControls
            fireworksControls

        case .fountain:
            particleSharedControls
            fountainControls

        case .ribbonWave:
            Stepper("Wave count: \(model.settings.ribbonWaveCount)",
                    value: $model.settings.ribbonWaveCount, in: 1...6)
                .resettable(\.ribbonWaveCount, model)
            Slider(value: $model.settings.ribbonTiltSpacing, in: 0...0.4) {
                Text("Tilt spacing")
            } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.4") }
                .resettable(\.ribbonTiltSpacing, model)
            Slider(value: $model.settings.ribbonDepthFalloff, in: 0...0.5) {
                Text("Depth falloff")
            } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
                .resettable(\.ribbonDepthFalloff, model)
            ribbonWaveControls

        case .voronoi:
            Picker("Render mode", selection: bind(\.voronoiRenderMode)) {
                Text("Cells").tag(VoronoiRenderMode.cells)
                Text("Blobs").tag(VoronoiRenderMode.blobs)
                Text("Soft Cells").tag(VoronoiRenderMode.softCells)
            }
                .resettable(profile: \.voronoiRenderMode, model)
            Picker("Shape mode", selection: bind(\.voronoiShapeMode)) {
                Text("Fixed").tag(VoronoiShapeMode.fixed)
                Text("Cycle").tag(VoronoiShapeMode.cycle)
                Text("Drift").tag(VoronoiShapeMode.drift)
                Text("Per Track").tag(VoronoiShapeMode.perTrack)
            }
                .resettable(profile: \.voronoiShapeMode, model)
            voronoiControls

        case .heightfield:
            Picker("Render mode", selection: bind(\.heightfieldRenderMode)) {
                Text("Wireframe").tag(HeightfieldRenderMode.wireframe)
                Text("Solid").tag(HeightfieldRenderMode.solid)
            }
                .resettable(profile: \.heightfieldRenderMode, model)
            heightfieldControls

        case .lavaLamp:
            Picker("Render mode", selection: bind(\.lavaLampRenderMode)) {
                Text("Shader").tag(LavaLampRenderMode.shader)
                Text("Marching Squares").tag(LavaLampRenderMode.marchingSquares)
            }
                .resettable(profile: \.lavaLampRenderMode, model)
            lavaLampControls

        case .polartone:
            polartoneControls

        case .starNest:
            starNestControls

        case .wireframe:
            wireframeControls

        case .outrunRain:
            outrunRainControls

        case .octaveMeatballs:
            octaveMeatballsControls

        case .joyPlot:
            joyPlotControls

        case .plasma:
            plasmaControls

        case .bumpscope:
            bumpscopeControls

        case .xyScope:
            xyScopeControls

        case .iris:
            irisControls

        case .tricentric:
            tricentricControls

        case .musicalSpectrum:
            musicalSpectrumControls

        default:
            Text("No style-specific controls for this visualizer.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Polartone's full simple-scalar control set. `oscilloscopeThickness` is a
    /// single shared top-level field (also surfaced under Oscilloscope); it is
    /// shown here too because Polartone multiplies its line width by it.
    @ViewBuilder
    private var polartoneControls: some View {
        Picker("Mode", selection: $model.settings.polartoneRenderMode) {
            Text("Ring").tag(PolartoneRenderMode.ring)
            Text("Spiral").tag(PolartoneRenderMode.spiral)
        }
            .resettable(\.polartoneRenderMode, model)
        if model.settings.polartoneRenderMode == .spiral {
            Slider(value: $model.settings.polartoneInnerThreshold, in: 0.0...0.4) {
                Text("Inner threshold")
            } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.4") }
                .resettable(\.polartoneInnerThreshold, model)
            Slider(value: $model.settings.polartoneDriftRevolutions, in: 1...40) {
                Text("Drift (revolutions/sweep)")
            } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("40") }
                .resettable(\.polartoneDriftRevolutions, model)
            Picker("Start direction", selection: $model.settings.polartoneStartDirection) {
                Text("Inward").tag(PolartoneStartDirection.inward)
                Text("Outward").tag(PolartoneStartDirection.outward)
            }
                .resettable(\.polartoneStartDirection, model)
        }
        Slider(value: $model.settings.polartoneRadius, in: 0.1...0.9) {
            Text(model.settings.polartoneRenderMode == .spiral ? "Outer radius" : "Radius")
        } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("0.9") }
            .resettable(\.polartoneRadius, model)
        Slider(value: $model.settings.polartoneAmplitude, in: 0.0...0.6) {
            Text("Amplitude")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.6") }
            .resettable(\.polartoneAmplitude, model)
        Slider(value: $model.settings.polartoneColorFloor, in: 0...0.5) {
            Text("Color floor")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.polartoneColorFloor, model)
        Slider(value: $model.settings.polartoneRotationSpeed, in: -2...2) {
            Text("Rotation speed")
        } minimumValueLabel: { Text("-2") } maximumValueLabel: { Text("2") }
            .resettable(\.polartoneRotationSpeed, model)
        Stepper("Point count: \(model.settings.polartonePointCount)",
                value: $model.settings.polartonePointCount, in: 64...1024, step: 64)
            .resettable(\.polartonePointCount, model)
        Slider(value: $model.settings.polartonePhaseOffset, in: -.pi ... .pi) {
            Text("Phase offset")
        } minimumValueLabel: { Text("-π") } maximumValueLabel: { Text("π") }
            .resettable(\.polartonePhaseOffset, model)
        Slider(value: $model.settings.polartoneLineHalfThickness, in: 0.001...0.02) {
            Text("Line thickness")
        } minimumValueLabel: { Text("Thin") } maximumValueLabel: { Text("Thick") }
            .resettable(\.polartoneLineHalfThickness, model)
        Slider(value: $model.settings.polartoneWaveformClamp, in: 0.25...2) {
            Text("Waveform clamp")
        } minimumValueLabel: { Text("0.25") } maximumValueLabel: { Text("2") }
            .resettable(\.polartoneWaveformClamp, model)
        Slider(value: $model.settings.oscilloscopeThickness, in: 0.5...3.0) {
            Text("Line width ×")
        } minimumValueLabel: { Text("0.5×") } maximumValueLabel: { Text("3×") }
            .resettable(\.oscilloscopeThickness, model)
    }

    /// XY Scope knobs. Rotation 45° is the goniometer convention (mono reads
    /// as a vertical line); 0° is the raw Lissajous convention (L on x, R on
    /// y). Phosphor-style persistence comes from the shared Trails setting.
    @ViewBuilder
    private var xyScopeControls: some View {
        Slider(value: $model.settings.xyScopeGain, in: 0.1...4.0) {
            Text("Gain")
        } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("4") }
            .resettable(\.xyScopeGain, model)
        Slider(value: $model.settings.xyScopeRotationDegrees, in: 0...90) {
            Text("Rotation (45° = goniometer)")
        } minimumValueLabel: { Text("0°") } maximumValueLabel: { Text("90°") }
            .resettable(\.xyScopeRotationDegrees, model)
        Stepper("Trace points: \(model.settings.xyScopeSampleCount)",
                value: $model.settings.xyScopeSampleCount, in: 32...256, step: 32)
            .resettable(\.xyScopeSampleCount, model)
        Slider(value: $model.settings.xyScopeLineHalfThickness, in: 0.001...0.02) {
            Text("Line thickness")
        } minimumValueLabel: { Text("Thin") } maximumValueLabel: { Text("Thick") }
            .resettable(\.xyScopeLineHalfThickness, model)
        Slider(value: $model.settings.xyScopeColorFloor, in: 0...0.5) {
            Text("Color floor")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.xyScopeColorFloor, model)
        Slider(value: $model.settings.xyScopeBeatBoost, in: 0...1.5) {
            Text("Beat boost")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1.5") }
            .resettable(\.xyScopeBeatBoost, model)
        Slider(value: $model.settings.xyScopeBeatHalfLife, in: 0.05...0.6) {
            Text("Beat decay (s)")
        } minimumValueLabel: { Text("0.05") } maximumValueLabel: { Text("0.6") }
            .resettable(\.xyScopeBeatHalfLife, model)
        Slider(value: $model.settings.xyScopeAlpha, in: 0.1...1.0) {
            Text("Opacity")
        } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("1") }
            .resettable(\.xyScopeAlpha, model)
    }

    /// Musical Spectrum knobs. Octave range reconfigures the analyzer's
    /// note-aligned band mapping; the rest are display knobs.
    @ViewBuilder
    private var musicalSpectrumControls: some View {
        Stepper("Start octave: C\(model.settings.musicalStartOctave)",
                value: $model.settings.musicalStartOctave, in: 0...5)
            .resettable(\.musicalStartOctave, model)
        Stepper("Octaves: \(model.settings.musicalOctaveCount)",
                value: $model.settings.musicalOctaveCount, in: 1...8)
            .resettable(\.musicalOctaveCount, model)
        Slider(value: $model.settings.musicalBarGap, in: 0...0.9) {
            Text("Bar gap")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.9") }
            .resettable(\.musicalBarGap, model)
        Slider(value: $model.settings.musicalOctaveGap, in: 0...2) {
            Text("Octave gap")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.musicalOctaveGap, model)
        Toggle("Color by pitch class (same note = same color)",
               isOn: $model.settings.musicalPitchClassColoring)
            .resettable(\.musicalPitchClassColoring, model)
        Slider(value: $model.settings.musicalColorFloor, in: 0...0.6) {
            Text("Quiet-bar floor")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.6") }
            .resettable(\.musicalColorFloor, model)
        Slider(value: $model.settings.musicalAlpha, in: 0.1...1.0) {
            Text("Opacity")
        } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("1") }
            .resettable(\.musicalAlpha, model)
        Text("Low octaves smear together below the FFT's semitone resolution — start at C2 or higher for the cleanest alignment.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Iris knobs (Vissonance port — see NOTICE).
    @ViewBuilder
    private var irisControls: some View {
        Stepper("Petals: \(model.settings.irisPetalCount)",
                value: $model.settings.irisPetalCount, in: 8...256, step: 8)
            .resettable(\.irisPetalCount, model)
        Slider(value: $model.settings.irisInnerRadius, in: 0...0.6) {
            Text("Inner radius")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.6") }
            .resettable(\.irisInnerRadius, model)
        Slider(value: $model.settings.irisBaseLength, in: 0...0.5) {
            Text("Base length")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.irisBaseLength, model)
        Slider(value: $model.settings.irisLengthScale, in: 0...1.5) {
            Text("Audio response")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1.5") }
            .resettable(\.irisLengthScale, model)
        Slider(value: $model.settings.irisPetalWidth, in: 0.002...0.05) {
            Text("Petal width")
        } minimumValueLabel: { Text("Thin") } maximumValueLabel: { Text("Wide") }
            .resettable(\.irisPetalWidth, model)
        Slider(value: $model.settings.irisLoudnessSwell, in: 0...1) {
            Text("Loudness swell")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.irisLoudnessSwell, model)
        Slider(value: $model.settings.irisInnerDim, in: 0...1) {
            Text("Base dim")
        } minimumValueLabel: { Text("Dark") } maximumValueLabel: { Text("Full") }
            .resettable(\.irisInnerDim, model)
        Slider(value: $model.settings.irisAlpha, in: 0.1...1.0) {
            Text("Opacity")
        } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("1") }
            .resettable(\.irisAlpha, model)
    }

    /// Tricentric knobs (Vissonance port — see NOTICE).
    @ViewBuilder
    private var tricentricControls: some View {
        Stepper("Rings: \(model.settings.tricentricRingCount)",
                value: $model.settings.tricentricRingCount, in: 4...64, step: 4)
            .resettable(\.tricentricRingCount, model)
        Slider(value: $model.settings.tricentricBaseRadius, in: 0.3...1.2) {
            Text("Tunnel radius")
        } minimumValueLabel: { Text("0.3") } maximumValueLabel: { Text("1.2") }
            .resettable(\.tricentricBaseRadius, model)
        Slider(value: $model.settings.tricentricRadiusFalloff, in: 0.5...0.99) {
            Text("Depth falloff")
        } minimumValueLabel: { Text("Steep") } maximumValueLabel: { Text("Shallow") }
            .resettable(\.tricentricRadiusFalloff, model)
        Slider(value: $model.settings.tricentricScaleFloor, in: 0...1) {
            Text("Silence floor")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.tricentricScaleFloor, model)
        Slider(value: $model.settings.tricentricRotationSpeed, in: -6...6) {
            Text("Rotation speed")
        } minimumValueLabel: { Text("-6") } maximumValueLabel: { Text("6") }
            .resettable(\.tricentricRotationSpeed, model)
        Slider(value: $model.settings.tricentricLineThickness, in: 0.002...0.03) {
            Text("Line thickness")
        } minimumValueLabel: { Text("Thin") } maximumValueLabel: { Text("Thick") }
            .resettable(\.tricentricLineThickness, model)
        Slider(value: $model.settings.tricentricAlpha, in: 0.1...1.0) {
            Text("Opacity")
        } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("1") }
            .resettable(\.tricentricAlpha, model)
    }

    /// Star Nest's resting-value controls. Each slider sets the `base` the
    /// shader modulates with audio on top, so defaults reproduce today's look.
    /// The Density subgroup's two integer sliders raise GPU cost as they climb,
    /// hence the quiet "(performance)" caption.
    @ViewBuilder
    private var starNestControls: some View {
        Slider(value: $model.settings.starNestZoom, in: 0.3...2.0) {
            Text("Zoom")
        } minimumValueLabel: { Text("0.3") } maximumValueLabel: { Text("2.0") }
            .resettable(\.starNestZoom, model)
        Slider(value: $model.settings.starNestSpeed, in: 0.0...1.0) {
            Text("Speed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.starNestSpeed, model)
        Slider(value: $model.settings.starNestFormuparam, in: 0.4...0.7) {
            Text("Formuparam")
        } minimumValueLabel: { Text("0.4") } maximumValueLabel: { Text("0.7") }
            .resettable(\.starNestFormuparam, model)
        Slider(value: $model.settings.starNestTile, in: 0.5...1.2) {
            Text("Tile")
        } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("1.2") }
            .resettable(\.starNestTile, model)
        Slider(value: $model.settings.starNestStepsize, in: 0.02...0.3) {
            Text("Step size")
        } minimumValueLabel: { Text("0.02") } maximumValueLabel: { Text("0.3") }
            .resettable(\.starNestStepsize, model)
        Slider(value: $model.settings.starNestBrightness, in: 0.0002...0.003) {
            Text("Brightness")
        } minimumValueLabel: { Text("Dim") } maximumValueLabel: { Text("Bright") }
            .resettable(\.starNestBrightness, model)
        Slider(value: $model.settings.starNestDarkmatter, in: 0.0...1.0) {
            Text("Dark matter")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.starNestDarkmatter, model)
        Slider(value: $model.settings.starNestDistfading, in: 0.4...1.0) {
            Text("Distance fading")
        } minimumValueLabel: { Text("0.4") } maximumValueLabel: { Text("1") }
            .resettable(\.starNestDistfading, model)
        Slider(value: $model.settings.starNestSaturation, in: 0.0...1.0) {
            Text("Saturation")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.starNestSaturation, model)

        Text("Density (performance)")
            .font(.caption)
            .foregroundStyle(.secondary)
        Slider(
            value: Binding(
                get: { Double(model.settings.starNestVolsteps) },
                set: { model.settings.starNestVolsteps = Int($0.rounded()) }
            ),
            in: 1...26, step: 1
        ) {
            Text("Volume steps: \(model.settings.starNestVolsteps)")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("26") }
            .resettable(\.starNestVolsteps, model)
        Slider(
            value: Binding(
                get: { Double(model.settings.starNestIterations) },
                set: { model.settings.starNestIterations = Int($0.rounded()) }
            ),
            in: 1...16, step: 1
        ) {
            Text("Iterations: \(model.settings.starNestIterations)")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("16") }
            .resettable(\.starNestIterations, model)
    }

    /// Wireframe's tunables. The six scalars bind directly to the top-level
    /// `wireframe*` Double fields; defaults reproduce today's look. The Detail
    /// subgroup's subdivision level raises CPU cost per frame as it climbs
    /// (level 4 ≈ 16× the default edge count), hence the "(performance)" caption.
    @ViewBuilder
    private var wireframeControls: some View {
        Slider(value: $model.settings.wireframeBaseRadius, in: 0.2...1.0) {
            Text("Base radius")
        } minimumValueLabel: { Text("0.2") } maximumValueLabel: { Text("1.0") }
            .resettable(\.wireframeBaseRadius, model)
        Slider(value: $model.settings.wireframeDisplaceScale, in: 0.0...0.6) {
            Text("Audio displacement")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.6") }
            .resettable(\.wireframeDisplaceScale, model)
        Slider(value: $model.settings.wireframeLineThickness, in: 0.001...0.02) {
            Text("Line thickness")
        } minimumValueLabel: { Text("Thin") } maximumValueLabel: { Text("Thick") }
            .resettable(\.wireframeLineThickness, model)
        Slider(value: $model.settings.wireframeRotationSpeed, in: -2...2) {
            Text("Rotation speed")
        } minimumValueLabel: { Text("-2") } maximumValueLabel: { Text("2") }
            .resettable(\.wireframeRotationSpeed, model)
        Slider(value: $model.settings.wireframeTiltX, in: -.pi ... .pi) {
            Text("X tilt")
        } minimumValueLabel: { Text("-π") } maximumValueLabel: { Text("π") }
            .resettable(\.wireframeTiltX, model)
        Slider(value: $model.settings.wireframeLineOpacity, in: 0.0...1.0) {
            Text("Line opacity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.wireframeLineOpacity, model)

        Text("Placement")
            .font(.caption)
            .foregroundStyle(.secondary)
        Toggle("Auto-fill width", isOn: $model.settings.wireframeFillWidth)
            .help("Recomputes Width from the window's aspect ratio every frame, so the mesh keeps spanning the full width when you resize. Overrides the Width slider.")
            .resettable(\.wireframeFillWidth, model)
        Toggle("Anchor to bottom", isOn: $model.settings.wireframeAnchorBottom)
            .help("Pins the mesh to the bottom edge, recomputed as its height changes. Overrides the Vertical position slider.")
            .resettable(\.wireframeAnchorBottom, model)
        Slider(value: $model.settings.wireframeXExtent, in: 0.25...8.0) {
            Text("Width")
        } minimumValueLabel: { Text("0.25\u{00D7}") } maximumValueLabel: { Text("8\u{00D7}") }
            .disabled(model.settings.wireframeFillWidth)
            .resettable(\.wireframeXExtent, model)
        Slider(value: $model.settings.wireframeYExtent, in: 0.25...4.0) {
            Text("Height")
        } minimumValueLabel: { Text("0.25\u{00D7}") } maximumValueLabel: { Text("4\u{00D7}") }
            .resettable(\.wireframeYExtent, model)
        Slider(value: $model.settings.wireframeVerticalCenter, in: -1...1) {
            Text("Vertical position")
        } minimumValueLabel: { Text("Bottom") } maximumValueLabel: { Text("Top") }
            .disabled(model.settings.wireframeAnchorBottom)
            .resettable(\.wireframeVerticalCenter, model)
        Text(model.settings.wireframeFillWidth || model.settings.wireframeAnchorBottom
             ? "Auto-placement follows the window as you resize it. While Auto-fill width is on, Base radius no longer changes the width; Height still sets how tall the mesh is. Loud passages push slightly past the edges."
             : "Raise Width past 1\u{00D7} to fill a wide window (the sphere flattens into an ellipsoid); drop Vertical position to sit it on the bottom edge.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("Detail (performance)")
            .font(.caption)
            .foregroundStyle(.secondary)
        Slider(
            value: Binding(
                get: { Double(model.settings.wireframeSubdivisions) },
                set: { model.settings.wireframeSubdivisions = Int($0.rounded()) }
            ),
            in: 0...4, step: 1
        ) {
            Text("Subdivisions: \(model.settings.wireframeSubdivisions)")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.wireframeSubdivisions, model)
    }

    /// Outrun the Rain's full tunable set. Every slider sets either a resting
    /// "base" value or an audio-response coefficient the shader multiplies onto
    /// bass/lowMid/treble/energy; defaults reproduce today's look exactly. The
    /// 44 controls are split across labelled sub-sections (each its own
    /// `@ViewBuilder` var) so no single `ViewBuilder` block exceeds the 10-child
    /// limit and the list stays navigable.
    @ViewBuilder
    private var outrunRainControls: some View {
        outrunHorizonControls
        outrunMotionControls
        outrunLayer0Controls
        outrunLayer1Controls
        outrunLayer2Controls
        outrunSparkleControls
        outrunShapeColorControls
        outrunBrightnessReflectionControls
    }

    private func outrunSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Plasma's full tunable set, each a prior hardcoded literal in `plasma_fs`.
    /// Plasma reacts only to `time` (animation) and `energy` (brightness lift);
    /// it reads no bands. Defaults reproduce today's look exactly, so the style
    /// is identical until a slider moves. The 15 controls are split across three
    /// labelled sub-sections (each its own `@ViewBuilder` var) so no single
    /// `ViewBuilder` block exceeds the ~10-child limit.
    @ViewBuilder
    private var plasmaControls: some View {
        plasmaPatternControls
        plasmaAnimationControls
        plasmaColorControls
    }

    private func plasmaSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var plasmaPatternControls: some View {
        plasmaSectionHeader("Pattern")
        Slider(value: $model.settings.plasmaCoordinateScale, in: 0.5...6) {
            Text("Coordinate scale (zoom)")
        } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("6") }
            .resettable(\.plasmaCoordinateScale, model)
        Slider(value: $model.settings.plasmaCoordinateOffset, in: 0...2) {
            Text("Coordinate offset")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.plasmaCoordinateOffset, model)
        Slider(value: $model.settings.plasmaXFrequency, in: 0...32) {
            Text("X frequency")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("32") }
            .resettable(\.plasmaXFrequency, model)
        Slider(value: $model.settings.plasmaYFrequency, in: 0...32) {
            Text("Y frequency")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("32") }
            .resettable(\.plasmaYFrequency, model)
        Slider(value: $model.settings.plasmaDiagonalFrequency, in: 0...32) {
            Text("Diagonal frequency")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("32") }
            .resettable(\.plasmaDiagonalFrequency, model)
    }

    @ViewBuilder
    private var plasmaAnimationControls: some View {
        plasmaSectionHeader("Animation")
        Slider(value: $model.settings.plasmaXTimeScale, in: 0...4) {
            Text("X time scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.plasmaXTimeScale, model)
        Slider(value: $model.settings.plasmaYTimeScale, in: 0...4) {
            Text("Y time scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.plasmaYTimeScale, model)
        Slider(value: $model.settings.plasmaDiagonalTimeScale, in: 0...4) {
            Text("Diagonal time scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.plasmaDiagonalTimeScale, model)
    }

    @ViewBuilder
    private var plasmaColorControls: some View {
        plasmaSectionHeader("Color")
        Slider(value: $model.settings.plasmaWaveDivisor, in: 0.5...6) {
            Text("Wave divisor")
        } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("6") }
            .resettable(\.plasmaWaveDivisor, model)
        Slider(value: $model.settings.plasmaContrast, in: 0...2) {
            Text("Contrast")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.plasmaContrast, model)
        Slider(value: $model.settings.plasmaBrightnessBias, in: 0...1) {
            Text("Brightness bias")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.plasmaBrightnessBias, model)
        Slider(value: $model.settings.plasmaEnergyResponse, in: 0...2) {
            Text("Energy response")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.plasmaEnergyResponse, model)
        Slider(value: $model.settings.plasmaClampMin, in: 0...1) {
            Text("Clamp min")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.plasmaClampMin, model)
        Slider(value: $model.settings.plasmaClampMax, in: 0...1) {
            Text("Clamp max")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.plasmaClampMax, model)
        Slider(value: $model.settings.plasmaAlpha, in: 0...1) {
            Text("Alpha")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.plasmaAlpha, model)
    }

    // MARK: - Bumpscope controls

    /// Bumpscope reacts only to `bands` (a per-frequency embossed terrain); it
    /// reads no time/energy. Defaults reproduce today's look exactly, so the
    /// style is identical until a slider moves. The 15 controls are split across
    /// three labelled sub-sections (each its own `@ViewBuilder` var) so no single
    /// `ViewBuilder` block exceeds the ~10-child limit.
    @ViewBuilder
    private var bumpscopeControls: some View {
        bumpscopeBumpControls
        bumpscopeLightingControls
        bumpscopeColorControls
    }

    private func bumpscopeSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var bumpscopeBumpControls: some View {
        bumpscopeSectionHeader("Bump")
        Stepper("Neighbor radius: \(model.settings.bumpscopeNeighborRadius)",
                value: $model.settings.bumpscopeNeighborRadius, in: 0...15)
            .resettable(\.bumpscopeNeighborRadius, model)
        Slider(value: $model.settings.bumpscopeSlopeScale, in: 0...3) {
            Text("Slope scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.bumpscopeSlopeScale, model)
        Slider(value: $model.settings.bumpscopeSurfaceNormalY, in: 0.1...4) {
            Text("Surface normal Y")
        } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("4") }
            .resettable(\.bumpscopeSurfaceNormalY, model)
        Slider(value: $model.settings.bumpscopeSurfaceNormalZ, in: -2...2) {
            Text("Surface normal Z")
        } minimumValueLabel: { Text("-2") } maximumValueLabel: { Text("2") }
            .resettable(\.bumpscopeSurfaceNormalZ, model)
        Slider(value: $model.settings.bumpscopeUvClampMin, in: 0...1) {
            Text("UV clamp min")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeUvClampMin, model)
        Slider(value: $model.settings.bumpscopeUvClampMax, in: 0...1) {
            Text("UV clamp max")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeUvClampMax, model)
    }

    @ViewBuilder
    private var bumpscopeLightingControls: some View {
        bumpscopeSectionHeader("Lighting")
        Slider(value: $model.settings.bumpscopeLightX, in: -1...1) {
            Text("Light X")
        } minimumValueLabel: { Text("-1") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeLightX, model)
        Slider(value: $model.settings.bumpscopeLightY, in: -1...1) {
            Text("Light Y")
        } minimumValueLabel: { Text("-1") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeLightY, model)
        Slider(value: $model.settings.bumpscopeLightZ, in: -1...1) {
            Text("Light Z")
        } minimumValueLabel: { Text("-1") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeLightZ, model)
        Slider(value: $model.settings.bumpscopeDiffuseFloor, in: 0...1) {
            Text("Diffuse floor")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeDiffuseFloor, model)
    }

    @ViewBuilder
    private var bumpscopeColorControls: some View {
        bumpscopeSectionHeader("Color & Audio")
        Slider(value: $model.settings.bumpscopeBandGain, in: 0...6) {
            Text("Band gain")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("6") }
            .resettable(\.bumpscopeBandGain, model)
        Slider(value: $model.settings.bumpscopeIntensityBias, in: 0...2) {
            Text("Intensity bias")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.bumpscopeIntensityBias, model)
        Slider(value: $model.settings.bumpscopeIntensityClampMin, in: 0...1) {
            Text("Intensity clamp min")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeIntensityClampMin, model)
        Slider(value: $model.settings.bumpscopeIntensityClampMax, in: 0...1) {
            Text("Intensity clamp max")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeIntensityClampMax, model)
        Slider(value: $model.settings.bumpscopeAlpha, in: 0...1) {
            Text("Alpha")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.bumpscopeAlpha, model)
    }

    @ViewBuilder
    private var outrunHorizonControls: some View {
        outrunSectionHeader("Horizon & Backdrop")
        Slider(value: $model.settings.outrunHorizon, in: 0.05...1.0) {
            Text("Horizon height")
        } minimumValueLabel: { Text("0.05") } maximumValueLabel: { Text("1") }
            .resettable(\.outrunHorizon, model)
        Slider(value: $model.settings.outrunHorizonGlowScale, in: 0...12) {
            Text("Horizon glow sharpness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("12") }
            .resettable(\.outrunHorizonGlowScale, model)
        Slider(value: $model.settings.outrunHorizonGlowBase, in: 0...3) {
            Text("Horizon glow")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunHorizonGlowBase, model)
        Slider(value: $model.settings.outrunHorizonBassGlow, in: 0...3) {
            Text("Bass → horizon glow")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunHorizonBassGlow, model)
        Slider(value: $model.settings.outrunLowMidBackdrop, in: 0...3) {
            Text("Low-mid → backdrop")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunLowMidBackdrop, model)
        Slider(value: $model.settings.outrunBackgroundBrightness, in: 0...1) {
            Text("Backdrop brightness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.outrunBackgroundBrightness, model)
        Slider(value: $model.settings.outrunBackgroundGlow, in: 0...3) {
            Text("Backdrop glow")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunBackgroundGlow, model)
    }

    @ViewBuilder
    private var outrunMotionControls: some View {
        outrunSectionHeader("Rain Motion")
        Slider(value: $model.settings.outrunLeanBase, in: 0...1) {
            Text("Lean")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.outrunLeanBase, model)
        Slider(value: $model.settings.outrunLeanLowMid, in: 0...3) {
            Text("Low-mid → lean")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunLeanLowMid, model)
        Slider(value: $model.settings.outrunFallBase, in: 0...3) {
            Text("Fall speed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunFallBase, model)
        Slider(value: $model.settings.outrunFallBass, in: 0...3) {
            Text("Bass → fall")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunFallBass, model)
        Slider(value: $model.settings.outrunFallEnergy, in: 0...3) {
            Text("Energy → fall")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunFallEnergy, model)
        Slider(value: $model.settings.outrunDensity, in: 20...160) {
            Text("Density")
        } minimumValueLabel: { Text("20") } maximumValueLabel: { Text("160") }
            .resettable(\.outrunDensity, model)
    }

    @ViewBuilder
    private var outrunLayer0Controls: some View {
        outrunSectionHeader("Depth Layer 0 (far)")
        Slider(value: $model.settings.outrunLayer0ColumnScale, in: 0...4) {
            Text("Column scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.outrunLayer0ColumnScale, model)
        Slider(value: $model.settings.outrunLayer0FallScale, in: 0...3) {
            Text("Fall scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunLayer0FallScale, model)
        Slider(value: $model.settings.outrunLayer0Seed, in: 0...8) {
            Text("Seed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("8") }
            .resettable(\.outrunLayer0Seed, model)
        Slider(value: $model.settings.outrunLayer0Thickness, in: 40...800) {
            Text("Thickness")
        } minimumValueLabel: { Text("40") } maximumValueLabel: { Text("800") }
            .resettable(\.outrunLayer0Thickness, model)
        Slider(value: $model.settings.outrunLayer0Weight, in: 0...2) {
            Text("Weight")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.outrunLayer0Weight, model)
    }

    @ViewBuilder
    private var outrunLayer1Controls: some View {
        outrunSectionHeader("Depth Layer 1 (mid)")
        Slider(value: $model.settings.outrunLayer1ColumnScale, in: 0...4) {
            Text("Column scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.outrunLayer1ColumnScale, model)
        Slider(value: $model.settings.outrunLayer1FallScale, in: 0...3) {
            Text("Fall scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunLayer1FallScale, model)
        Slider(value: $model.settings.outrunLayer1Seed, in: 0...8) {
            Text("Seed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("8") }
            .resettable(\.outrunLayer1Seed, model)
        Slider(value: $model.settings.outrunLayer1Thickness, in: 40...800) {
            Text("Thickness")
        } minimumValueLabel: { Text("40") } maximumValueLabel: { Text("800") }
            .resettable(\.outrunLayer1Thickness, model)
        Slider(value: $model.settings.outrunLayer1Weight, in: 0...2) {
            Text("Weight")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.outrunLayer1Weight, model)
    }

    @ViewBuilder
    private var outrunLayer2Controls: some View {
        outrunSectionHeader("Depth Layer 2 (near)")
        Slider(value: $model.settings.outrunLayer2ColumnScale, in: 0...4) {
            Text("Column scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.outrunLayer2ColumnScale, model)
        Slider(value: $model.settings.outrunLayer2FallScale, in: 0...3) {
            Text("Fall scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunLayer2FallScale, model)
        Slider(value: $model.settings.outrunLayer2Seed, in: 0...8) {
            Text("Seed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("8") }
            .resettable(\.outrunLayer2Seed, model)
        Slider(value: $model.settings.outrunLayer2Thickness, in: 40...800) {
            Text("Thickness")
        } minimumValueLabel: { Text("40") } maximumValueLabel: { Text("800") }
            .resettable(\.outrunLayer2Thickness, model)
        Slider(value: $model.settings.outrunLayer2Weight, in: 0...2) {
            Text("Weight")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.outrunLayer2Weight, model)
    }

    @ViewBuilder
    private var outrunSparkleControls: some View {
        outrunSectionHeader("Sparkle Layer")
        Slider(value: $model.settings.outrunSparkleColumnScale, in: 0...4) {
            Text("Column scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.outrunSparkleColumnScale, model)
        Slider(value: $model.settings.outrunSparkleFallScale, in: 0...3) {
            Text("Fall scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunSparkleFallScale, model)
        Slider(value: $model.settings.outrunSparkleSeed, in: 0...8) {
            Text("Seed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("8") }
            .resettable(\.outrunSparkleSeed, model)
        Slider(value: $model.settings.outrunSparkleThickness, in: 40...800) {
            Text("Thickness")
        } minimumValueLabel: { Text("40") } maximumValueLabel: { Text("800") }
            .resettable(\.outrunSparkleThickness, model)
        Slider(value: $model.settings.outrunSparkleBase, in: 0...3) {
            Text("Sparkle")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunSparkleBase, model)
        Slider(value: $model.settings.outrunSparkleTreble, in: 0...3) {
            Text("Treble → sparkle")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunSparkleTreble, model)
    }

    @ViewBuilder
    private var outrunShapeColorControls: some View {
        outrunSectionHeader("Rain Shape & Color")
        Slider(value: $model.settings.outrunRainVerticalBase, in: 0...1) {
            Text("Density floor (top)")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.outrunRainVerticalBase, model)
        Slider(value: $model.settings.outrunRainVerticalY, in: 0...2) {
            Text("Density gain (bottom)")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.outrunRainVerticalY, model)
        Slider(value: $model.settings.outrunRainColorBase, in: 0...1) {
            Text("Rain color")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.outrunRainColorBase, model)
        Slider(value: $model.settings.outrunRainColorTreble, in: 0...3) {
            Text("Treble → color")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunRainColorTreble, model)
        Slider(value: $model.settings.outrunRainColorEnergy, in: 0...3) {
            Text("Energy → color")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunRainColorEnergy, model)
    }

    @ViewBuilder
    private var outrunBrightnessReflectionControls: some View {
        outrunSectionHeader("Brightness & Reflection")
        Slider(value: $model.settings.outrunRainBrightnessBase, in: 0...3) {
            Text("Rain brightness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunRainBrightnessBase, model)
        Slider(value: $model.settings.outrunRainBrightnessEnergy, in: 0...3) {
            Text("Energy → brightness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunRainBrightnessEnergy, model)
        Slider(value: $model.settings.outrunRainBrightnessTreble, in: 0...3) {
            Text("Treble → brightness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunRainBrightnessTreble, model)
        Slider(value: $model.settings.outrunReflectionWidth, in: 0...8) {
            Text("Reflection width")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("8") }
            .resettable(\.outrunReflectionWidth, model)
        Slider(value: $model.settings.outrunReflectionBass, in: 0...3) {
            Text("Bass → reflection")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.outrunReflectionBass, model)
    }

    /// Octave Meatballs's full tunable set. Every slider sets either a resting
    /// "base" value or an audio-response coefficient the shader multiplies onto
    /// bands/energy; defaults reproduce today's look exactly. The controls are
    /// split across labelled sub-sections (each its own `@ViewBuilder` var) so no
    /// single `ViewBuilder` block exceeds the ~10-child limit. The Density
    /// subgroup's octave count is the shader loop bound — it raises GPU cost as
    /// it climbs, hence the quiet "(performance)" caption.
    @ViewBuilder
    private var octaveMeatballsControls: some View {
        octaveMeatballsPatternControls
        octaveMeatballsShimmerControls
        octaveMeatballsDriftControls
        octaveMeatballsFieldControls
        octaveMeatballsColorControls
        octaveMeatballsAudioControls
        octaveMeatballsDensityControls
    }

    private func octaveSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var octaveMeatballsPatternControls: some View {
        octaveSectionHeader("Pattern & Scale")
        Slider(value: $model.settings.octaveMeatballsScale, in: 1...30) {
            Text("Scale")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("30") }
            .resettable(\.octaveMeatballsScale, model)
        Slider(value: $model.settings.octaveMeatballsBallDivisor, in: 1...30) {
            Text("Balls per octave")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("30") }
            .resettable(\.octaveMeatballsBallDivisor, model)
    }

    @ViewBuilder
    private var octaveMeatballsShimmerControls: some View {
        octaveSectionHeader("Shimmer & Drift")
        Slider(value: $model.settings.octaveMeatballsOctavePhase, in: 0...1) {
            Text("Octave phase")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.octaveMeatballsOctavePhase, model)
        Slider(value: $model.settings.octaveMeatballsShimmerOctaveScale, in: 0...2) {
            Text("Shimmer octave scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.octaveMeatballsShimmerOctaveScale, model)
        Slider(value: $model.settings.octaveMeatballsShimmerTimeScale, in: 0...1) {
            Text("Shimmer time scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.octaveMeatballsShimmerTimeScale, model)
        Slider(value: $model.settings.octaveMeatballsLifeTimeScale, in: 0...1) {
            Text("Drift time scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.octaveMeatballsLifeTimeScale, model)
        Slider(value: $model.settings.octaveMeatballsLifeOctaveScale, in: 0...0.2) {
            Text("Drift octave scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.2") }
            .resettable(\.octaveMeatballsLifeOctaveScale, model)
    }

    @ViewBuilder
    private var octaveMeatballsDriftControls: some View {
        Slider(value: $model.settings.octaveMeatballsPulseEdge0, in: 0...1) {
            Text("Pulse edge 0")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.octaveMeatballsPulseEdge0, model)
        Slider(value: $model.settings.octaveMeatballsPulseEdge1, in: 0...1) {
            Text("Pulse edge 1")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.octaveMeatballsPulseEdge1, model)
        Slider(value: $model.settings.octaveMeatballsLifeDenomBase, in: 0...0.2) {
            Text("Drift denom base")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.2") }
            .resettable(\.octaveMeatballsLifeDenomBase, model)
        Slider(value: $model.settings.octaveMeatballsLifeDenomRadius, in: 0...0.01) {
            Text("Drift denom radius")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.01") }
            .resettable(\.octaveMeatballsLifeDenomRadius, model)
        Slider(value: $model.settings.octaveMeatballsLifeDenomScale, in: 1...200) {
            Text("Drift denom scale")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("200") }
            .resettable(\.octaveMeatballsLifeDenomScale, model)
    }

    @ViewBuilder
    private var octaveMeatballsFieldControls: some View {
        octaveSectionHeader("Metaball Field")
        Slider(value: $model.settings.octaveMeatballsDistanceFloor, in: 0.0001...0.05) {
            Text("Distance floor")
        } minimumValueLabel: { Text("Tiny") } maximumValueLabel: { Text("0.05") }
            .resettable(\.octaveMeatballsDistanceFloor, model)
        Slider(value: $model.settings.octaveMeatballsBallStrength, in: 0...0.1) {
            Text("Ball strength")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.1") }
            .resettable(\.octaveMeatballsBallStrength, model)
        Slider(value: $model.settings.octaveMeatballsBallBase, in: 0...2) {
            Text("Ball base brightness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.octaveMeatballsBallBase, model)
    }

    @ViewBuilder
    private var octaveMeatballsColorControls: some View {
        octaveSectionHeader("Color & Palette")
        Slider(value: $model.settings.octaveMeatballsBackgroundR, in: 0...0.5) {
            Text("Background R")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.octaveMeatballsBackgroundR, model)
        Slider(value: $model.settings.octaveMeatballsBackgroundG, in: 0...0.5) {
            Text("Background G")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.octaveMeatballsBackgroundG, model)
        Slider(value: $model.settings.octaveMeatballsBackgroundB, in: 0...0.5) {
            Text("Background B")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.octaveMeatballsBackgroundB, model)
        Slider(value: $model.settings.octaveMeatballsRedGlowR, in: 0...0.5) {
            Text("Glow R")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.octaveMeatballsRedGlowR, model)
        Slider(value: $model.settings.octaveMeatballsRedGlowG, in: 0...0.5) {
            Text("Glow G")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.octaveMeatballsRedGlowG, model)
        Slider(value: $model.settings.octaveMeatballsRedGlowB, in: 0...0.5) {
            Text("Glow B")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.octaveMeatballsRedGlowB, model)
        Slider(value: $model.settings.octaveMeatballsPaletteFieldGain, in: 0...5) {
            Text("Palette field gain")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("5") }
            .resettable(\.octaveMeatballsPaletteFieldGain, model)
        Slider(value: $model.settings.octaveMeatballsPaletteGain, in: 0...5) {
            Text("Palette gain")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("5") }
            .resettable(\.octaveMeatballsPaletteGain, model)
    }

    @ViewBuilder
    private var octaveMeatballsAudioControls: some View {
        octaveSectionHeader("Audio Response")
        Slider(value: $model.settings.octaveMeatballsBandPhase, in: 0...6) {
            Text("Band → phase")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("6") }
            .resettable(\.octaveMeatballsBandPhase, model)
        Slider(value: $model.settings.octaveMeatballsBandBrightness, in: 0...5) {
            Text("Band → brightness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("5") }
            .resettable(\.octaveMeatballsBandBrightness, model)
        Slider(value: $model.settings.octaveMeatballsEnergyBrightness, in: 0...3) {
            Text("Energy → brightness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.octaveMeatballsEnergyBrightness, model)
        Slider(value: $model.settings.octaveMeatballsPaletteEnergy, in: 0...2) {
            Text("Energy → palette")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.octaveMeatballsPaletteEnergy, model)
    }

    @ViewBuilder
    private var octaveMeatballsDensityControls: some View {
        octaveSectionHeader("Density (performance)")
        Slider(
            value: Binding(
                get: { Double(model.settings.octaveMeatballsOctaves) },
                set: { model.settings.octaveMeatballsOctaves = Int($0.rounded()) }
            ),
            in: 1...32, step: 1
        ) {
            Text("Octaves: \(model.settings.octaveMeatballsOctaves)")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("32") }
            .resettable(\.octaveMeatballsOctaves, model)
    }

    // MARK: - Lava Lamp controls

    /// Lava Lamp's tunables. Most fields are shared by both render modes (the
    /// shader and the CPU marching-squares emitter advance the same points), so
    /// the render-mode picker above plus these sliders configure either mode.
    /// Grouped into @ViewBuilder sub-vars to stay under SwiftUI's ~10-child limit.
    @ViewBuilder
    private var lavaLampControls: some View {
        lavaLampFieldColorControls
        lavaLampMotionControls
        lavaLampBeatControls
        lavaLampDetailControls
    }

    @ViewBuilder
    private var lavaLampFieldColorControls: some View {
        octaveSectionHeader("Field & Color")
        Slider(value: $model.settings.lavaLampDensityFalloff, in: 0.5...40) {
            Text("Density falloff")
        } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("40") }
            .resettable(\.lavaLampDensityFalloff, model)
        Slider(value: $model.settings.lavaLampBrightnessResponse, in: 0...4) {
            Text("Brightness response")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("4") }
            .resettable(\.lavaLampBrightnessResponse, model)
        Slider(value: $model.settings.lavaLampPaletteDensityScale, in: 0...2) {
            Text("Palette density scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.lavaLampPaletteDensityScale, model)
    }

    @ViewBuilder
    private var lavaLampMotionControls: some View {
        octaveSectionHeader("Motion")
        Slider(value: $model.settings.lavaLampMotionSpeed, in: 0...2) {
            Text("Motion speed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.lavaLampMotionSpeed, model)
        Slider(value: $model.settings.lavaLampDriftStrength, in: 0...2) {
            Text("Drift strength")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.lavaLampDriftStrength, model)
        Slider(value: $model.settings.lavaLampWrapBounds, in: 1.0...2.0) {
            Text("Wrap bounds")
        } minimumValueLabel: { Text("1.0") } maximumValueLabel: { Text("2.0") }
            .resettable(\.lavaLampWrapBounds, model)
        Slider(
            value: Binding(
                get: { Double(model.settings.lavaLampBlobCount) },
                set: { model.settings.lavaLampBlobCount = Int($0.rounded()) }
            ),
            in: 1...24, step: 1
        ) {
            Text("Blobs: \(model.settings.lavaLampBlobCount)")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("24") }
            .resettable(\.lavaLampBlobCount, model)
    }

    @ViewBuilder
    private var lavaLampBeatControls: some View {
        octaveSectionHeader("Beat Response")
        Slider(value: $model.settings.lavaLampShaderBeatBoost, in: 0...3) {
            Text("Shader beat boost")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.lavaLampShaderBeatBoost, model)
        Slider(value: $model.settings.lavaLampCpuBeatBoost, in: 0...3) {
            Text("Marching beat boost")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.lavaLampCpuBeatBoost, model)
        Slider(value: $model.settings.lavaLampCpuBeatHalfLife, in: 0.02...2) {
            Text("Marching beat half-life")
        } minimumValueLabel: { Text("0.02") } maximumValueLabel: { Text("2") }
            .resettable(\.lavaLampCpuBeatHalfLife, model)
    }

    @ViewBuilder
    private var lavaLampDetailControls: some View {
        octaveSectionHeader("Detail (performance)")
        Slider(
            value: Binding(
                get: { Double(model.settings.lavaLampGridSize) },
                set: { model.settings.lavaLampGridSize = Int($0.rounded()) }
            ),
            in: 16...128, step: 1
        ) {
            Text("Grid size: \(model.settings.lavaLampGridSize)")
        } minimumValueLabel: { Text("16") } maximumValueLabel: { Text("128") }
            .resettable(\.lavaLampGridSize, model)
    }

    /// Shared particle dot size / speed sliders (particles, fountain, fireworks).
    @ViewBuilder
    private var particleSharedControls: some View {
        Slider(value: $model.settings.particleSize, in: 0.5...2.5) {
            Text("Particle size")
        } minimumValueLabel: { Text("0.5×") } maximumValueLabel: { Text("2.5×") }
            .resettable(\.particleSize, model)
        Slider(value: $model.settings.particleSpeed, in: 0.2...2.0) {
            Text("Particle speed")
        } minimumValueLabel: { Text("0.2×") } maximumValueLabel: { Text("2×") }
            .resettable(\.particleSpeed, model)
    }

    /// Per-visualization frame rate: "Use global" (nil) or an explicit rate
    /// that overrides Settings > Window > Frame rate for this style only.
    @ViewBuilder
    private var styleFrameRatePicker: some View {
        Picker("Frame rate", selection: bind(\.frameRateOverride)) {
            Text("Use global (\(model.settings.targetFPS) fps)").tag(Int?.none)
            ForEach(fpsOptions, id: \.self) { Text("\($0) fps").tag(Int?.some($0)) }
        }
        .help("Frame rate for this visualization only. Use global follows Settings > Window > Frame rate.")
        .resettable(profile: \.frameRateOverride, model)
    }

    // MARK: - Particles controls

    /// Particles' tunables, each a prior hardcoded literal in `ParticleVisualizer` (a
    /// bass-reactive starfield). Defaults reproduce today's look bit-exact, so the style
    /// is identical until a slider moves. Grouped into @ViewBuilder sub-vars to stay
    /// under SwiftUI's ~10-child limit. Particle size/speed/palette stay on the shared
    /// controls above; only particles-exclusive fields appear here.
    @ViewBuilder
    private var particlesControls: some View {
        particlesFieldControls
        particlesBrightnessControls
        particlesBassControls
        particlesMotionControls
    }

    @ViewBuilder
    private var particlesFieldControls: some View {
        octaveSectionHeader("Field")
        Slider(
            value: Binding(
                get: { Double(model.settings.particlesMaxParticles) },
                set: { model.settings.particlesMaxParticles = Int($0.rounded()) }
            ),
            in: 1...4000   // no step: 4000 tick marks hang SwiftUI's slider layout; the setter rounds
        ) {
            Text("Max particles: \(model.settings.particlesMaxParticles)")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("4000") }
            .resettable(\.particlesMaxParticles, model)
        Slider(value: $model.settings.particlesBaseSize, in: 0...0.05) {
            Text("Base size")
        } minimumValueLabel: { Text("Small") } maximumValueLabel: { Text("Large") }
            .resettable(\.particlesBaseSize, model)
        Slider(value: $model.settings.particlesInitialVelocityScale, in: 0...0.5) {
            Text("Initial velocity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.particlesInitialVelocityScale, model)
        Slider(value: $model.settings.particlesRespawnVelocityScale, in: 0...0.5) {
            Text("Respawn velocity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.particlesRespawnVelocityScale, model)
        Slider(value: $model.settings.particlesRespawnOffscreenBound, in: 0.5...2.0) {
            Text("Respawn bound")
        } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("2.0") }
            .resettable(\.particlesRespawnOffscreenBound, model)
        Slider(value: $model.settings.particlesRespawnCenterHalfRange, in: 0...1) {
            Text("Respawn spread")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.particlesRespawnCenterHalfRange, model)
    }

    @ViewBuilder
    private var particlesBrightnessControls: some View {
        octaveSectionHeader("Brightness")
        Slider(value: $model.settings.particlesBaseBrightness, in: 0...1) {
            Text("Base brightness")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.particlesBaseBrightness, model)
        Slider(value: $model.settings.particlesBrightnessJitter, in: 0...1) {
            Text("Brightness jitter")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.particlesBrightnessJitter, model)
        Slider(value: $model.settings.particlesBrightnessCap, in: 0...2) {
            Text("Brightness cap")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.particlesBrightnessCap, model)
    }

    @ViewBuilder
    private var particlesBassControls: some View {
        octaveSectionHeader("Bass Response")
        Slider(value: $model.settings.particlesBassThreshold, in: 0...1) {
            Text("Bass threshold")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.particlesBassThreshold, model)
        Slider(value: $model.settings.particlesLowBandPercent, in: 0.01...1.0) {
            Text("Low-band percent")
        } minimumValueLabel: { Text("1%") } maximumValueLabel: { Text("100%") }
            .resettable(\.particlesLowBandPercent, model)
        Slider(value: $model.settings.particlesBassImpulse, in: 0...2) {
            Text("Bass impulse")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.particlesBassImpulse, model)
        Slider(value: $model.settings.particlesBassBrightnessGain, in: 0...3) {
            Text("Bass brightness gain")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.particlesBassBrightnessGain, model)
        Slider(value: $model.settings.particlesBassSizeGain, in: 0...5) {
            Text("Bass size gain")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("5") }
            .resettable(\.particlesBassSizeGain, model)
        Slider(value: $model.settings.particlesSizeCapMultiplier, in: 0...8) {
            Text("Size cap ×")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("8") }
            .resettable(\.particlesSizeCapMultiplier, model)
    }

    @ViewBuilder
    private var particlesMotionControls: some View {
        octaveSectionHeader("Motion & Beat")
        Slider(value: $model.settings.particlesVelocityDamping, in: 0.8...1.0) {
            Text("Velocity damping")
        } minimumValueLabel: { Text("0.8") } maximumValueLabel: { Text("1.0") }
            .resettable(\.particlesVelocityDamping, model)
        Slider(value: $model.settings.particlesReturnLerpRate, in: 0...10) {
            Text("Return rate")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("10") }
            .resettable(\.particlesReturnLerpRate, model)
        Slider(value: $model.settings.particlesBeatHalfLife, in: 0.02...2) {
            Text("Beat half-life")
        } minimumValueLabel: { Text("0.02") } maximumValueLabel: { Text("2") }
            .resettable(\.particlesBeatHalfLife, model)
        Slider(value: $model.settings.particlesBeatPulseScale, in: 0...3) {
            Text("Beat pulse")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.particlesBeatPulseScale, model)
    }

    // MARK: - Fountain controls

    /// Fountain's tunables, each a prior hardcoded literal in
    /// SpectrumFountainVisualizer. Defaults match those literals, so the fountain
    /// looks identical until a slider moves. Grouped into @ViewBuilder sub-vars to
    /// stay under SwiftUI's ~10-child limit. Particle size/speed/palette stay on the
    /// shared controls above; only fountain-exclusive fields appear here.
    @ViewBuilder
    private var fountainControls: some View {
        fountainParticleControls
        fountainSpawningControls
        fountainLaunchControls
        fountainPhysicsControls
    }

    @ViewBuilder
    private var fountainParticleControls: some View {
        octaveSectionHeader("Particles")
        Slider(
            value: Binding(
                get: { Double(model.settings.fountainMaxParticles) },
                set: { model.settings.fountainMaxParticles = Int($0.rounded()) }
            ),
            in: 50...4000, step: 50
        ) {
            Text("Max particles: \(model.settings.fountainMaxParticles)")
        } minimumValueLabel: { Text("50") } maximumValueLabel: { Text("4000") }
            .resettable(\.fountainMaxParticles, model)
        Slider(value: $model.settings.fountainBaseSize, in: 0.001...0.05) {
            Text("Base size")
        } minimumValueLabel: { Text("Small") } maximumValueLabel: { Text("Large") }
            .resettable(\.fountainBaseSize, model)
    }

    @ViewBuilder
    private var fountainSpawningControls: some View {
        octaveSectionHeader("Spawning")
        Slider(value: $model.settings.fountainSpawnRate, in: 0...60) {
            Text("Spawn rate")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("60") }
            .resettable(\.fountainSpawnRate, model)
        Slider(value: $model.settings.fountainSpawnFloor, in: 0...1) {
            Text("Spawn floor")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.fountainSpawnFloor, model)
    }

    @ViewBuilder
    private var fountainLaunchControls: some View {
        octaveSectionHeader("Launch")
        Slider(value: $model.settings.fountainBaseUp, in: 0...2) {
            Text("Base lift")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.fountainBaseUp, model)
        Slider(value: $model.settings.fountainLaunchScale, in: 0...5) {
            Text("Launch scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("5") }
            .resettable(\.fountainLaunchScale, model)
        Slider(value: $model.settings.fountainLaunchJitter, in: 0...1) {
            Text("Launch jitter")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.fountainLaunchJitter, model)
        Slider(value: $model.settings.fountainBeatLaunchBoost, in: 0...3) {
            Text("Beat boost")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.fountainBeatLaunchBoost, model)
    }

    @ViewBuilder
    private var fountainPhysicsControls: some View {
        octaveSectionHeader("Physics")
        Slider(value: $model.settings.fountainGravity, in: 0...5) {
            Text("Gravity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("5") }
            .resettable(\.fountainGravity, model)
        Slider(value: $model.settings.fountainHorizontalJitter, in: 0...0.3) {
            Text("Horizontal jitter")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.3") }
            .resettable(\.fountainHorizontalJitter, model)
        Slider(value: $model.settings.fountainHorizontalDrag, in: 0.8...1.0) {
            Text("Horizontal drag")
        } minimumValueLabel: { Text("0.8") } maximumValueLabel: { Text("1.0") }
            .resettable(\.fountainHorizontalDrag, model)
        Slider(value: $model.settings.fountainBaseLifetime, in: 0.2...10) {
            Text("Lifetime")
        } minimumValueLabel: { Text("0.2") } maximumValueLabel: { Text("10") }
            .resettable(\.fountainBaseLifetime, model)
    }

    // MARK: - Fireworks controls

    /// Fireworks' tunables, each a prior hardcoded literal in `FireworksVisualizer`.
    /// Bursts fire only on a beat; defaults reproduce today's look bit-exact, so the
    /// style is identical until a slider moves. Grouped into @ViewBuilder sub-vars to
    /// stay under SwiftUI's ~10-child limit. Particle size/speed/palette stay on the
    /// shared controls above; only fireworks-exclusive fields appear here.
    @ViewBuilder
    private var fireworksControls: some View {
        fireworksParticleControls
        fireworksBurstControls
        fireworksBurstAreaControls
        fireworksPhysicsControls
    }

    @ViewBuilder
    private var fireworksParticleControls: some View {
        octaveSectionHeader("Particles")
        Slider(
            value: Binding(
                get: { Double(model.settings.fireworksMaxParticles) },
                set: { model.settings.fireworksMaxParticles = Int($0.rounded()) }
            ),
            in: 1...4000, step: 50
        ) {
            Text("Max particles: \(model.settings.fireworksMaxParticles)")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("4000") }
            .resettable(\.fireworksMaxParticles, model)
        Slider(value: $model.settings.fireworksBaseSize, in: 0.001...0.05) {
            Text("Base size")
        } minimumValueLabel: { Text("Small") } maximumValueLabel: { Text("Large") }
            .resettable(\.fireworksBaseSize, model)
    }

    @ViewBuilder
    private var fireworksBurstControls: some View {
        octaveSectionHeader("Burst")
        Slider(
            value: Binding(
                get: { Double(model.settings.fireworksBurstParticlesMax) },
                set: { model.settings.fireworksBurstParticlesMax = Int($0.rounded()) }
            ),
            in: 1...400    // no step (400 tick marks); the setter rounds
        ) {
            Text("Burst count: \(model.settings.fireworksBurstParticlesMax)")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("400") }
            .resettable(\.fireworksBurstParticlesMax, model)
        Slider(
            value: Binding(
                get: { Double(model.settings.fireworksBurstParticlesMin) },
                set: { model.settings.fireworksBurstParticlesMin = Int($0.rounded()) }
            ),
            in: 0...400    // no step (400 tick marks); the setter rounds
        ) {
            Text("Burst floor: \(model.settings.fireworksBurstParticlesMin)")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("400") }
            .resettable(\.fireworksBurstParticlesMin, model)
        Slider(value: $model.settings.fireworksBurstScaleBase, in: 0...2) {
            Text("Beat scale base")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.fireworksBurstScaleBase, model)
        Slider(value: $model.settings.fireworksBurstScaleIntensity, in: 0...3) {
            Text("Beat scale intensity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.fireworksBurstScaleIntensity, model)
    }

    @ViewBuilder
    private var fireworksBurstAreaControls: some View {
        octaveSectionHeader("Burst Area")
        Slider(value: $model.settings.fireworksBurstHalfX, in: 0...1) {
            Text("Horizontal range")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.fireworksBurstHalfX, model)
        Slider(value: $model.settings.fireworksBurstHalfY, in: 0...1) {
            Text("Vertical range")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.fireworksBurstHalfY, model)
        Slider(value: $model.settings.fireworksAngleJitter, in: 0...0.5) {
            Text("Angle jitter")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.fireworksAngleJitter, model)
    }

    @ViewBuilder
    private var fireworksPhysicsControls: some View {
        octaveSectionHeader("Physics")
        Slider(value: $model.settings.fireworksBaseSpeed, in: 0...3) {
            Text("Base speed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.fireworksBaseSpeed, model)
        Slider(value: $model.settings.fireworksSpreadSpeed, in: 0...2) {
            Text("Spread speed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("2") }
            .resettable(\.fireworksSpreadSpeed, model)
        Slider(value: $model.settings.fireworksGravity, in: 0...5) {
            Text("Gravity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("5") }
            .resettable(\.fireworksGravity, model)
        Slider(value: $model.settings.fireworksDrag, in: 0.8...1.0) {
            Text("Drag")
        } minimumValueLabel: { Text("0.8") } maximumValueLabel: { Text("1.0") }
            .resettable(\.fireworksDrag, model)
        Slider(value: $model.settings.fireworksBaseLifetime, in: 0.2...6) {
            Text("Lifetime")
        } minimumValueLabel: { Text("0.2") } maximumValueLabel: { Text("6") }
            .resettable(\.fireworksBaseLifetime, model)
        Slider(value: $model.settings.fireworksLifetimeJitter, in: 0...1) {
            Text("Lifetime jitter")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.fireworksLifetimeJitter, model)
        Slider(value: $model.settings.fireworksMinLifetime, in: 0.05...3) {
            Text("Min lifetime")
        } minimumValueLabel: { Text("0.05") } maximumValueLabel: { Text("3") }
            .resettable(\.fireworksMinLifetime, model)
    }

    // MARK: - Heightfield controls

    /// Heightfield's tunables. Every field is a prior hardcoded literal in
    /// `HeightfieldVisualizer`; defaults reproduce today's look for both render
    /// modes. The render-mode picker is shown above (in `controls(for:)`); these
    /// sliders configure both modes (lighting only affects Solid; line thickness
    /// only affects Wireframe). Grouped into @ViewBuilder sub-vars to stay under
    /// SwiftUI's ~10-child limit.
    @ViewBuilder
    private var heightfieldControls: some View {
        Text("Placement")
            .font(.caption)
            .foregroundStyle(.secondary)
        Toggle("Auto-fill width", isOn: $model.settings.heightfieldFillWidth)
            .help("Recomputes the grid's horizontal extent from the window's aspect ratio every frame, so it keeps spanning the full width when you resize. Overrides the X extent slider.")
            .resettable(\.heightfieldFillWidth, model)
        Toggle("Anchor to bottom", isOn: $model.settings.heightfieldAnchorBottom)
            .help("Pins the resting grid's front row to the bottom edge. Overrides the Vertical center slider; audio still lifts the back rows upward.")
            .resettable(\.heightfieldAnchorBottom, model)
        heightfieldGeometryControls
        heightfieldProjectionControls
        heightfieldWireframeControls
        heightfieldLightingControls
        heightfieldBeatOpacityControls
    }

    @ViewBuilder
    private var heightfieldGeometryControls: some View {
        octaveSectionHeader("Geometry")
        Slider(
            value: Binding(
                get: { Double(model.settings.heightfieldGridSize) },
                set: { model.settings.heightfieldGridSize = Int($0.rounded()) }
            ),
            in: 2...64, step: 1
        ) {
            Text("Grid size: \(model.settings.heightfieldGridSize)")
        } minimumValueLabel: { Text("2") } maximumValueLabel: { Text("64") }
            .resettable(\.heightfieldGridSize, model)
        Slider(value: $model.settings.heightfieldTiltAngle, in: 0...1.5) {
            Text("Tilt angle")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1.5") }
            .resettable(\.heightfieldTiltAngle, model)
        Slider(value: $model.settings.heightfieldZScale, in: 0.02...1.0) {
            Text("Height scale")
        } minimumValueLabel: { Text("0.02") } maximumValueLabel: { Text("1.0") }
            .resettable(\.heightfieldZScale, model)
        Slider(value: $model.settings.heightfieldXExtent, in: 0.3...2.0) {
            Text("X extent")
        } minimumValueLabel: { Text("0.3") } maximumValueLabel: { Text("2.0") }
            .disabled(model.settings.heightfieldFillWidth)
            .resettable(\.heightfieldXExtent, model)
        Slider(value: $model.settings.heightfieldYExtent, in: 0.3...2.0) {
            Text("Y extent")
        } minimumValueLabel: { Text("0.3") } maximumValueLabel: { Text("2.0") }
            .resettable(\.heightfieldYExtent, model)
    }

    @ViewBuilder
    private var heightfieldProjectionControls: some View {
        octaveSectionHeader("Projection")
        Slider(value: $model.settings.heightfieldVerticalFit, in: 0.5...1.2) {
            Text("Vertical fit")
        } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("1.2") }
            .resettable(\.heightfieldVerticalFit, model)
        Slider(value: $model.settings.heightfieldVerticalCenter, in: -0.5...0.5) {
            Text("Vertical center")
        } minimumValueLabel: { Text("-0.5") } maximumValueLabel: { Text("0.5") }
            .disabled(model.settings.heightfieldAnchorBottom)
            .resettable(\.heightfieldVerticalCenter, model)
    }

    @ViewBuilder
    private var heightfieldWireframeControls: some View {
        octaveSectionHeader("Wireframe")
        Slider(value: $model.settings.heightfieldLineHalfThickness, in: 0.0005...0.02) {
            Text("Line thickness")
        } minimumValueLabel: { Text("Thin") } maximumValueLabel: { Text("Thick") }
            .resettable(\.heightfieldLineHalfThickness, model)
    }

    @ViewBuilder
    private var heightfieldLightingControls: some View {
        octaveSectionHeader("Solid Lighting")
        Slider(value: $model.settings.heightfieldLightX, in: -1...1) {
            Text("Light X")
        } minimumValueLabel: { Text("-1") } maximumValueLabel: { Text("1") }
            .resettable(\.heightfieldLightX, model)
        Slider(value: $model.settings.heightfieldLightY, in: -1...1) {
            Text("Light Y")
        } minimumValueLabel: { Text("-1") } maximumValueLabel: { Text("1") }
            .resettable(\.heightfieldLightY, model)
        Slider(value: $model.settings.heightfieldLightZ, in: -1...1) {
            Text("Light Z")
        } minimumValueLabel: { Text("-1") } maximumValueLabel: { Text("1") }
            .resettable(\.heightfieldLightZ, model)
        Slider(value: $model.settings.heightfieldAmbientLight, in: 0...1) {
            Text("Ambient light")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.heightfieldAmbientLight, model)
    }

    @ViewBuilder
    private var heightfieldBeatOpacityControls: some View {
        octaveSectionHeader("Beat & Opacity")
        Slider(value: $model.settings.heightfieldBeatBoost, in: 0...3) {
            Text("Beat boost")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.heightfieldBeatBoost, model)
        Slider(value: $model.settings.heightfieldBeatHalfLife, in: 0.02...2) {
            Text("Beat half-life")
        } minimumValueLabel: { Text("0.02") } maximumValueLabel: { Text("2") }
            .resettable(\.heightfieldBeatHalfLife, model)
        Slider(value: $model.settings.heightfieldOpacity, in: 0...1) {
            Text("Opacity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.heightfieldOpacity, model)
    }

    // MARK: - Ribbon Wave controls

    /// Ribbon Wave's comprehensive tunables. Every field is a prior hardcoded
    /// literal in `RibbonWaveVisualizer`; defaults reproduce today's look
    /// byte-identically. The wave-count / tilt / depth controls are shown above
    /// (in `controls(for:)`). Grouped into @ViewBuilder sub-vars to stay under
    /// SwiftUI's ~10-child limit.
    @ViewBuilder
    private var ribbonWaveControls: some View {
        ribbonWaveShapeControls
        ribbonWaveWaveControls
        ribbonWaveMotionControls
    }

    @ViewBuilder
    private var ribbonWaveShapeControls: some View {
        octaveSectionHeader("Shape")
        Slider(
            value: Binding(
                get: { Double(model.settings.ribbonSampleCount) },
                set: { model.settings.ribbonSampleCount = Int($0.rounded()) }
            ),
            in: 16...1024, step: 16
        ) {
            Text("Sample count: \(model.settings.ribbonSampleCount)")
        } minimumValueLabel: { Text("16") } maximumValueLabel: { Text("1024") }
            .resettable(\.ribbonSampleCount, model)
        Slider(value: $model.settings.ribbonHeightScale, in: 0...1.0) {
            Text("Height scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1.0") }
            .resettable(\.ribbonHeightScale, model)
        Slider(value: $model.settings.ribbonMaxAmplitude, in: 0.1...2) {
            Text("Max amplitude")
        } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("2") }
            .resettable(\.ribbonMaxAmplitude, model)
        Slider(value: $model.settings.ribbonAlpha, in: 0...1) {
            Text("Opacity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.ribbonAlpha, model)
    }

    @ViewBuilder
    private var ribbonWaveWaveControls: some View {
        octaveSectionHeader("Waves")
        Slider(value: $model.settings.ribbonBaseFrequency, in: 0.5...20) {
            Text("Base frequency")
        } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("20") }
            .resettable(\.ribbonBaseFrequency, model)
        Slider(value: $model.settings.ribbonFrequencySpread, in: 0...20) {
            Text("Frequency spread")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("20") }
            .resettable(\.ribbonFrequencySpread, model)
        Slider(value: $model.settings.ribbonPhaseSwing, in: 0...3.2) {
            Text("Phase swing")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3.2") }
            .resettable(\.ribbonPhaseSwing, model)
    }

    @ViewBuilder
    private var ribbonWaveMotionControls: some View {
        octaveSectionHeader("Motion & Response")
        Slider(value: $model.settings.ribbonMotionSpeed, in: 0...3) {
            Text("Motion speed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.ribbonMotionSpeed, model)
        Slider(value: $model.settings.ribbonSmoothing, in: 0...1) {
            Text("Smoothing")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.ribbonSmoothing, model)
        Slider(value: $model.settings.ribbonGain, in: 0...5) {
            Text("Gain")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("5") }
            .resettable(\.ribbonGain, model)
        Slider(value: $model.settings.ribbonStereoPanScale, in: 0...1) {
            Text("Stereo pan scale")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.ribbonStereoPanScale, model)
    }

    // MARK: - Joy Plot controls

    /// Joy Plot's comprehensive tunables. Every field is a prior hardcoded
    /// literal in `JoyPlotVisualizer` (or a new neutral-at-default shift);
    /// defaults reproduce today's look byte-identically. The row count (4) is
    /// fixed because the rows have bespoke per-row audio sources. Grouped into
    /// @ViewBuilder sub-vars to stay under SwiftUI's ~10-child limit.
    @ViewBuilder
    private var joyPlotControls: some View {
        joyPlotLayoutControls
        joyPlotAppearanceControls
        joyPlotBeatControls
    }

    @ViewBuilder
    private var joyPlotLayoutControls: some View {
        octaveSectionHeader("Layout")
        Slider(
            value: Binding(
                get: { Double(model.settings.joyPlotSampleCount) },
                set: { model.settings.joyPlotSampleCount = Int($0.rounded()) }
            ),
            in: 8...512, step: 8
        ) {
            Text("Sample count: \(model.settings.joyPlotSampleCount)")
        } minimumValueLabel: { Text("8") } maximumValueLabel: { Text("512") }
            .resettable(\.joyPlotSampleCount, model)
        Slider(value: $model.settings.joyPlotRowSpacing, in: 0...1) {
            Text("Row spacing")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.joyPlotRowSpacing, model)
        Slider(value: $model.settings.joyPlotRowHeight, in: 0...0.6) {
            Text("Row height")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.6") }
            .resettable(\.joyPlotRowHeight, model)
        Slider(value: $model.settings.joyPlotBaselineOffset, in: -0.5...0.5) {
            Text("Baseline offset")
        } minimumValueLabel: { Text("-0.5") } maximumValueLabel: { Text("0.5") }
            .resettable(\.joyPlotBaselineOffset, model)
        Slider(value: $model.settings.joyPlotXExtent, in: 0.3...2.0) {
            Text("Horizontal extent")
        } minimumValueLabel: { Text("0.3") } maximumValueLabel: { Text("2.0") }
            .resettable(\.joyPlotXExtent, model)
    }

    @ViewBuilder
    private var joyPlotAppearanceControls: some View {
        octaveSectionHeader("Appearance")
        Slider(value: $model.settings.joyPlotBottomDim, in: 0...1) {
            Text("Bottom dim")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.joyPlotBottomDim, model)
        Slider(value: $model.settings.joyPlotAlpha, in: 0...1) {
            Text("Opacity")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.joyPlotAlpha, model)
    }

    @ViewBuilder
    private var joyPlotBeatControls: some View {
        octaveSectionHeader("Beat")
        Slider(value: $model.settings.joyPlotBeatBoost, in: 0...3) {
            Text("Beat boost")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.joyPlotBeatBoost, model)
        Slider(value: $model.settings.joyPlotBeatHalfLife, in: 0.02...2) {
            Text("Beat half-life")
        } minimumValueLabel: { Text("0.02") } maximumValueLabel: { Text("2") }
            .resettable(\.joyPlotBeatHalfLife, model)
    }

    // MARK: - Voronoi controls

    /// Voronoi's tunables. `seedCount` is shared by all three render modes (the
    /// shader blobs path and the CPU cells/softCells paths apply the same count
    /// to their respective seed sets); the rest are mode-specific. Grouped into
    /// @ViewBuilder sub-vars to stay under SwiftUI's ~10-child limit. Defaults
    /// match the prior hardcoded literals, so every mode looks identical until a
    /// slider moves.
    @ViewBuilder
    private var voronoiControls: some View {
        voronoiCellsControls
        voronoiMotionControls
        voronoiColorBeatControls
        voronoiSoftCellsControls
    }

    @ViewBuilder
    private var voronoiCellsControls: some View {
        octaveSectionHeader("Cells")
        Slider(
            value: Binding(
                get: { Double(model.settings.voronoiSeedCount) },
                set: { model.settings.voronoiSeedCount = Int($0.rounded()) }
            ),
            in: 1...128, step: 1
        ) {
            Text("Seeds: \(model.settings.voronoiSeedCount)")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("128") }
            .resettable(\.voronoiSeedCount, model)
        Slider(value: $model.settings.voronoiSeedSpread, in: 0.5...1.0) {
            Text("Seed spread")
        } minimumValueLabel: { Text("0.5") } maximumValueLabel: { Text("1.0") }
            .resettable(\.voronoiSeedSpread, model)
        Slider(value: $model.settings.voronoiEdgeSharpness, in: 1...40) {
            Text("Edge sharpness")
        } minimumValueLabel: { Text("1") } maximumValueLabel: { Text("40") }
            .resettable(\.voronoiEdgeSharpness, model)
    }

    @ViewBuilder
    private var voronoiMotionControls: some View {
        octaveSectionHeader("Motion")
        Slider(value: $model.settings.voronoiCyclePeriod, in: 5...300) {
            Text("Cycle period (s)")
        } minimumValueLabel: { Text("5") } maximumValueLabel: { Text("300") }
            .resettable(\.voronoiCyclePeriod, model)
        Slider(value: $model.settings.voronoiFadeDuration, in: 0.05...3) {
            Text("Fade duration (s)")
        } minimumValueLabel: { Text("0.05") } maximumValueLabel: { Text("3") }
            .resettable(\.voronoiFadeDuration, model)
        Slider(value: $model.settings.voronoiDriftSpeed, in: 0...1) {
            Text("Drift speed")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
            .resettable(\.voronoiDriftSpeed, model)
        Slider(value: $model.settings.voronoiDriftStrength, in: 0...0.5) {
            Text("Drift strength")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.voronoiDriftStrength, model)
    }

    @ViewBuilder
    private var voronoiColorBeatControls: some View {
        octaveSectionHeader("Color & Beat")
        Slider(value: $model.settings.voronoiTintRange, in: 0...0.5) {
            Text("Tint range")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("0.5") }
            .resettable(\.voronoiTintRange, model)
        Slider(value: $model.settings.voronoiShaderBeatBoost, in: 0...3) {
            Text("Shader beat boost")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.voronoiShaderBeatBoost, model)
        Slider(value: $model.settings.voronoiCpuBeatBoost, in: 0...3) {
            Text("Cells beat boost")
        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("3") }
            .resettable(\.voronoiCpuBeatBoost, model)
        Slider(value: $model.settings.voronoiCpuBeatHalfLife, in: 0.02...2) {
            Text("Cells beat half-life")
        } minimumValueLabel: { Text("0.02") } maximumValueLabel: { Text("2") }
            .resettable(\.voronoiCpuBeatHalfLife, model)
    }

    @ViewBuilder
    private var voronoiSoftCellsControls: some View {
        octaveSectionHeader("Soft Cells")
        Slider(value: $model.settings.voronoiSoftBlurSigma, in: 0.2...5) {
            Text("Soft blur sigma")
        } minimumValueLabel: { Text("0.2") } maximumValueLabel: { Text("5") }
            .resettable(\.voronoiSoftBlurSigma, model)
    }

    // MARK: - Bindings to the current profile

    /// Builds a SwiftUI Binding to a field on the current style's profile.
    /// Reads via `settings.current` (the forwarder). Writes go to just the
    /// current profile by default; when `model.applyToAllStyles` is on, the
    /// same write fans out across every style's profile so users can preview
    /// a palette/gain/glow/etc. choice across all styles at once.
    private func bind<T>(_ keyPath: WritableKeyPath<StyleProfile, T>) -> Binding<T> {
        Binding(
            get: { model.settings.current[keyPath: keyPath] },
            set: { newValue in
                if model.applyToAllStyles {
                    for style in VisualizerStyle.allCases {
                        var p = model.settings.profiles[style] ?? .defaults(for: style)
                        p[keyPath: keyPath] = newValue
                        model.settings.profiles[style] = p
                    }
                } else {
                    model.settings.mutateCurrent { $0[keyPath: keyPath] = newValue }
                }
            }
        )
    }

    /// Whether the active style is a centered, geometry (vertex-emit) style
    /// whose drawn position can be nudged (per-style offset + center-below-
    /// lyrics). Defined once on `VisualizerStyle` so the renderer and this UI
    /// agree on the set.
    private var styleSupportsPositionOffset: Bool {
        model.settings.visualizerStyle.supportsPositionOffset
    }

    /// Two-way bridge between a top-level `RGBAColor` setting and SwiftUI's
    /// `Color`. Opacity is carried separately (its own slider), so the color
    /// well runs with `supportsOpacity: false` and alpha stays 1 here — the
    /// same convention as the lyrics color wells.
    private func windowColorBinding(_ keyPath: WritableKeyPath<VisualizerSettings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(model.settings[keyPath: keyPath]) },
            set: { model.settings[keyPath: keyPath] = RGBAColor($0) }
        )
    }
}

#if DEBUG
/// A no-op capture source so previews construct a `RenderModel` without touching
/// Core Audio or any live service.
private final class PreviewCaptureSource: AudioCaptureSource {
    var state: CaptureState = .stopped
    var onSamples: (([Float], [Float], Double) -> Void)?
    func start() {}
    func stop() {}
}

private func previewModel(style: VisualizerStyle, applyToAll: Bool = false) -> RenderModel {
    let model = RenderModel(capture: PreviewCaptureSource())
    model.settings = .defaults
    model.settings.visualizerStyle = style
    model.applyToAllStyles = applyToAll
    return model
}

#Preview("Polartone (full controls)") {
    SettingsView(model: previewModel(style: .polartone), lyrics: .live())
}

#Preview("Polartone spiral (mode + spiral controls)") {
    let model = previewModel(style: .polartone)
    model.settings.polartoneRenderMode = .spiral
    return SettingsView(model: model, lyrics: .live())
}

#Preview("Bars (placeholder + apply-all)") {
    SettingsView(model: previewModel(style: .wireframe, applyToAll: true), lyrics: .live())
}
#endif

/// One sidebar category row. Tracks its own hover so the mouse highlights it
/// automatically, and fills with the accent when it is the selected category.
private struct SidebarRow: View {
    let cat: SettingsCategory
    let title: String
    let badge: Int?
    let shortcut: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: cat.icon)
                    .foregroundStyle(iconTint)
                    .frame(width: 20)
                Text(title)
                Spacer(minLength: 4)
                if let badge {
                    Text("\(badge)")
                        .font(.caption2).monospacedDigit().fontWeight(.semibold)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25)
                                                   : Color.secondary.opacity(0.22)))
                        .foregroundStyle(selected ? Color.white : .secondary)
                }
                if let shortcut {
                    Text(shortcut)
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(selected ? Color.white.opacity(0.75)
                                         : Color.secondary.opacity(0.6))
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor
                          : hovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var iconTint: Color {
        if selected { return .white }
        return cat.isGlobal ? .orange : .accentColor
    }
}

/// Settings categories, split by scope. Global categories are app-wide (amber
/// in the sidebar); per-visualization categories edit the active style's
/// profile (accent color). `allOrdered` is the sidebar order.
enum SettingsCategory: String, Hashable, Identifiable {
    // Global (app-wide)
    case styles, paletteCycle, postFX, analysis, trackOverlay, lyrics, layout, window
    // Per-visualization (active style's profile)
    case appearance, glow, bands, styleControls

    var id: String { rawValue }

    static let allOrdered: [SettingsCategory] = [
        .styles, .paletteCycle, .postFX, .analysis, .trackOverlay, .lyrics, .layout, .window,
        .styleControls, .appearance, .glow, .bands,
    ]

    var isGlobal: Bool {
        switch self {
        case .appearance, .glow, .bands, .styleControls: return false
        default: return true
        }
    }

    /// Fixed title. The Controls category shows the active style's name instead
    /// (see `SettingsView.label(for:)`).
    var title: String {
        switch self {
        case .styles:        return "Styles & Presets"
        case .paletteCycle:  return "Palette Cycle"
        case .postFX:        return "Post-FX"
        case .analysis:      return "Analysis"
        case .trackOverlay:  return "Track Overlay"
        case .lyrics:        return "Lyrics"
        case .layout:        return "Layout"
        case .window:        return "Window"
        case .appearance:    return "Appearance"
        case .glow:          return "Glow"
        case .bands:         return "Bands"
        case .styleControls: return "Controls"
        }
    }

    /// SF Symbol for the sidebar row.
    var icon: String {
        switch self {
        case .styles:        return "square.stack.3d.up"
        case .paletteCycle:  return "paintpalette"
        case .postFX:        return "sparkles"
        case .analysis:      return "waveform"
        case .trackOverlay:  return "textformat"
        case .lyrics:        return "quote.bubble"
        case .layout:        return "rectangle.3.group"
        case .window:        return "macwindow"
        case .appearance:    return "circle.lefthalf.filled"
        case .glow:          return "sun.max"
        case .bands:         return "chart.bar"
        case .styleControls: return "slider.horizontal.3"
        }
    }
}
