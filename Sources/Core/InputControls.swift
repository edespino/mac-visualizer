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

/// Which modifier key turns a mouse click or scroll into a visualizer action.
/// Control is deliberately absent: Control-click is a right-click on macOS.
public enum MouseControlModifier: String, Codable, Equatable, CaseIterable {
    case off, shift, option, command
}

/// Held modifier keys as a plain value (no AppKit types in Core).
public struct ModifierState: Equatable {
    public var shift: Bool
    public var option: Bool
    public var command: Bool
    public var control: Bool

    public init(shift: Bool = false, option: Bool = false, command: Bool = false, control: Bool = false) {
        self.shift = shift
        self.option = option
        self.command = command
        self.control = control
    }

    /// True when no modifier at all is held.
    public var isEmpty: Bool { !(shift || option || command || control) }

    /// True when exactly the configured modifier is held and no other.
    public func matchesOnly(_ m: MouseControlModifier) -> Bool {
        switch m {
        case .off: return false
        case .shift: return shift && !option && !command && !control
        case .option: return option && !shift && !command && !control
        case .command: return command && !shift && !option && !control
        }
    }
}

/// Everything the keyboard, mouse and context menu can ask the app to do.
public enum ControlAction: Equatable {
    case previousVisualization, nextVisualization, randomVisualization
    case previousPalette, nextPalette
    case previousSong, nextSong, togglePlayPause
    case toggleFullscreen
    case toggleCheatSheet
    /// Esc: closes the cheat sheet. The app only consumes the key when it is shown.
    case dismissCheatSheet
    case showContextMenu
}

/// macOS virtual key code for Escape.
private let escapeKeyCode: UInt16 = 53

/// Spinner-only bare keys are handled in `InputController` (they need the live Spinner state,
/// so they are not part of this pure mapping): `m` metal, `t` / Shift+`t` pitch
/// forward / back, `y` / Shift+`y` yaw right / left (both by the Spinner's rotation-step setting), `0` reset
/// orientation (Option+left-drag, a mouse gesture, rotates the disc freely and is handled in `InputController`),
/// `b` music mode, `c` hub finish, `u` hum on/off, `g` classic shader / RealityKit renderer; the scroll wheel spins
/// the disc. `m`, `c`, `b`, `u` and `g` write the Spinner's persisted settings (`StyleProfile.spinner`) through
/// `RenderModel`, exactly like the Settings controls; orientation is runtime state and is not saved. They act only
/// while the Spinner is active.
///
/// Maps a key-down to an action, or nil when the key is not bound. Bare keys only:
/// Command, Control or Option held disables every binding (Shift is allowed, since
/// `?` needs it, and letters match case-insensitively so Caps Lock works). Key
/// repeats are ignored.
public func keyAction(characters: String, keyCode: UInt16,
                      modifiers: ModifierState, isRepeat: Bool) -> ControlAction? {
    guard !isRepeat, !modifiers.command, !modifiers.control, !modifiers.option else { return nil }
    if keyCode == escapeKeyCode { return .dismissCheatSheet }
    switch characters.lowercased() {
    case "h": return .previousVisualization
    case "l": return .nextVisualization
    case "j": return .nextPalette
    case "k": return .previousPalette
    case "r": return .randomVisualization
    case ",": return .previousSong
    case ".": return .nextSong
    case " ": return .togglePlayPause
    case "f": return .toggleFullscreen
    case "?": return .toggleCheatSheet
    default: return nil
    }
}

public enum MouseButton: Equatable {
    case left, right, middle
}

/// An action bound to a mouse gesture, and whether the event must be consumed
/// (so it neither drags the window nor reaches the views underneath).
public struct MouseBinding: Equatable {
    public let action: ControlAction
    public let consume: Bool
}

/// Maps a mouse-down to a binding, or nil to leave the event alone.
/// - The configured modifier, held alone: left = previous visualization,
///   right = next, middle = random (consumed). `off` disables this layer.
/// - No modifier: right click = context menu (consumed); double left click =
///   toggle fullscreen (NOT consumed). Single bare clicks are never touched.
public func mouseBinding(button: MouseButton, clickCount: Int,
                         held: ModifierState, configured: MouseControlModifier) -> MouseBinding? {
    if held.matchesOnly(configured) {
        switch button {
        case .left: return MouseBinding(action: .previousVisualization, consume: true)
        case .right: return MouseBinding(action: .nextVisualization, consume: true)
        case .middle: return MouseBinding(action: .randomVisualization, consume: true)
        }
    }
    guard held.isEmpty else { return nil }
    switch button {
    case .right: return MouseBinding(action: .showContextMenu, consume: true)
    case .left where clickCount == 2: return MouseBinding(action: .toggleFullscreen, consume: false)
    default: return nil
    }
}

/// Turns scroll deltas into palette steps: positive = next, negative = previous.
/// Scrolling down (content moving up, i.e. a negative `scrollingDeltaY`, which AppKit
/// already adjusts for the natural-scrolling preference) steps to the next palette.
/// Shift+scroll arrives as a horizontal delta, so whichever axis is larger wins.
/// A notched wheel gives one step per event; precise (trackpad) deltas accumulate
/// to `preciseThreshold` points per step so one gesture does not skip through many.
public struct ScrollStepAccumulator {
    public var preciseThreshold: Double
    private var remainder: Double = 0

    public init(preciseThreshold: Double = 40) {
        self.preciseThreshold = preciseThreshold
    }

    public mutating func reset() { remainder = 0 }

    public mutating func steps(deltaX: Double, deltaY: Double, precise: Bool) -> Int {
        let d = abs(deltaY) >= abs(deltaX) ? deltaY : deltaX
        guard d != 0 else { return 0 }
        if !precise {
            remainder = 0
            return d < 0 ? 1 : -1
        }
        // Reversing direction mid-gesture discards what was accumulated the other way.
        if remainder != 0, (remainder < 0) != (d < 0) { remainder = 0 }
        remainder += d
        let whole = Int(abs(remainder) / preciseThreshold)
        guard whole > 0 else { return 0 }
        let negative = remainder < 0
        remainder += (negative ? 1 : -1) * Double(whole) * preciseThreshold
        return negative ? whole : -whole
    }
}
