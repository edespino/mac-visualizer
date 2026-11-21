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

/// Bridges AppKit code (the right-click menu) to the `Window(id: "settings")` scene
/// and lets it ask the Settings sidebar to show a specific category.
///
/// A request is kept in `pending` until a `SettingsView` consumes it, so it also works
/// when the Settings window did not exist yet and is created by the same request.
final class SettingsRouter {
    static let shared = SettingsRouter()

    /// Set by a view in the main scene (the only place `OpenWindowAction` is available).
    var openSettingsWindow: (() -> Void)?
    /// A category waiting to be shown; consumed by `SettingsView`.
    private(set) var pending: SettingsCategory?
    let requests = PassthroughSubject<Void, Never>()

    /// Opens (or focuses) the Settings window, optionally on a specific category.
    func open(_ category: SettingsCategory? = nil) {
        pending = category
        openSettingsWindow?()
        NSApp.activate(ignoringOtherApps: true)
        requests.send()
    }

    /// Returns and clears the pending category.
    func takePending() -> SettingsCategory? {
        defer { pending = nil }
        return pending
    }
}

/// The main visualizer window, registered by `WindowConfigurator`, and the Settings
/// window, registered by `SettingsWindowRegistrar`. Mouse/scroll monitors act only on
/// the main window; the bare keys also act in Settings (never while a text field edits).
enum MainWindow {
    static weak var window: NSWindow?
    static weak var settingsWindow: NSWindow?
}

/// Registers the Settings window for the bare-key monitor. Strictly pass-through
/// (`hitTest` → nil): a hit-testable helper view here would swallow clicks.
struct SettingsWindowRegistrar: NSViewRepresentable {
    final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                if MainWindow.settingsWindow !== window { logWindowIdentity(window, role: "settings") }
                MainWindow.settingsWindow = window
            }
        }
    }
    func makeNSView(context: Context) -> NSView { PassThroughView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// Diagnostic only: logs which window this is plus its geometry and view count,
/// to identify the window involved in an intermittent AppKit layout-loop crash.
func logWindowIdentity(_ window: NSWindow, role: String) {
    func count(_ v: NSView) -> Int { 1 + v.subviews.reduce(0) { $0 + count($1) } }
    let root = window.contentView?.superview ?? window.contentView
    let views = root.map(count) ?? 0
    let ptr = Unmanaged.passUnretained(window).toOpaque()
    let visible = window.screen.map { NSStringFromRect($0.visibleFrame) } ?? "nil"
    Log.window.notice("Window identity: role=\(role, privacy: .public) number=\(window.windowNumber, privacy: .public) ptr=\(String(describing: ptr), privacy: .public) frame=\(NSStringFromRect(window.frame), privacy: .public) contentLayoutRect=\(NSStringFromRect(window.contentLayoutRect), privacy: .public) screenVisibleFrame=\(visible, privacy: .public) views=\(views, privacy: .public)")
}

/// Menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func run() { handler() }
}

/// Keyboard, mouse and right-click controls for the main window.
///
/// Uses local `NSEvent` monitors only: no hit-testable views (the track overlay's
/// hover and window drag must keep working), no `acceptsMouseMovedEvents`, and no
/// hidden shortcut buttons. Pure mapping lives in Core (`InputControls.swift`).
final class InputController {
    private let model: RenderModel
    private let nowPlaying: NowPlayingService
    private var monitors: [Any] = []
    private var scroll = ScrollStepAccumulator()
    /// Option-drag rotation of the Spinner (see `handleMouse` / `handleDrag`).
    private var spinnerDrag: SpinnerDragGesture?
    /// A click action held back while an Option-press could still turn into a drag (only when the app-wide
    /// modifier is itself Option, so its left-click binding and the drag share the same press).
    private var deferredClick: ControlAction?

    init(model: RenderModel, nowPlaying: NowPlayingService) {
        self.model = model
        self.nowPlaying = nowPlaying
        install()
    }

    deinit { monitors.forEach { NSEvent.removeMonitor($0) } }

    private func install() {
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard let self else { return e }
            return self.handleKey(e)
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] e in
                guard let self else { return e }
                return self.handleMouse(e)
            }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp], handler: { [weak self] e in
                guard let self else { return e }
                return self.handleDrag(e)
            }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            guard let self else { return e }
            return self.handleScroll(e)
        }) { monitors.append(m) }
    }

    // MARK: - Event translation

    private func modifiers(of event: NSEvent) -> ModifierState {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return ModifierState(shift: f.contains(.shift), option: f.contains(.option),
                             command: f.contains(.command), control: f.contains(.control))
    }

    /// True when the event belongs to the main visualizer window.
    private func isMainWindow(_ event: NSEvent) -> Bool {
        guard let main = MainWindow.window, event.window === main else { return false }
        return true
    }

    /// True when the event belongs to the Settings window. Keys only: the mouse and
    /// scroll layers stay main-window-only so Settings' own controls are untouched.
    private func isSettingsWindow(_ event: NSEvent) -> Bool {
        guard let settings = MainWindow.settingsWindow, event.window === settings else { return false }
        return true
    }

    /// True when the point is over a title-bar button (close / minimize / zoom), which
    /// must keep working even with a modifier held.
    private func isOverWindowButton(_ event: NSEvent, in window: NSWindow) -> Bool {
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        return kinds.contains { kind in
            guard let b = window.standardWindowButton(kind), !b.isHidden else { return false }
            return b.convert(b.bounds, to: nil).contains(event.locationInWindow)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard isMainWindow(event) || isSettingsWindow(event) else { return event }
        // Never steal keys from a text editor (the Settings filter and text fields
        // type normally; the bare keys apply once focus leaves the field).
        if event.window?.firstResponder is NSText { return event }
        // Bare `m` cycles the Spinner's metal; only while that style is active.
        if model.settings.visualizerStyle == .spinner, !event.isARepeat,
           modifiers(of: event).isEmpty, event.characters == "m" {
            model.cycleSpinnerMetal()
            return nil
        }
        // Shift+`t` / Shift+`y` (capital T / Y) step the Spinner's pitch back / yaw left by one step; Shift is
        // allowed for these two keys only, no other modifier.
        if model.settings.visualizerStyle == .spinner, !event.isARepeat,
           modifiers(of: event) == ModifierState(shift: true) {
            if event.characters == "T" {
                SpinnerInput.shared.pendingOrientation.pitchSteps -= 1
                return nil
            }
            if event.characters == "Y" {
                SpinnerInput.shared.pendingOrientation.yawSteps -= 1
                return nil
            }
        }
        // Bare `t` / `y` step the Spinner's pitch forward / yaw right by one step, `0` resets the orientation,
        // `b` cycles its music mode, `c` its hub finish.
        if model.settings.visualizerStyle == .spinner, !event.isARepeat, modifiers(of: event).isEmpty {
            switch event.characters {
            case "t": SpinnerInput.shared.pendingOrientation.pitchSteps += 1; return nil
            case "y": SpinnerInput.shared.pendingOrientation.yawSteps += 1; return nil
            case "0": model.resetSpinnerOrientation(); return nil
            case "b": model.cycleSpinnerMusicMode(); return nil
            case "c": model.cycleSpinnerHubFinish(); return nil
            case "u": model.toggleSpinnerHum(); return nil            // bearing hum on/off
            case "g": model.cycleSpinnerRenderer(); return nil        // shader <-> RealityKit (macOS 15+; no effect before)
            default: break
            }
        }
        guard let action = keyAction(characters: event.characters ?? "", keyCode: event.keyCode,
                                     modifiers: modifiers(of: event), isRepeat: event.isARepeat)
        else { return event }
        if action == .dismissCheatSheet && !model.cheatSheetVisible { return event }
        perform(action, event: event)
        return nil
    }

    private func handleMouse(_ event: NSEvent) -> NSEvent? {
        guard isMainWindow(event), let window = event.window else { return event }
        // Option + left press while the Spinner is active starts a rotation drag. It is consumed so it neither moves
        // the window nor reaches anything else. When the app-wide modifier is also Option, its left-click binding
        // (previous visualization) is held back and fires on release only if the press never became a drag, so the
        // click keeps working and a drag past the movement threshold always rotates.
        if event.type == .leftMouseDown, model.settings.visualizerStyle == .spinner,
           modifiers(of: event) == ModifierState(option: true), !isOverWindowButton(event, in: window) {
            spinnerDrag = SpinnerDragGesture()
            deferredClick = nil
            if model.settings.mouseControlModifier == .option,
               let clickBinding = mouseBinding(button: .left, clickCount: event.clickCount, held: modifiers(of: event),
                                               configured: model.settings.mouseControlModifier) {
                deferredClick = clickBinding.action
            }
            return nil
        }
        let button: MouseButton
        switch event.type {
        case .leftMouseDown: button = .left
        case .rightMouseDown: button = .right
        case .otherMouseDown:
            guard event.buttonNumber == 2 else { return event }
            button = .middle
        default: return event
        }
        guard let binding = mouseBinding(button: button, clickCount: event.clickCount,
                                         held: modifiers(of: event),
                                         configured: model.settings.mouseControlModifier)
        else { return event }
        if isOverWindowButton(event, in: window) { return event }
        // A double-click in the title-bar strip is the system's zoom gesture.
        if binding.action == .toggleFullscreen,
           !window.contentLayoutRect.contains(event.locationInWindow) { return event }
        perform(binding.action, event: event)
        return binding.consume ? nil : event
    }

    /// Drag and release of an Option-drag started in `handleMouse`; consumed while one is active.
    private func handleDrag(_ event: NSEvent) -> NSEvent? {
        guard var gesture = spinnerDrag else { return event }
        if event.type == .leftMouseUp {
            let click = deferredClick
            let rotated = gesture.rotating
            spinnerDrag = nil
            deferredClick = nil
            if !rotated, let click { perform(click, event: event) }
            return nil
        }
        let step = gesture.move(deltaX: Double(event.deltaX), deltaY: Double(event.deltaY),
                                degreesPerPoint: SpinnerTuning.dragDegreesPerPoint)
        spinnerDrag = gesture
        SpinnerInput.shared.pendingOrientation.dragPitchRadians += step.pitch
        SpinnerInput.shared.pendingOrientation.dragYawRadians += step.yaw
        return nil
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard isMainWindow(event) else { return event }
        // Bare wheel spins the Spinner visualization; never consumed.
        if model.settings.visualizerStyle == .spinner, modifiers(of: event).isEmpty {
            let d = Double(event.scrollingDeltaY) / (event.hasPreciseScrollingDeltas ? 10 : 1)
            SpinnerInput.shared.pendingImpulse += d
            return event
        }
        let configured = model.settings.mouseControlModifier
        guard modifiers(of: event).matchesOnly(configured) else {
            scroll.reset()
            return event
        }
        // Inertia from a trackpad flick must not keep stepping palettes.
        if !event.momentumPhase.isEmpty { return nil }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { scroll.reset() }
        let n = scroll.steps(deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY),
                             precise: event.hasPreciseScrollingDeltas)
        if n != 0 {
            let dir = n > 0 ? 1 : -1
            for _ in 0..<abs(n) { model.cyclePalette(by: dir) }
        }
        return nil
    }

    // MARK: - Actions

    func perform(_ action: ControlAction, event: NSEvent? = nil) {
        switch action {
        case .previousVisualization: model.previousStyle()
        case .nextVisualization: model.nextStyle()
        case .randomVisualization: model.randomizeStyle()
        case .previousPalette: model.cyclePalette(by: -1)
        case .nextPalette: model.cyclePalette(by: 1)
        case .previousSong: nowPlaying.previousTrack()
        case .nextSong: nowPlaying.nextTrack()
        case .togglePlayPause: nowPlaying.togglePlayPause()
        case .toggleFullscreen: MainWindow.window?.toggleFullScreen(nil)
        case .toggleCheatSheet: model.cheatSheetVisible.toggle()
        case .dismissCheatSheet: model.cheatSheetVisible = false
        case .showContextMenu: showContextMenu(for: event)
        }
    }

    private func showContextMenu(for event: NSEvent?) {
        guard let event, let view = event.window?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, checked: Bool = false, _ run: @escaping () -> Void) {
            menu.addItem(ClosureMenuItem(title, checked: checked, handler: run))
        }
        add("Settings…") { SettingsRouter.shared.open() }
        add("Lyrics Settings…") { SettingsRouter.shared.open(.lyrics) }
        add("Layout Settings…") { SettingsRouter.shared.open(.layout) }
        menu.addItem(.separator())
        add("Next Visualization") { [model] in model.nextStyle() }
        add("Previous Visualization") { [model] in model.previousStyle() }
        add("Random Visualization") { [model] in model.randomizeStyle() }
        add("Next Palette") { [model] in model.cyclePalette(by: 1) }
        add("Previous Palette") { [model] in model.cyclePalette(by: -1) }
        menu.addItem(.separator())
        add("Play/Pause") { [nowPlaying] in nowPlaying.togglePlayPause() }
        add("Next Song") { [nowPlaying] in nowPlaying.nextTrack() }
        add("Previous Song") { [nowPlaying] in nowPlaying.previousTrack() }
        menu.addItem(.separator())
        add("Show Lyrics", checked: model.settings.lyrics.enabled) { [model] in
            model.settings.lyrics.enabled.toggle()
        }
        add("Cycle Window Border") { [model] in
            model.settings.windowBorderMode = model.settings.windowBorderMode.next
        }
        add("Toggle Full Screen") { MainWindow.window?.toggleFullScreen(nil) }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}
