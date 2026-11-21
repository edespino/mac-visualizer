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
import QuartzCore
import Combine
import MacVisualizerCore

/// Drives rendering from real captured audio (synthetic fallback) and applies live
/// settings changes to the analyzer, persisting them.
final class RenderModel: ObservableObject {
    @Published var settings: VisualizerSettings
    @Published private(set) var captureState: CaptureState = .stopped
    /// Whether a settings undo / redo is available, for menu-item enablement.
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// Session-only (not persisted): when true, Settings UI writes + the
    /// ⌥]/⌥[ palette-cycle shortcut fan out to every style's profile, so
    /// changing palette/gain/glow once updates all 8 visualizers at once.
    @Published var applyToAllStyles: Bool = false
    /// Whether the `?` keyboard/mouse cheat sheet is showing. Transient, never persisted.
    @Published var cheatSheetVisible: Bool = false
    /// The reset targets: the user's saved "my defaults" snapshot (or factory when
    /// none). Loaded once at launch and republished only when saved/cleared, so
    /// per-row "is modified" checks stay cheap value comparisons.
    @Published private(set) var baseline: SettingsBaseline

    /// Emits a normalized beat pulse (0…1) on the main thread each time the
    /// adaptive `LyricBeatFollower` detects an onset, so the lyrics overlay can
    /// snap the active line's shadow. Independent of the visualizers' shared
    /// `BeatDetector`, so it fires reliably at the user's low capture level.
    let lyricPulse = PassthroughSubject<Float, Never>()

    // Palette auto-cycle — deterministic engine advanced on the main/draw path
    // only (never the audio IO thread). `lastPaletteCycleTime` tracks wall-clock
    // for the per-frame dt; nil until the first advance.
    private let paletteCycleEngine = PaletteCycleEngine()
    private var lastPaletteCycleTime: CFTimeInterval?

    private let analyzer: SpectrumAnalyzer
    private let box = LatestFrameBox()
    private let capture: AudioCaptureSource
    private let dsp = DispatchQueue(label: "visualizer.dsp")
    /// Per-frame watchdog that rebuilds a *running* capture which has silently
    /// stopped delivering frames — an output-route change stranding the
    /// aggregate device's clock, or a Bluetooth device sleeping. Without it such
    /// a stall idle-fades the whole scene (and lyrics) out indefinitely while
    /// audio is actually playing. Main-thread-confined; see `tickCaptureWatchdog`.
    private var stallMonitor = CaptureStallMonitor(now: CACurrentMediaTime())
    /// Serial queue for settings persistence: debounced saves are delivered and
    /// written here, so overlapping writes can never complete out of order (a
    /// concurrent global queue offered no such guarantee).
    private let persistence = DispatchQueue(label: "visualizer.settings.persist", qos: .utility)
    private var cancellables = Set<AnyCancellable>()

    // Settings undo/redo (⌘Z / ⌘⇧Z). The history snapshots the whole
    // `VisualizerSettings`. Rapid edits (a slider drag) are coalesced into one
    // step: the first change of a burst records the pre-burst state, and changes
    // within `undoCoalesceWindow` of each other fold into it. `isRestoring`
    // guards the sink so applying an undo does not record a new step.
    private var history = UndoHistory<VisualizerSettings>()
    private var lastRecordedSettings: VisualizerSettings
    private var lastRecordTime: CFTimeInterval = 0
    private var isRestoring = false
    private let undoCoalesceWindow: CFTimeInterval = 0.35

    // DSP-queue-confined state.
    private var currentBarCount: Int
    private var currentSampleRate: Float
    /// Drives the lyric shadow bounce. Fed `frame.bassEnergy` on the dsp queue
    /// only (like the analyzer); never touched from the main thread.
    private var lyricFollower = LyricBeatFollower()

    // Demo mode state — MAIN-THREAD-CONFINED. These three fields are mutated and
    // read from `applyLive(_:)` (the Combine $settings sink) and `currentFrame()`
    // (the MTKView draw loop); both run on the main thread today, so access is
    // race-free. This confinement is unenforced by the type system, so each
    // access point asserts `dispatchPrecondition(condition: .onQueue(.main))` —
    // any future off-main access trips in Debug and Release (the precondition
    // is elided only under -Ounchecked) instead of racing silently.
    // (Contrast the analyzer/box state below, which is dsp-queue-confined.)
    private var demoSource: DemoAudioSource?
    private var demoBarCount = 0
    private var lastDemoModeEnabled = false

    /// Session-only (not persisted): the current track identifier stamped into
    /// every AudioFrame so visualizers (VoronoiVisualizer .perTrack) can detect
    /// track changes. Set by the app layer via NowPlayingService observation.
    var currentTrackId: String?

    /// Whether the lyrics overlay currently has lyrics on screen (enabled and a
    /// display loaded). Set by the app layer (LyricsCoordinator) from the
    /// LyricsModel; read on the render path to center a visualization below the
    /// text. A plain var (like `currentTrackId`): read each frame, no view update.
    var lyricsShowing: Bool = false

    /// Whether audio is currently playing. The render loop flips it after a
    /// short hold of silence; the visualizer view fades out when it goes false
    /// (idle) and fades back in when it returns true. Published so the fade is a
    /// SwiftUI opacity animation; the render loop only writes it on a change.
    @Published var visualizerActive: Bool = true
    /// Bearing hum, driven once per frame from MetalView.draw.
    let spinnerHum = SpinnerHumPlayer()

    /// Settings as the render/analyzer boundary must consume them: the current
    /// style resolved to the effective (enabled) style. The deferred correction
    /// in `applyLive` normalizes the STORED value; readers on the frame path use
    /// this accessor so a disabled style can never render, even in the window
    /// before that correction lands. Cheap: profiles is CoW, only the style
    /// enum is rewritten.
    var renderSettings: VisualizerSettings {
        var s = settings
        s.visualizerStyle = s.effectiveStyle
        return s
    }

    /// The single validated barCount accessor. DemoAudioSource,
    /// SyntheticFrameSource, and SpectrumAnalyzer.reconfigure all precondition
    /// on a positive count, so every consumer in this class reads the value
    /// through this clamp — a live mutation to <= 0 can never crash a frame.
    /// (Persisted values are already clamped at decode.)
    private static func safeBarCount(_ s: VisualizerSettings) -> Int {
        max(1, s.barCount)
    }

    init(capture: AudioCaptureSource = AudioCaptureService()) {
        var loaded = VisualizerSettings.load(from: VisualizerSettings.defaultFileURL())
        // A persisted current style that is disabled (hand-edited JSON) resolves
        // to the first enabled style before anything observes settings.
        loaded.visualizerStyle = loaded.effectiveStyle
        self.settings = loaded
        self.baseline = SettingsBaseline.load(from: SettingsBaseline.defaultFileURL())
        self.lastRecordedSettings = loaded
        self.analyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: loaded)
        self.capture = capture
        self.currentBarCount = Self.safeBarCount(loaded)
        self.currentSampleRate = 48000

        capture.onSamples = { [weak self] left, right, rate in
            guard let self else { return }
            self.dsp.async {
                if Float(rate) > 0, abs(Float(rate) - self.currentSampleRate) > 1 {
                    self.currentSampleRate = Float(rate)
                    self.analyzer.reconfigure(sampleRate: Float(rate))
                }
                if let frame = self.analyzer.append(left: left, right: right) {
                    self.box.store(frame, at: CACurrentMediaTime())
                    // Drive the lyric shadow bounce from a dedicated adaptive
                    // follower (not the visualizers' BeatDetector), so it fires
                    // at the user's low capture level. Only the pulse crosses to
                    // the main thread.
                    let pulse = self.lyricFollower.update(bassEnergy: frame.bassEnergy,
                                                          timestamp: CACurrentMediaTime())
                    if pulse > 0 {
                        DispatchQueue.main.async { [weak self] in self?.lyricPulse.send(pulse) }
                    }
                }
            }
        }
        // Capture comes up on the service's lifecycle queue; init returns at
        // once. The launch start counts as a rebuild in flight until it completes.
        stallMonitor.noteRebuildStarted(now: CACurrentMediaTime())
        capture.start(reason: "launch") { [weak self] in self?.captureRebuildFinished() }

        // Apply settings changes live (immediate) and persist (debounced).
        $settings
            .dropFirst()
            .sink { [weak self] s in self?.applyLive(s) }
            .store(in: &cancellables)

        $settings
            .dropFirst()
            .debounce(for: .seconds(0.4), scheduler: persistence)
            .sink { s in
                let url = VisualizerSettings.defaultFileURL()
                do {
                    try s.save(to: url)
                } catch {
                    Log.settings.error("Failed to save settings to \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
            .store(in: &cancellables)
    }

    /// Record the pre-change settings onto the undo stack, coalescing a burst of
    /// rapid changes (e.g. a slider drag) into a single step. Skipped while a
    /// restore (undo/redo) is applying its own settings.
    private func recordUndoSnapshot(_ s: VisualizerSettings) {
        guard !isRestoring, s != lastRecordedSettings else { return }
        let now = CACurrentMediaTime()
        if now - lastRecordTime > undoCoalesceWindow {
            history.record(lastRecordedSettings)
            canUndo = history.canUndo
            canRedo = history.canRedo
        }
        lastRecordedSettings = s
        lastRecordTime = now
    }

    /// Restore the previous settings (⌘Z). No-op when nothing to undo.
    func undoSettings() {
        guard let previous = history.undo(current: settings) else { return }
        applyRestoredSettings(previous)
    }

    /// Re-apply a change undone by `undoSettings()` (⌘⇧Z). No-op when nothing to redo.
    func redoSettings() {
        guard let next = history.redo(current: settings) else { return }
        applyRestoredSettings(next)
    }

    private func applyRestoredSettings(_ s: VisualizerSettings) {
        isRestoring = true
        settings = s                       // applyLive runs; recording is suppressed
        lastRecordedSettings = s
        lastRecordTime = CACurrentMediaTime()
        isRestoring = false
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    // MARK: - Reset to default
    //
    // Every reset is an ordinary write to `settings`, so `applyLive` →
    // `recordUndoSnapshot` makes it undoable (⌘Z) through the existing history.

    /// Saves the current settings as "my defaults".
    func saveCurrentAsUserDefaults() {
        do {
            baseline = try SettingsBaseline.save(settings, to: SettingsBaseline.defaultFileURL())
        } catch {
            Log.settings.error("Failed to save user defaults: \(String(describing: error), privacy: .public)")
        }
    }

    /// Saves only the active style into "my defaults" (other styles and app-wide
    /// settings in the snapshot, or factory if none, are kept).
    func saveCurrentStyleAsUserDefaults() {
        do {
            let merged = baseline.snapshotSavingCurrentStyle(of: settings)
            baseline = try SettingsBaseline.save(merged, to: SettingsBaseline.defaultFileURL())
        } catch {
            Log.settings.error("Failed to save style defaults: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes the saved snapshot; the baseline reverts to factory. Settings are untouched.
    func clearUserDefaults() {
        do {
            try SettingsBaseline.clear(at: SettingsBaseline.defaultFileURL())
            baseline = SettingsBaseline()
        } catch {
            Log.settings.error("Failed to clear user defaults: \(String(describing: error), privacy: .public)")
        }
    }

    /// Resets one app-wide field to the baseline (or factory).
    func resetSetting<T>(_ keyPath: WritableKeyPath<VisualizerSettings, T>, toFactory: Bool) {
        settings[keyPath: keyPath] = toFactory ? baseline.factoryValue(keyPath)
                                               : baseline.baselineValue(keyPath)
    }

    /// Resets one per-style field on the current style, or on every style (each to
    /// ITS OWN baseline) when `fanOut` and "apply to all styles" is on.
    func resetProfileField<T>(_ keyPath: WritableKeyPath<StyleProfile, T>,
                              toFactory: Bool, fanOut: Bool) {
        func value(_ style: VisualizerStyle) -> T {
            toFactory ? baseline.factoryValue(keyPath, style: style)
                      : baseline.baselineValue(keyPath, style: style)
        }
        if fanOut && applyToAllStyles {
            var s = settings
            for style in VisualizerStyle.allCases {
                var p = s.profiles[style] ?? .defaults(for: style)
                p[keyPath: keyPath] = value(style)
                s.profiles[style] = p
            }
            settings = s
        } else {
            let style = settings.visualizerStyle
            settings.mutateCurrent { $0[keyPath: keyPath] = value(style) }
        }
    }

    /// Resets the active style (profile + its exclusive fields) to the baseline or factory.
    func resetCurrentStyle(toFactory: Bool) {
        settings.resetCurrentStyle(to: toFactory ? .defaults : baseline.effective)
    }

    /// Resets every style and all app-wide settings to the baseline or factory.
    /// Does not touch the saved snapshot.
    func resetEverything(toFactory: Bool) {
        settings = toFactory ? .defaults : baseline.effective
    }

    // MARK: - Spinner actions (keys and Settings share these writes)
    //
    // The Spinner's choices are persisted per-style settings (`StyleProfile.spinner`). The bare keys write them through
    // the same `settings` publisher as the Settings controls, so persistence, the modified/reset affordance and undo
    // all apply. They act on the Spinner's profile only while the Spinner is the active style.

    private func mutateSpinner(_ body: (inout SpinnerSettings) -> Void) {
        guard settings.visualizerStyle == .spinner else { return }
        settings.mutateCurrent { (profile: inout StyleProfile) -> Void in body(&profile.spinner) }
    }

    /// Key `m`: next metal.
    func cycleSpinnerMetal() {
        mutateSpinner { (s: inout SpinnerSettings) -> Void in s.metal = s.metal.next }
    }

    /// Key `c`: next hub finish.
    func cycleSpinnerHubFinish() {
        mutateSpinner { (s: inout SpinnerSettings) -> Void in s.hubFinish = s.hubFinish.next }
    }

    /// Key `b`: next music mode.
    func cycleSpinnerMusicMode() {
        mutateSpinner { (s: inout SpinnerSettings) -> Void in s.musicMode = s.musicMode.next }
    }

    /// Key `u`: hum on/off.
    func toggleSpinnerHum() {
        mutateSpinner { (s: inout SpinnerSettings) -> Void in s.humEnabled.toggle() }
    }

    /// Key `g`: shader <-> RealityKit.
    func cycleSpinnerRenderer() {
        mutateSpinner { (s: inout SpinnerSettings) -> Void in s.renderer = s.renderer.next }
    }

    /// Key `0` and the Settings "Reset orientation" button: eases pitch and yaw back to face-on.
    func resetSpinnerOrientation() {
        SpinnerInput.shared.pendingOrientation.reset = true
    }

    /// Key `0`: resets the orientation, or flips to the other face when the target is already face-on.
    func resetOrFlipSpinnerOrientation() {
        SpinnerInput.shared.pendingOrientation.resetOrFlip = true
    }

    /// Option+`0`: resets the orientation, or flips about the vertical axis when the target is face-on.
    func resetOrFlipSpinnerYaw() {
        SpinnerInput.shared.pendingOrientation.resetOrFlipYaw = true
    }

    // MARK: - Hotkey actions (focused-only; also surfaced as menu items)

    /// Switch to the next / previous enabled style (wrapping).
    func nextStyle() {
        settings.visualizerStyle = settings.nextEnabledStyle(after: settings.visualizerStyle)
    }

    func previousStyle() {
        settings.visualizerStyle = settings.previousEnabledStyle(before: settings.visualizerStyle)
    }

    /// Switch to a random enabled style other than the current one.
    func randomizeStyle() {
        var rng = SystemRandomNumberGenerator()
        settings.visualizerStyle = settings.randomEnabledStyle(
            excluding: settings.visualizerStyle, using: &rng)
    }

    /// Pick a random palette other than the current one (honors "apply to all").
    func randomizePalette() {
        var rng = SystemRandomNumberGenerator()
        applyPalette(settings.randomPaletteName(excluding: settings.paletteName, using: &rng))
    }

    /// Step the active palette by `delta` (+1 next, -1 previous), wrapping.
    func cyclePalette(by delta: Int) {
        let names = ColorPalette.orderedPresetNames
        guard !names.isEmpty else { return }
        let idx = names.firstIndex(of: settings.paletteName) ?? 0
        let count = names.count
        applyPalette(names[((idx + delta) % count + count) % count])
    }

    /// Write a palette name to the current style, or to every style's profile
    /// when "apply to all styles" is on.
    func applyPalette(_ name: String) {
        if applyToAllStyles {
            for style in VisualizerStyle.allCases {
                var p = settings.profiles[style] ?? .defaults(for: style)
                p.paletteName = name
                settings.profiles[style] = p
            }
        } else {
            settings.paletteName = name
        }
    }

    private func applyLive(_ s: VisualizerSettings) {
        // Demo-mode fields are main-thread-confined; assert before touching them.
        dispatchPrecondition(condition: .onQueue(.main))
        recordUndoSnapshot(s)
        // If the current style is disabled, fall back to the first enabled
        // style. Deferred one tick: mutating @Published synchronously inside
        // its own sink would nest willSet publishes mid-view-update. The frame
        // path does NOT depend on this landing — everything below (and every
        // `renderSettings` reader) already resolves the effective style.
        if s.visualizerStyle != s.effectiveStyle {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.settings.visualizerStyle != self.settings.effectiveStyle {
                    self.settings.visualizerStyle = self.settings.effectiveStyle
                }
            }
        }
        // Configure the demo source and analyzer for the style that will
        // actually render, never a transiently-disabled current style.
        var s = s
        s.visualizerStyle = s.effectiveStyle
        // Recreate / reset the demo source on toggle-on or when barCount changes
        // while the toggle is on. Reset means: the next nextFrame(at:) call
        // restarts the demo clock at t=0 so the user sees the beat from the top.
        if s.demoModeEnabled {
            let barCount = Self.safeBarCount(s)
            if demoSource == nil || barCount != demoBarCount {
                demoSource = DemoAudioSource(barCount: barCount)
                demoBarCount = barCount
            } else if !lastDemoModeEnabled {
                demoSource?.reset()
            }
        }
        lastDemoModeEnabled = s.demoModeEnabled

        dsp.async {
            self.analyzer.update(gain: s.gain, smoothing: s.smoothing, peakHoldEnabled: s.peakHoldEnabled)
            self.analyzer.setWindow(s.fftWindow)
            let barCount = Self.safeBarCount(s)
            if barCount != self.currentBarCount {
                self.currentBarCount = barCount
                self.analyzer.reconfigure(barCount: barCount)
            }
            // Musical Spectrum reads note-aligned bands: switch the analyzer's
            // mapping while that style is active (setBandMapping is a no-op
            // when unchanged). C-based octave n starts at MIDI 12*(n+1).
            let mapping: SpectrumAnalyzer.BandMapping
            if s.visualizerStyle == .musicalSpectrum {
                let startOctave = max(0, min(5, s.musicalStartOctave))
                let octaves = max(1, min(8, s.musicalOctaveCount))
                mapping = .notes(minMidi: 12 * (startOctave + 1), count: octaves * 12)
            } else {
                mapping = .logSpaced
            }
            self.analyzer.setBandMapping(mapping)
        }
    }

    /// Live capture energy for the idle fade. Nil when the process tap is not
    /// delivering a fresh frame. Demo mode is reported separately so the
    /// synthetic demo does not count as silence, and the synthetic fallback
    /// used when nothing is playing does not count as music.
    func idleAudioSample(now: CFTimeInterval) -> IdleAudioSample {
        if renderSettings.demoModeEnabled { return .demo }
        guard capture.state == .running,
              let frame = box.recent(now: now, maxAge: 0.5) else { return .noCapture }
        return .level(max(frame.peak, frame.rms))
    }

    /// Per-frame capture watchdog (main/draw thread). A running capture that has
    /// stopped delivering frames for `CaptureStallMonitor.stallSeconds` — an
    /// output-route change stranding the aggregate's clock, a Bluetooth device
    /// sleeping — is rebuilt so the scene does not idle-fade out while audio is
    /// playing. The output-device listener in the capture service handles the
    /// common switch instantly; this is the backstop for stalls with no change
    /// event (e.g. a Bluetooth clock pausing). Demo mode renders synthetic
    /// frames and never fades, so its lack of live frames is not a stall.
    func tickCaptureWatchdog(now: CFTimeInterval) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !renderSettings.demoModeEnabled else {
            stallMonitor.noteSample(now: now)   // keep the clock fresh for when demo ends
            return
        }
        if box.recent(now: now, maxAge: 0.5) != nil {
            stallMonitor.noteSample(now: now)
        }
        let status = CaptureStallMonitor.Status(capture.state)
        // A non-nil track id means the player is playing (it is nil on pause/stop);
        // fed from NowPlayingService.track, which polls every 1.5 s.
        let wasSuppressed = stallMonitor.isGateSuppressing
        let rebuild = stallMonitor.shouldRebuild(now: now, status: status,
                                                 playerPlaying: currentTrackId != nil)
        if stallMonitor.isGateSuppressing != wasSuppressed {
            if stallMonitor.isGateSuppressing {
                Log.audioCapture.notice("Stall rebuilds suppressed: no track playing")
            } else {
                Log.audioCapture.notice("Stall rebuilds resumed: track playing")
            }
        }
        if rebuild {
            if status == .failed {
                Log.audioCapture.notice("Capture failed; retrying")
            } else {
                Log.audioCapture.notice("Capture stalled while running; rebuilding (fruitless=\(self.stallMonitor.fruitlessCount) backoff=\(Int(self.stallMonitor.currentBackoffSeconds))s)")
            }
            // The rebuild runs off main and may take a minute or more; the monitor
            // suppresses every further decision until the completion arrives.
            stallMonitor.noteRebuildStarted(now: now)
            capture.restart(reason: status == .failed ? "failed-retry" : "stall") { [weak self] in
                self?.captureRebuildFinished()
            }
        }
    }

    /// Completion of a launch/stall/failed-retry rebuild, delivered on main.
    /// Fresh clock: the finish time, not the request time, restarts the stall,
    /// backoff and failed-retry timers.
    private func captureRebuildFinished() {
        dispatchPrecondition(condition: .onQueue(.main))
        stallMonitor.noteRebuildFinished(now: CACurrentMediaTime())
        captureState = capture.state
    }

    /// The frame to render right now: real audio if flowing recently, else synthetic
    /// (built from the current bar count so it tracks live settings changes).
    /// `trackId` is always stamped from `currentTrackId` so visualizers can detect
    /// track changes regardless of the audio source in use.
    func currentFrame() -> AudioFrame {
        // Demo-mode fields are main-thread-confined; assert before touching them.
        dispatchPrecondition(condition: .onQueue(.main))
        let now = CACurrentMediaTime()
        // Normalized snapshot: barCount must come from the profile of the style
        // that will actually render (see renderSettings).
        let s = renderSettings
        var frame: AudioFrame
        if s.demoModeEnabled {
            // Lazily build the source if applyLive hasn't constructed it yet
            // (e.g. on first launch with demoModeEnabled persisted as true).
            let barCount = Self.safeBarCount(s)
            if demoSource == nil || demoBarCount != barCount {
                demoSource = DemoAudioSource(barCount: barCount)
                demoBarCount = barCount
            }
            frame = demoSource!.nextFrame(at: now)
        } else if capture.state == .running, let captured = box.recent(now: now, maxAge: 0.5) {
            frame = captured
        } else {
            frame = SyntheticFrameSource(bandCount: Self.safeBarCount(s)).frame(at: now)
        }
        frame.trackId = currentTrackId
        return frame
    }

    /// Advance the palette auto-cycle and return the effective palette to bind
    /// this frame. Runs on the main/draw thread (asserted) — never the audio IO
    /// thread. When the feature is disabled (default), the engine is a pure
    /// passthrough so the returned palette is the named current palette exactly
    /// (bit-identical to pre-feature behavior). On the frame a crossfade
    /// completes, the committed palette name is written to every style's profile
    /// (the same fan-out the ⌥]/⌥[ "apply to all styles" shortcut uses).
    func effectivePalette() -> ColorPalette {
        dispatchPrecondition(condition: .onQueue(.main))
        let now = CACurrentMediaTime()
        let dt: Double
        if let last = lastPaletteCycleTime { dt = now - last } else { dt = 0 }
        lastPaletteCycleTime = now

        // Normalized snapshot: paletteName lives on the current profile, so it
        // must resolve through the effective style (see renderSettings).
        let s = renderSettings
        var rng = SystemRandomNumberGenerator()
        let cyc = paletteCycleEngine.advance(
            dt: dt,
            enabled: s.paletteCycleEnabled,
            interval: s.paletteCycleInterval,
            fadeDuration: s.paletteCycleFadeDuration,
            currentPaletteName: s.paletteName,
            availableNames: ColorPalette.orderedPresetNames,
            rng: &rng)

        let effective: ColorPalette
        if let next = cyc.nextName, cyc.mix > 0 {
            effective = ColorPalette.blend(ColorPalette.preset(named: cyc.currentName) ?? .fallback,
                                           ColorPalette.preset(named: next) ?? .fallback,
                                           cyc.mix)
        } else {
            effective = ColorPalette.preset(named: cyc.currentName) ?? .fallback
        }

        if let committed = cyc.committedName {
            applyPaletteToAllStyles(committed)
        }
        return effective
    }

    /// Write a palette name into every style's profile (global color identity),
    /// mirroring the ⌥]/⌥[ "apply to all styles" fan-out in MacVisualizerApp.
    private func applyPaletteToAllStyles(_ name: String) {
        for style in VisualizerStyle.allCases {
            var p = settings.profiles[style] ?? .defaults(for: style)
            p.paletteName = name
            settings.profiles[style] = p
        }
    }

    deinit { capture.stop() }
}