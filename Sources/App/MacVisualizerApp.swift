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
import Combine
import MacVisualizerCore

@main
enum AppEntry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--list-audio-processes") {
            for p in ProcessLocator.runningAudioProcesses() {
                print("\(p.bundleID)\t[\(p.id)]")
            }
            exit(0)
        }
        if args.contains("--audio-probe") {
            AudioProbe.run()
            exit(0)
        }
        if args.contains("--nowplaying-probe") {
            NowPlayingProbe.run()
            exit(0)
        }
        if args.contains("--lyrics-probe") {
            LyricsProbe.run()
            exit(0)
        }
        if args.contains("--rk-hub-check") {
            RKHubCheck.run()
            exit(0)
        }
        if let idx = args.firstIndex(of: "--render-probe"), idx + 1 < args.count {
            // Positional: --render-probe <path> [style] [renderMode] [glow]
            // `glow` is a flag matched anywhere; the optional renderMode token selects a
            // per-style render mode (e.g. softCells, blobs, marchingSquares, solid).
            let path = args[idx + 1]
            let style = (idx + 2 < args.count ? VisualizerStyle(rawValue: args[idx + 2]) : nil) ?? .bars
            let renderMode = (idx + 3 < args.count && args[idx + 3] != "glow") ? args[idx + 3] : nil
            let glow = args.contains("glow")
            let ok = RenderProbe.run(outputPath: path, style: style, glow: glow, renderMode: renderMode)
            exit(ok ? 0 : 1)
        }
        MacVisualizerMain.main()
    }
}

struct MacVisualizerMain: App {
    @StateObject private var model = RenderModel()
    @StateObject private var nowPlaying = NowPlayingService()
    @StateObject private var lyrics = LyricsModel.live()
    @State private var lyricsCoordinator: LyricsCoordinator?
    @State private var inputController: InputController?

    var body: some Scene {
        Window("Mac Visualizer", id: "main") {
            ContentView(model: model, nowPlaying: nowPlaying, lyrics: lyrics)
                .background(WindowConfigurator(
                    alwaysOnTop: model.settings.alwaysOnTop,
                    transparencyMode: model.settings.windowTransparencyMode,
                    windowOpacity: model.settings.windowOpacity,
                    clickThroughEnabled: model.settings.clickThroughEnabled,
                    borderlessWindow: model.settings.borderlessWindow,
                    windowBorderMode: model.settings.windowBorderMode
                ))
                .onAppear {
                    nowPlaying.start()
                    if inputController == nil {
                        inputController = InputController(model: model, nowPlaying: nowPlaying)
                    }
                    if lyricsCoordinator == nil {
                        lyricsCoordinator = LyricsCoordinator(model: model, nowPlaying: nowPlaying, lyrics: lyrics)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenSettingsMenuItem()
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Change") { model.undoSettings() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.canUndo)
                Button("Redo Change") { model.redoSettings() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
                Divider()
                Button("Save Current Settings as My Defaults") { model.saveCurrentAsUserDefaults() }
                Button("Clear My Defaults…") { UserDefaultsPrompts.confirmClear(model) }
                    .disabled(!model.baseline.hasUserDefaults)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
            CommandMenu("Visualizer") {
                // Bare-key shortcuts (shown in the titles) are handled by
                // InputController, not by menu key equivalents.
                Button("Next Visualization (L)") { model.nextStyle() }
                Button("Previous Visualization (H)") { model.previousStyle() }
                Button("Random Visualization (R)") { model.randomizeStyle() }
                Divider()
                Button("Next Palette (J)") { model.cyclePalette(by: 1) }
                Button("Previous Palette (K)") { model.cyclePalette(by: -1) }
                Button("Random Palette") { model.randomizePalette() }
                Divider()
                Button("Play/Pause (Space)") { nowPlaying.togglePlayPause() }
                Button("Next Song (.)") { nowPlaying.nextTrack() }
                Button("Previous Song (,)") { nowPlaying.previousTrack() }
                Divider()
                ForEach(model.settings.enabledStyles, id: \.self) { style in
                    Button(style.displayName) { model.settings.visualizerStyle = style }
                }
                Divider()
                Toggle("Demo Mode", isOn: $model.settings.demoModeEnabled)
                    .keyboardShortcut("d", modifiers: [.option, .command])
            }
            CommandMenu("Window Chrome") {
                Toggle("Borderless Window", isOn: $model.settings.borderlessWindow)
                    .keyboardShortcut("b", modifiers: .command)
                Picker("Window Border", selection: $model.settings.windowBorderMode) {
                    Text("Off").tag(WindowBorderMode.off)
                    Text("Auto — fade when idle").tag(WindowBorderMode.auto)
                    Text("Always on").tag(WindowBorderMode.always)
                }
                Button("Cycle Window Border") {
                    model.settings.windowBorderMode = model.settings.windowBorderMode.next
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                Toggle("Always on Top", isOn: $model.settings.alwaysOnTop)
                    .keyboardShortcut("t", modifiers: .command)
                Toggle("Click-Through", isOn: $model.settings.clickThroughEnabled)
                    .keyboardShortcut("c", modifiers: [.command, .control])
                Divider()
                Toggle("Show Lyrics", isOn: $model.settings.lyrics.enabled)
                    .keyboardShortcut("l", modifiers: .command)
            }
        }

        Window("Settings", id: "settings") {
            SettingsView(model: model, lyrics: lyrics)
        }
        .windowResizability(.contentMinSize)
    }

}

/// Replaces the default Preferences menu item so it routes to our `Window(id: "settings")`
/// scene (which is resizable, unlike the system Settings scene).
private struct OpenSettingsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

/// Applies window-level chrome (always-on-top, transparency, click-through) once the window exists.
private struct WindowConfigurator: NSViewRepresentable {
    /// UserDefaults key under which we persist the main window's frame.
    static let frameKey = "MacVisualizerMainWindowFrame"
    let alwaysOnTop: Bool
    let transparencyMode: WindowTransparencyMode
    let windowOpacity: Float
    let clickThroughEnabled: Bool
    let borderlessWindow: Bool
    let windowBorderMode: WindowBorderMode

    func makeCoordinator() -> FramePersistence { FramePersistence() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async { [coordinator, alwaysOnTop, transparencyMode, windowOpacity, clickThroughEnabled, borderlessWindow, windowBorderMode] in
            guard let window = view.window else { return }
            MainWindow.window = window
            coordinator.attach(to: window)      // restore saved frame + persist future moves
            logWindowIdentity(window, role: "main")
            window.level = alwaysOnTop ? .floating : .normal
            configureWindowTransparency(window, mode: transparencyMode, opacity: windowOpacity)
            window.ignoresMouseEvents = clickThroughEnabled
            configureBorderless(window, borderless: borderlessWindow, windowBorderEnabled: windowBorderMode != .off)
            configureWindowBackground(window, mode: transparencyMode, borderless: borderlessWindow, windowBorderMode: windowBorderMode)
        }
        return view
    }

    /// Owns the main window's frame restore/save, replacing both SwiftUI's own
    /// "main" autosave and AppKit's — they disagreed across monitors. One source
    /// of truth: our `frameKey` in UserDefaults.
    final class FramePersistence {
        private var observers: [NSObjectProtocol] = []
        private var attached = false

        func attach(to window: NSWindow) {
            guard !attached else { return }
            attached = true
            // Turn off the built-in frame autosave so nothing else moves the
            // window behind our back.
            window.setFrameAutosaveName("")

            // Restore the saved frame, but only if it still lands on a connected
            // screen (a monitor may have been unplugged since).
            if let s = UserDefaults.standard.string(forKey: WindowConfigurator.frameKey) {
                let rect = NSRectFromString(s)
                if rect.width > 120, rect.height > 120,
                   NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
                    let opened = window.frame   // where SwiftUI opened it; logged below
                    window.setFrame(rect, display: true)
                    // Lay out now, so the hosting view takes its new size before this
                    // block returns. Left pending, the size change is picked up by the
                    // next SwiftUI update, and if that update carries a `withAnimation`
                    // transaction (track card bloom, lyric scroll) SwiftUI animates the
                    // window size itself and loops (see WindowBorderOverlay).
                    window.layoutIfNeeded()
                    Log.window.notice("Main window frame restore: requested=\(NSStringFromRect(rect), privacy: .public) actual=\(NSStringFromRect(window.frame), privacy: .public) openedAt=\(NSStringFromRect(opened), privacy: .public)")
                }
            }

            // Save on every move / resize.
            let save: (Notification) -> Void = { [weak window] _ in
                guard let window, window.isVisible else { return }
                UserDefaults.standard.set(NSStringFromRect(window.frame),
                                          forKey: WindowConfigurator.frameKey)
            }
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: NSWindow.didMoveNotification,
                                            object: window, queue: .main, using: save))
            observers.append(nc.addObserver(forName: NSWindow.didEndLiveResizeNotification,
                                            object: window, queue: .main, using: save))
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        window.level = alwaysOnTop ? .floating : .normal
        configureWindowTransparency(window, mode: transparencyMode, opacity: windowOpacity)
        window.ignoresMouseEvents = clickThroughEnabled
        configureBorderless(window, borderless: borderlessWindow, windowBorderEnabled: windowBorderMode != .off)
        configureWindowBackground(window, mode: transparencyMode, borderless: borderlessWindow, windowBorderMode: windowBorderMode)
    }
}

/// The window background color is a function of BOTH the transparency mode and
/// the borderless setting, so it is decided in exactly one place. Per-pixel
/// alpha composites the visualizer's transparent pixels over this color, so it
/// must stay `.clear` (desktop punch-through) with or without a title bar —
/// restoring `.windowBackgroundColor` there painted the background white in
/// light appearance. The system background is only correct for a titled,
/// non-punch-through window.
private func configureWindowBackground(_ window: NSWindow,
                                       mode: WindowTransparencyMode,
                                       borderless: Bool,
                                       windowBorderMode: WindowBorderMode) {
    let wantsClear = borderless || mode == .perPixelAlpha
    window.backgroundColor = wantsClear ? .clear : .windowBackgroundColor
    // A see-through window normally must not cast the system window shadow:
    // macOS draws it around whatever is opaque (the window edge, bright
    // visualizer pixels, the lyric text), which reads as a dark border and a
    // second drop shadow the user did not ask for. But the custom window
    // border is exactly a request for a shadowed frame, so when it is on the
    // native window shadow is the drop shadow — it falls outside the border,
    // around the window, which SwiftUI content cannot draw.
    //
    // `.auto` is deliberately NOT handled here: its border fades in and out, and
    // WindowBorderOverlay toggles `hasShadow` in lockstep with that fade so the
    // shadow never orphans. Setting it here too would fight those toggles.
    switch windowBorderMode {
    case .off:    window.hasShadow = !wantsClear
    case .always: window.hasShadow = true
    case .auto:   break
    }
}

private func configureBorderless(_ window: NSWindow, borderless: Bool, windowBorderEnabled: Bool) {
    // Full-bleed look — content under a transparent title bar — is used when the
    // window is borderless OR a custom window border is on, so the border can
    // wrap the title-bar strip (and the buttons it holds).
    let fullBleed = borderless || windowBorderEnabled
    // `.fullSizeContentView` stays in the style mask at ALL times so the content
    // view is always the full window. Toggling the border (or borderless) then
    // changes only the title-bar chrome, never the content's size or position,
    // so the title/overlays do not jump up and down. `.titled` likewise stays so
    // the window can still become key under SwiftUI's NSHostingView.
    window.styleMask.insert(.fullSizeContentView)
    window.titlebarAppearsTransparent = fullBleed
    // Hide the title text in any full-bleed look; show it only for the plain
    // conventional titled window (border off, not borderless).
    window.titleVisibility = fullBleed ? .hidden : .visible
    window.titlebarSeparatorStyle = fullBleed ? .none : .automatic
    // The traffic-light buttons are hidden only in true borderless mode; with a
    // border and no borderless, the buttons stay and the border wraps around
    // them.
    window.standardWindowButton(.closeButton)?.isHidden = borderless
    window.standardWindowButton(.miniaturizeButton)?.isHidden = borderless
    window.standardWindowButton(.zoomButton)?.isHidden = borderless
    // Always movable by dragging anywhere on the window surface, not just the
    // title bar — the preferred default in both normal and borderless mode.
    window.isMovableByWindowBackground = true
}

private func configureWindowTransparency(_ window: NSWindow,
                                          mode: WindowTransparencyMode,
                                          opacity: Float) {
    switch mode {
    case .opaque:
        window.isOpaque = true
        window.alphaValue = 1.0
    case .windowOpacity:
        window.isOpaque = false
        window.alphaValue = CGFloat(opacity)
    case .perPixelAlpha:
        // Per-pixel alpha AND an overall opacity: the shader's per-pixel alpha
        // (alpha = brightness) decides the SHAPE of the transparency, then the
        // window's alphaValue scales the whole composited result, so low values
        // give a very subtle ghost. Default opacity 1.0 leaves the original
        // behavior untouched.
        window.isOpaque = false
        window.alphaValue = CGFloat(opacity)
    }
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: RenderModel
    @ObservedObject var nowPlaying: NowPlayingService
    /// Not observed here: only `LyricsOverlay` needs its changes.
    let lyrics: LyricsModel

    /// Bottom edge of the track overlay card (in the ZStack's coordinate space),
    /// reported up by TrackOverlayBottomKey. Used as the lyrics' upper limit when
    /// the overlay is in a top corner.
    @State private var trackOverlayBottom: CGFloat = 0

    /// True when the track overlay sits in a top corner, so its bottom edge is a
    /// meaningful ceiling for the lyrics (a bottom-corner overlay is not).
    private var overlayAtTop: Bool {
        model.settings.overlayPosition == .topLeading
            || model.settings.overlayPosition == .topTrailing
    }

    var body: some View {
        ZStack {
            Group {
                MetalView(model: model)
                    .ignoresSafeArea()
                LyricsOverlay(lyrics: lyrics, settings: model.settings.lyrics,
                              lyricPulse: model.lyricPulse.eraseToAnyPublisher(),
                              topInset: overlayAtTop ? trackOverlayBottom : 0,
                              onTextVisibleChange: { model.lyricsShowing = $0 },
                              replayNonce: nowPlaying.replayNonce)
                    // Fade the lyrics and title out promptly when playback stops
                    // (`track` goes nil on pause/stop, and stays set across song
                    // changes), instead of lingering frozen until the audio
                    // idle-hold fades the whole scene. The display is kept, so
                    // they fade back in with the scene on resume.
                    .opacity(nowPlaying.track != nil ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: nowPlaying.track != nil)
            }
            // Idle fade: visualization and lyrics ease out together after the
            // hold, and ease back in when audio returns. 2 seconds each way.
            .opacity(model.visualizerActive ? 1 : 0)
            .animation(.easeInOut(duration: 2.0), value: model.visualizerActive)
            // Corner track label (album art + title). Always shown while a track
            // is playing, independent of the lyrics layer, so the art and title
            // stay on screen even after the scrolling song-title header has moved
            // off. Sits outside the idle-fade Group so it does not fade with the
            // scene when music stops. Gated only by the track-overlay setting and
            // a present track (see TrackOverlay).
            TrackOverlay(track: nowPlaying.track, artwork: nowPlaying.artwork,
                         settings: model.settings,
                         sourceBundleID: nowPlaying.activeBundleID,
                         replayNonce: nowPlaying.replayNonce)
            if model.cheatSheetVisible {
                CheatSheetOverlay(mouseModifier: model.settings.mouseControlModifier,
                                  showsSpinnerKeys: model.settings.visualizerStyle == .spinner,
                                  spinnerStepDegrees: model.settings.spinnerSettings.rotationStepDegrees)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.cheatSheetVisible)
        .onAppear { SettingsRouter.shared.openSettingsWindow = { openWindow(id: "settings") } }
        .coordinateSpace(name: TrackOverlayBottomKey.space)
        .onPreferenceChange(TrackOverlayBottomKey.self) { trackOverlayBottom = $0 }
        .frame(minWidth: 640, minHeight: 360)
        .ignoresSafeArea()
        // A thin outline around the whole window edge — including the top
        // menu/title-bar strip — so the (still-resizable) border is visible to
        // grab. Independent of borderless mode: this app uses a hidden title
        // bar, so even the "titled" window has almost no OS frame. Drawn in
        // SwiftUI (not as an AppKit subview) so it stays above the Metal content
        // and tracks the window size; non-interactive, so drag-move and
        // edge-resize pass straight through it.
        .overlay {
            WindowBorderOverlay(
                mode: model.settings.windowBorderMode,
                color: Color(model.settings.windowBorderColor),
                fullOpacity: Double(max(0, min(1, model.settings.windowBorderOpacity))),
                width: CGFloat(max(0, model.settings.windowBorderWidth)))
        }
        .onChange(of: nowPlaying.track) { track in
            // Propagate NowPlayingService track changes into RenderModel so
            // VoronoiVisualizer(.perTrack) can detect them via AudioFrame.trackId.
            model.currentTrackId = NowPlayingService.trackKey(for: track)
        }
    }
}

/// The window-edge outline, drawn in SwiftUI above the Metal content and tracking
/// the window size; non-interactive, so drag-move and edge-resize pass straight
/// through it.
///
/// `.off` draws nothing, `.always` draws statically at `fullOpacity`, and `.auto`
/// runs a small reveal/idle machine: the outline fades in when the pointer moves
/// over the window or the app becomes active, then fades out after a short idle —
/// so the resize edge is visible on demand without a permanent frame. Resizing
/// still works while it is faded out (the window owns edge-resize; this overlay is
/// purely visual guidance).
private struct WindowBorderOverlay: View {
    let mode: WindowBorderMode
    let color: Color
    let fullOpacity: Double
    let width: CGFloat

    // Tunable feel. A click reveals the border quickly; it then lingers for the
    // idle hold (so it doesn't start fading the instant you click) and fades out
    // smoothly. A resize keeps it up for as long as you drag.
    private let fadeInDuration = 0.3
    private let fadeOutDuration = 1.3
    private let idleDelay = 1.5

    /// Auto-mode opacity multiplier (0 hidden → 1 full). Unused by off/always.
    @State private var level: Double = 0
    /// Last reveal activity (a click, or a resize), in a reference type so the
    /// click monitor can stamp it without triggering a view update; the poll below
    /// reads it with fresh `mode`/`activeState` each tick (no stale-capture bug).
    @State private var activity = BorderActivity()
    @State private var clickMonitor: Any?
    @Environment(\.controlActiveState) private var activeState

    // Polls a few times a second to drive the idle fade; cheap (a stroke redraw).
    private let tick = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        // macOS windows have rounded corners, so a square stroke is clipped at
        // each corner. Trace a rounded rectangle whose radius matches the system
        // window corner (it grew in macOS 26 Tahoe; no public API, so pick by OS
        // major version) so the outline follows the curve.
        let cornerRadius: CGFloat =
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 26 : 10
        let effective: Double
        switch mode {
        case .off:    effective = 0
        case .always: effective = fullOpacity
        case .auto:   effective = fullOpacity * level
        }
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(color.opacity(effective), lineWidth: width)
            // The auto fade is animated HERE, scoped to the stroke, and never with
            // `withAnimation`. `withAnimation` puts the animation on the whole
            // view-graph transaction, and `updateAuto` can run while the hosting
            // view holds a new size it has not laid out yet (it is called from the
            // window's own resize notification, and from a timer). SwiftUI then
            // animates the ROOT size too and writes each interpolated size back to
            // the window frame, which changes the root size again: a layout loop
            // that AppKit ends with an exception. A scoped animation cannot reach
            // the root size. Only `.auto` animates; off/always switch at once.
            .animation(mode == .auto
                        ? .easeInOut(duration: level > 0.5 ? fadeInDuration : fadeOutDuration)
                        : nil,
                       value: level)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // Pass-through view that only resolves the host window (for the shadow
            // toggle). hitTest returns nil, so it never intercepts clicks, drag-move
            // or the track overlay's hover.
            .background(WindowResolverView { win in
                activity.window = win
                // Establish the initial native shadow once the window resolves. A
                // fresh NSWindow defaults to hasShadow = true, but an auto border
                // starts hidden — so without this a fresh launch shows a drop shadow
                // with no border. Match the shadow to the border's current state.
                if mode == .auto {
                    let shown = level > 0.001
                    win?.hasShadow = shown
                    win?.invalidateShadow()
                    activity.shadowOn = shown
                }
            })
            .onReceive(tick) { _ in updateAuto() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
                // A resize keeps the border revealed for as long as you drag (it
                // began with a click on the edge, which already revealed it).
                guard mode == .auto, (note.object as? NSWindow) === activity.window else { return }
                activity.last = Date()
                updateAuto()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { note in
                // Dragging the window is interaction too: hold the border while it
                // moves (the move began with a click, which already revealed it).
                guard mode == .auto, level > 0.001,
                      (note.object as? NSWindow) === activity.window else { return }
                activity.last = Date()
            }
            .onChange(of: activeState) { _ in
                // Losing focus hides the border; regaining it does NOT reveal it —
                // only a deliberate click does.
                updateAuto()
            }
            .onChange(of: mode) { newMode in
                if newMode == .auto { activity.last = Date() } else { level = 0 }
                updateAuto()
            }
            .onAppear(perform: startClickMonitor)
            .onDisappear {
                stopClickMonitor()
                activity.pump?.invalidate()
                activity.pump = nil
            }
    }

    /// Reveals the border on a deliberate click anywhere in the app (mouse-down),
    /// as a non-consuming local monitor so clicks, drag-move, the track-overlay tap
    /// and resize all still work. Movement and plain focus changes do NOT reveal it.
    private func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            activity.last = Date()
            activity.pressed = true   // held until the button is released (see updateAuto)
            return event
        }
    }

    private func stopClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    /// Drives `level` toward its target: full while the window is active AND a
    /// click (or resize) landed within `idleDelay`, else hidden. On each transition it also
    /// starts a short per-frame pump that calls `invalidateShadow()` while the
    /// stroke's opacity animates, so the NATIVE window shadow fades together with
    /// the border instead of popping.
    ///
    /// Why the pump: the drop shadow is the window-server shadow drawn OUTSIDE the
    /// window edge, where SwiftUI (clipped to the window) cannot draw, so it can't
    /// be crossfaded directly. But that shadow is derived from the window's content
    /// alpha — a fainter stroke casts a fainter shadow — so re-invalidating it each
    /// frame as the stroke animates makes the shadow track the fade.
    private func updateAuto() {
        guard mode == .auto else { return }
        // A press that is still held (dragging the window, holding on the card) is
        // ongoing interaction: keep refreshing the activity stamp until release, so
        // the idle fade only starts counting from mouse-up. Polled rather than
        // watching mouse-up because the window-drag loop can swallow that event.
        if activity.pressed {
            if NSEvent.pressedMouseButtons != 0 { activity.last = Date() }
            else { activity.pressed = false }
        }
        let active = activeState != .inactive
        let recent = Date().timeIntervalSince(activity.last) < idleDelay
        let target: Double = (active && recent) ? 1 : 0
        guard abs(level - target) > 0.001 else { return }   // act only on a transition
        let fadingIn = target > level
        let duration = fadingIn ? fadeInDuration : fadeOutDuration
        if fadingIn { setShadow(true) }                      // present as the stroke grows
        level = target                                       // animated by the stroke's scoped .animation
        startShadowPump(duration: duration, turnOffAtEnd: !fadingIn)
    }

    private func setShadow(_ on: Bool) {
        guard activity.shadowOn != on else { return }
        activity.shadowOn = on
        activity.window?.hasShadow = on
        activity.window?.invalidateShadow()
    }

    /// Recomputes the native window shadow each frame for the length of a fade so
    /// it tracks the stroke's animating alpha. Replaces any running pump; at the
    /// end of a fade-out it turns the shadow fully off.
    private func startShadowPump(duration: Double, turnOffAtEnd: Bool) {
        activity.pump?.invalidate()
        let deadline = Date().addingTimeInterval(duration + 0.08)
        let pump = Timer(timeInterval: 1.0 / 60.0, repeats: true) { timer in
            activity.window?.invalidateShadow()
            if Date() >= deadline {
                timer.invalidate()
                if turnOffAtEnd { setShadow(false) }
            }
        }
        RunLoop.main.add(pump, forMode: .common)
        activity.pump = pump
    }

}

/// Shared mutable state for the auto window border, in a reference type so the
/// event monitor and window accessor can update it without invalidating the view.
private final class BorderActivity {
    var last = Date()               // last pointer activity
    var pressed = false             // a mouse button went down and has not been seen released
    weak var window: NSWindow?      // the host window, for the native shadow toggle
    var shadowOn = false            // last value written to window.hasShadow (auto mode)
    var pump: Timer?                // per-frame shadow-invalidation pump during a fade
}

/// Resolves the host `NSWindow` for the auto window border (needed to toggle the
/// native shadow in sync with the fade). Strictly pass-through — `hitTest` returns
/// nil — so it never intercepts clicks, window drag-move, or the track overlay's
/// hover.
private struct WindowResolverView: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = PassthroughView()
        v.onWindow = onWindow
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PassthroughView)?.onWindow = onWindow
    }
}

private final class PassthroughView: NSView {
    var onWindow: (NSWindow?) -> Void = { _ in }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow(window)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

