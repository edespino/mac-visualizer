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

import SwiftUI
import MacVisualizerCore

/// The Controls panel of a spinner style (the Disc Spinner or the Tri-wing Spinner): grouped sections (Motion, Look,
/// Shadow, Sound & Music, and Renderer on the Disc Spinner), one control per `SpinnerSettings` field that applies to
/// that style. Every control reads and writes `StyleProfile.spinner` of the active style's own profile through
/// `RenderModel.settings`, so it persists, shares the undo history and carries the shared `.resettable` affordance with
/// the keys (`m`, Shift+`m`, `c`, `b`, `u`, `g`, `e`), which write the same fields. Sliders have no `step:` (a stepped slider lays out one
/// tick slot per step); values are rounded in the setters where a coarse unit matters.
struct SpinnerSettingsSections: View {
    @ObservedObject var model: RenderModel
    /// The spinner style being edited (the active style).
    let style: VisualizerStyle

    private var isTriWing: Bool { style == .triWingSpinner }
    /// Tooltip suffix: the classic shader exists only for the Disc Spinner.
    private var renderers: String { isTriWing ? "" : " Both renderers." }
    private var darknessNote: String { isTriWing ? "" : " Both renderers (48% is the original look)." }

    var body: some View {
        motionSection
        lookSection
        shadowSection
        soundSection
        if isTriWing {
            orientationSection
        } else {
            rendererSection
        }
    }

    // MARK: - Bindings and formatting

    private func field<T>(_ keyPath: WritableKeyPath<SpinnerSettings, T>) -> Binding<T> {
        Binding<T>(
            get: { () -> T in current[keyPath: keyPath] },
            set: { (newValue: T) -> Void in
                model.settings.mutateCurrent { (profile: inout StyleProfile) -> Void in
                    profile.spinner[keyPath: keyPath] = newValue
                }
            })
    }

    private func multiple(_ value: Double) -> String { String(format: "\u{00D7}%.2f", value) }
    private func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }
    private func radPerSecond(_ value: Double) -> String { String(format: "%.1f rad/s", value) }

    private func slider(_ title: String, _ keyPath: WritableKeyPath<SpinnerSettings, Double>,
                        range: ClosedRange<Double>, readout: String) -> some View {
        Slider(value: field(keyPath), in: range) {
            Text("\(title): \(readout)")
        }
    }

    private var current: SpinnerSettings { model.settings.profiles[style]?.spinner ?? StyleProfile.defaults(for: style).spinner }

    // MARK: - Motion

    @ViewBuilder private var motionSection: some View {
        Section("Motion") {
            frictionRow
            pushRow
            topSpeedRow
            lockRow
            stepRow
        }
    }

    private var frictionRow: some View {
        slider("Friction", \.friction, range: SpinnerSettings.frictionRange, readout: multiple(current.friction))
            .help("Multiplies both friction terms. Lower coasts longer, higher stops sooner.\(renderers)")
            .resettable(profile: \.spinner.friction, model, fanOut: false)
    }

    private var pushRow: some View {
        slider("Push strength", \.pushStrength, range: SpinnerSettings.pushStrengthRange, readout: multiple(current.pushStrength))
            .help("Multiplies how hard each scroll notch pushes the spinner.\(renderers)")
            .resettable(profile: \.spinner.pushStrength, model, fanOut: false)
    }

    private var topSpeedRow: some View {
        slider("Top speed", \.topSpeed, range: SpinnerSettings.topSpeedRange, readout: radPerSecond(current.topSpeed))
            .help("The speed limit of the spinner.\(renderers)")
            .resettable(profile: \.spinner.topSpeed, model, fanOut: false)
    }

    private var lockRow: some View {
        Toggle("Direction lock", isOn: field(\.directionLock))
            .help("On: an opposing scroll only brakes the spinner and cannot restart it the other way until a moment of quiet. Off: an opposing scroll passes through zero and reverses it.")
            .resettable(profile: \.spinner.directionLock, model, fanOut: false)
    }

    private var stepRow: some View {
        Picker("Rotation step", selection: field(\.rotationStepDegrees)) {
            ForEach(SpinnerSettings.rotationStepChoices, id: \.self) { (degrees: Int) in
                Text("\(degrees)\u{00B0}").tag(degrees)
            }
        }
        .help("How far the t / y keys (and Shift+t / Shift+y, Option+t) turn the spinner per press, and per repeat while held. 15 degrees gives 24 stops per turn.")
        .resettable(profile: \.spinner.rotationStepDegrees, model, fanOut: false)
    }

    // MARK: - Look

    @ViewBuilder private var lookSection: some View {
        Section("Look") {
            if isTriWing {
                combinationRow
                metalRow
                plateMetalRow
                bossMetalRow
                edgeLightsRow
                lightColorsRow
                beatLightsRow
                restingGlowRow
                beatGlowRow
            } else {
                metalRow
                finishRow
            }
            glowRow
            roomRow
            sizeRow
            blurRow
        }
    }

    private var edgeLightsRow: some View {
        Toggle("Edge lights", isOn: field(\.edgeLights))
            .help("The glowing tubes at the wing tips (key e). Brightness follows Glow brightness.")
            .resettable(profile: \.spinner.edgeLights, model, fanOut: false)
    }

    private var lightColorsRow: some View {
        Picker("Light colours", selection: field(\.lightColors)) {
            ForEach(SpinnerLightColors.allCases, id: \.self) { (choice: SpinnerLightColors) in
                Text(choice.displayName).tag(choice)
            }
        }
        .help("Original keeps the green, blue and orange wing lights. Follow palette takes the three wing colours from the current colour palette (the j / k keys and Palette Cycle recolour them; set the palette under Appearance). Applies to the edge-light tubes, the slot glow, the side windows and the spin-blur glow rings.")
        .resettable(profile: \.spinner.lightColors, model, fanOut: false)
    }

    private var beatLightsEnabled: Bool { current.edgeLights }

    private var beatLightsRow: some View {
        Toggle("Lights follow the beat", isOn: field(\.beatLights))
            .disabled(!beatLightsEnabled)
            .help("With Edge lights on: the edge lights pulse on the music's beat. Live audio only (Demo mode has no beat signal, so the lights rest). Bluetooth output plays late, so the light can lead the sound.")
            .resettable(profile: \.spinner.beatLights, model, fanOut: false)
    }

    private var restingGlowRow: some View {
        slider("Resting glow", \.restingGlow, range: SpinnerSettings.restingGlowRange, readout: percent(current.restingGlow))
            .disabled(!beatLightsEnabled || !current.beatLights)
            .help("Light level between beats, as a fraction of Glow brightness. Applies with Edge lights on and Lights follow the beat on. With nothing playing for 2 seconds the lights ease up to full.")
            .resettable(profile: \.spinner.restingGlow, model, fanOut: false)
    }

    private var beatGlowRow: some View {
        slider("Beat glow", \.beatGlow, range: SpinnerSettings.beatGlowRange, readout: percent(current.beatGlow))
            .disabled(!beatLightsEnabled || !current.beatLights)
            .help("Light level a beat reaches, as a fraction of Glow brightness (never below Resting glow; equal values mean no pulse). Applies with Edge lights on and Lights follow the beat on.")
            .resettable(profile: \.spinner.beatGlow, model, fanOut: false)
    }

    /// The named combination the three metal settings spell out; nil reads as Custom.
    private var combinationBinding: Binding<SpinnerMetalCombination?> {
        Binding<SpinnerMetalCombination?>(
            get: { () -> SpinnerMetalCombination? in SpinnerMetalCombination.matching(for: current) },
            set: { (choice: SpinnerMetalCombination?) -> Void in
                guard let combination = choice else { return }
                // One write, so one undo step.
                model.settings.mutateCurrent { (profile: inout StyleProfile) -> Void in
                    combination.apply(to: &profile.spinner)
                }
            })
    }

    private var combinationRow: some View {
        Picker("Combination", selection: combinationBinding) {
            ForEach(SpinnerMetalCombination.allCases, id: \.self) { (combo: SpinnerMetalCombination) in
                Text(combo.displayName).tag(Optional<SpinnerMetalCombination>.some(combo))
            }
            Text("Custom").tag(Optional<SpinnerMetalCombination>.none)
        }
        .help("Favoured body, plate and boss metal pairings. Picking one sets Metal, Plate metal and Boss metal together (Matched keeps the body metal and makes the plates and bosses follow it). Custom shows when the three settings match none of them; it cannot be picked.")
    }

    private var metalRow: some View {
        Picker("Metal", selection: field(\.metal)) {
            ForEach(SpinnerMetal.allCases, id: \.self) { (metal: SpinnerMetal) in
                Text(metal.displayName).tag(metal)
            }
        }
        .help(isTriWing
              ? "The body material (key m). It applies to the body and hub, and to the plates and bosses while they follow the body; the gold parts, blue jewels and screws, the steel bearing and the bright ring keep their own materials. Anodized Titanium is drawn as plain titanium grey."
              : "The body material (key m). Anodized Titanium shows its colour-shifting film only in the classic shader; RealityKit draws plain titanium grey.")
        .resettable(profile: \.spinner.metal, model, fanOut: false)
    }

    private var plateMetalRow: some View {
        Picker("Plate metal", selection: field(\.plateMetal)) {
            ForEach(SpinnerPlateMetal.allCases, id: \.self) { (choice: SpinnerPlateMetal) in
                Text(choice.displayName).tag(choice)
            }
        }
        .help("The metal of the three screwed-down wing plates (key Shift+m cycles it). Same as body follows Metal. The ray finish is kept in every metal.")
        .resettable(profile: \.spinner.plateMetal, model, fanOut: false)
    }

    private var bossMetalRow: some View {
        Picker("Boss metal", selection: field(\.bossMetal)) {
            ForEach(SpinnerBossMetal.allCases, id: \.self) { (choice: SpinnerBossMetal) in
                Text(choice.displayName).tag(choice)
            }
        }
        .help("The metal of the three raised round bosses that hold the jewel settings. Same as body follows Metal, Same as plate follows Plate metal. The gold setting and jewel keep their own materials.")
        .resettable(profile: \.spinner.bossMetal, model, fanOut: false)
    }

    private var finishRow: some View {
        Picker("Hub finish", selection: field(\.hubFinish)) {
            ForEach(SpinnerHubFinish.allCases, id: \.self) { (finish: SpinnerHubFinish) in
                Text(finish.displayName).tag(finish)
            }
        }
        .help("Lit: the hub marks are cut in as glowing channels. Raised: plain hub, marks standing proud. Engraved: unlit, marks laser-cut into the polished hub as dark matte channels (key c cycles).\(renderers)")
        .resettable(profile: \.spinner.hubFinish, model, fanOut: false)
    }

    private var glowRow: some View {
        slider("Glow brightness", \.glowBrightness, range: SpinnerSettings.glowBrightnessRange,
               readout: percent(current.glowBrightness))
            .help("Brightness of the glow rods, motion arcs and lit hub marks. 0% turns the emission off.\(renderers)")
            .resettable(profile: \.spinner.glowBrightness, model, fanOut: false)
    }

    private var roomRow: some View {
        slider("Room light", \.roomLight, range: SpinnerSettings.roomLightRange, readout: percent(current.roomLight))
            .help("Brightness of the room light on the metal (not the glowing parts). RealityKit: key light and environment. Classic shader: its light scale.")
            .resettable(profile: \.spinner.roomLight, model, fanOut: false)
    }

    private var sizeRow: some View {
        slider("Size", \.size, range: SpinnerSettings.sizeRange, readout: percent(current.size))
            .help("Scales the spinner relative to its normal size.\(renderers)")
            .resettable(profile: \.spinner.size, model, fanOut: false)
    }

    private var blurRow: some View {
        slider("Spin blur", \.spinBlur, range: SpinnerSettings.spinBlurRange, readout: percent(current.spinBlur))
            .help("Scales how much a fast-spinning spinner smears. 0% shows a sharp spinner at any speed.\(renderers)")
            .resettable(profile: \.spinner.spinBlur, model, fanOut: false)
    }

    // MARK: - Shadow

    @ViewBuilder private var shadowSection: some View {
        Section("Shadow") {
            darknessRow
            spreadRow
            distanceRow
        }
    }

    private var darknessRow: some View {
        slider("Darkness", \.shadowDarkness, range: SpinnerSettings.shadowDarknessRange,
               readout: percent(current.shadowDarkness))
            .help("How dark the drop shadow is. 0% hides it.\(darknessNote)")
            .resettable(profile: \.spinner.shadowDarkness, model, fanOut: false)
    }

    private var spreadRow: some View {
        slider("Spread", \.shadowSpread, range: SpinnerSettings.shadowSpreadRange, readout: multiple(current.shadowSpread))
            .help("How soft the shadow's edge is.\(renderers)")
            .resettable(profile: \.spinner.shadowSpread, model, fanOut: false)
    }

    private var distanceRow: some View {
        slider("Distance", \.shadowDistance, range: SpinnerSettings.shadowDistanceRange,
               readout: multiple(current.shadowDistance))
            .help("How far the shadow falls from the spinner. 0 puts it directly behind the spinner.\(renderers)")
            .resettable(profile: \.spinner.shadowDistance, model, fanOut: false)
    }

    // MARK: - Sound and music

    @ViewBuilder private var soundSection: some View {
        Section("Sound & Music") {
            humRow
            humVolumeRow
            musicModeRow
            sustainRow
            kickRow
        }
    }

    private var humRow: some View {
        Toggle("Bearing hum", isOn: field(\.humEnabled))
            .help("A quiet bearing hum that follows the spin speed (key u). The hum is only heard when no music is playing: any music activity silences it, and it returns after 6 seconds of silence.")
            .resettable(profile: \.spinner.humEnabled, model, fanOut: false)
    }

    private var humVolumeRow: some View {
        slider("Hum volume", \.humVolume, range: SpinnerSettings.humVolumeRange, readout: percent(current.humVolume))
            .help("Scales the hum's loudness when it is heard (only while no music is playing).")
            .resettable(profile: \.spinner.humVolume, model, fanOut: false)
    }

    private var musicModeRow: some View {
        Picker("Music mode", selection: field(\.musicMode)) {
            ForEach(SpinnerMusicMode.allCases, id: \.self) { (mode: SpinnerMusicMode) in
                Text(mode.displayName).tag(mode)
            }
        }
        .help("How the music acts on the spin (key b). Sustain: loud music lengthens the coast. Kick: bass beats nudge the spinner.\(renderers)")
        .resettable(profile: \.spinner.musicMode, model, fanOut: false)
    }

    private var sustainRow: some View {
        slider("Sustain", \.musicSustain, range: SpinnerSettings.musicSustainRange, readout: percent(current.musicSustain))
            .disabled(!(current.musicMode == .sustain || current.musicMode == .both))
            .help("How much friction loud music removes. Used by the Sustain and Sustain + Kick music modes.")
            .resettable(profile: \.spinner.musicSustain, model, fanOut: false)
    }

    private var kickRow: some View {
        slider("Kick", \.musicKick, range: SpinnerSettings.musicKickRange, readout: radPerSecond(current.musicKick))
            .disabled(!(current.musicMode == .kick || current.musicMode == .both))
            .help("Speed added by a full-strength beat. Used by the Kick and Sustain + Kick music modes.")
            .resettable(profile: \.spinner.musicKick, model, fanOut: false)
    }

    // MARK: - Renderer

    @ViewBuilder private var rendererSection: some View {
        Section("Renderer") {
            rendererRow
            resetOrientationButton
        }
    }

    @ViewBuilder private var orientationSection: some View {
        Section("Orientation") {
            resetOrientationButton
        }
    }

    private var resetOrientationButton: some View {
        Button("Reset orientation") { model.resetSpinnerOrientation() }
            .help("Eases the spinner back to face-on. The 0 key does the same, and flips to the other side when it is already face-on (Option+0 flips about the vertical axis). Orientation is not saved and is shared by the two spinner styles.")
    }

    private var rendererRow: some View {
        Picker("Renderer", selection: field(\.renderer)) {
            ForEach(SpinnerRendererChoice.allCases, id: \.self) { (choice: SpinnerRendererChoice) in
                Text(choice.displayName).tag(choice)
            }
        }
        .disabled(!RealitySpinnerHost.isSupported)
        .help(RealitySpinnerHost.isSupported
              ? "RealityKit is the default; the classic shader stands in while it loads and ignores yaw (key g)."
              : "RealityKit needs macOS 15; the classic shader is used.")
        .resettable(profile: \.spinner.renderer, model, fanOut: false)
    }
}
