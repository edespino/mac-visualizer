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
import simd
import QuartzCore

/// A full-frame color flash driven by detected beats. On each `frame.beat == true`
/// onset the flash intensity jumps to `frame.beatIntensity` (0…1) and a beat counter
/// advances, picking the next palette color so successive beats flash different
/// colors. Between beats the flash decays toward 0 using WALL-CLOCK time (the frame
/// timestamp delta), so the decay rate is frame-rate independent. When idle the
/// quad settles to a dim near-black background.
///
/// Stateful — keep one instance alive across frames (the renderer caches it).
/// Emits a single full-screen quad (two triangles, 6 vertices) covering clip
/// space [-1, 1]^2.
public final class BeatCounterVisualizer: Visualizer {
    /// Time for the flash to fade to half its value, in seconds (wall-clock).
    private let halfLife: Float = 0.22
    /// Resting brightness when no recent beat — dim, not pure black.
    private let ambient: Float = 0.02

    private var flash: Float = 0
    private var beatCount: Int = 0
    private var lastTimestamp: CFTimeInterval = -1

    public init() {}

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        // Wall-clock delta (clamped), independent of particleSpeed so the flash
        // decays at a real-time rate regardless of physics tuning.
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp

        // Exponential decay toward 0 with a fixed half-life.
        if realDt > 0 && flash > 0 {
            flash *= powf(0.5, realDt / halfLife)
            if flash < 1e-4 { flash = 0 }
        }

        // On a beat, advance the counter and re-arm the flash from the onset's
        // intensity (take the max so a fresh beat never dims a brighter one).
        if frame.beat {
            beatCount &+= 1
            flash = max(flash, max(0, min(1, frame.beatIntensity)))
        }

        // Pick the palette color for the current beat. Stepping by beat index
        // through the stops makes successive beats flash distinct colors.
        let stopCount = palette.stops.count
        let pos: Float = stopCount > 1
            ? Float(((beatCount % stopCount) + stopCount) % stopCount) / Float(stopCount - 1)
            : 0
        let c = palette.sample(at: pos)

        // Blend from the ambient background up to the full palette color by flash.
        let r = ambient + (c.r - ambient) * flash
        let g = ambient + (c.g - ambient) * flash
        let b = ambient + (c.b - ambient) * flash
        let color = SIMD4<Float>(max(0, r), max(0, g), max(0, b), 1)

        let bl = BarVertex(position: SIMD4(-1, -1, 0, 1), color: color)
        let br = BarVertex(position: SIMD4( 1, -1, 0, 1), color: color)
        let tl = BarVertex(position: SIMD4(-1,  1, 0, 1), color: color)
        let tr = BarVertex(position: SIMD4( 1,  1, 0, 1), color: color)
        return [bl, br, tl, br, tr, tl]
    }
}
