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

/// Trailing "reset to default" button for one settings control, shown only while
/// the value differs from its baseline. Applied as `.resettable(\.field, model)`
/// (app-wide field) or `.resettable(profile: \.field, model)` (per-style field).
///
/// "Is modified" is computed by the extension methods below, in the caller's
/// body, and passed in as a plain `Bool`; the modifier struct therefore changes
/// (and re-renders) exactly when the flag flips. Layout: nothing is reserved while
/// the value is at its default; when modified, the control gives up `reservedWidth`
/// at its trailing edge to the button.
struct ResetAffordance: ViewModifier {
    let isModified: Bool
    let hasUserDefaults: Bool
    /// Called with `true` for a factory reset (Option-click).
    let reset: (_ toFactory: Bool) -> Void

    private let reservedWidth: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(.trailing, isModified ? reservedWidth : 0)
            .overlay(alignment: .trailing) {
                if isModified {
                    Button {
                        reset(NSEvent.modifierFlags.contains(.option))
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .imageScale(.small)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(hasUserDefaults
                          ? "Reset to my default. Option-click: reset to factory default."
                          : "Reset to factory default.")
                }
            }
    }
}

extension View {
    /// Reset button for an app-wide `VisualizerSettings` field (stored fields and
    /// nested ones such as `\.lyrics.x`; not the per-style forwarders).
    func resettable<T: Equatable>(_ keyPath: WritableKeyPath<VisualizerSettings, T>,
                                  _ model: RenderModel) -> some View {
        modifier(ResetAffordance(
            isModified: model.settings[keyPath: keyPath] != model.baseline.baselineValue(keyPath),
            hasUserDefaults: model.baseline.hasUserDefaults,
            reset: { model.resetSetting(keyPath, toFactory: $0) }))
    }

    /// Reset button for a per-style `StyleProfile` field on the active style.
    /// With "apply to all styles" on, `fanOut` resets every style, each to its own
    /// baseline (pass `false` for controls whose edits do not fan out).
    func resettable<T: Equatable>(profile keyPath: WritableKeyPath<StyleProfile, T>,
                                  _ model: RenderModel, fanOut: Bool = true) -> some View {
        let style = model.settings.visualizerStyle
        return modifier(ResetAffordance(
            isModified: model.settings.current[keyPath: keyPath]
                != model.baseline.baselineValue(keyPath, style: style),
            hasUserDefaults: model.baseline.hasUserDefaults,
            reset: { model.resetProfileField(keyPath, toFactory: $0, fanOut: fanOut) }))
    }
}

/// Confirmation for clearing the saved "my defaults" snapshot, shared by the
/// Settings button and the app menu (an `NSAlert`, so it works from a menu command).
enum UserDefaultsPrompts {
    @MainActor
    static func confirmClear(_ model: RenderModel) {
        let alert = NSAlert()
        alert.messageText = "Clear your saved defaults?"
        alert.informativeText = "Reset buttons will restore factory defaults again. Your current settings are not changed."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearUserDefaults()
        }
    }
}
