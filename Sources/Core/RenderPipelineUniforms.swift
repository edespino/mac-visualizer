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

// Pipeline-level POD uniforms shared by every fullscreen shader pass. Field
// order/types MUST match the same-named structs in Shaders.metal; fixed-size
// tuples stand in for arrays (a Swift Array inside a struct does NOT survive
// `setFragmentBytes`). They live in Core — following the VoronoiUniforms /
// LavaLampUniforms pattern — so the pure builders are unit-testable
// (RenderPipelineUniformsTests pins strides, offsets, and builder behavior);
// the renderer is a thin caller that supplies the clock.

/// Bound at fragment buffer 0 of `composite_fs` (bloom/vignette/kaleidoscope
/// composite) and, for the direct no-glow geometry path, to `fs_main` /
/// `fs_round`. 6 × 4-byte fields, tightly packed — stride 24.
public struct CompositeUniforms {
    public var intensity: Float
    public var vignetteAmount: Float
    public var time: Float
    public var kaleidoscopeFolds: Int32
    public var perPixelAlphaMode: Float
    public var brightness: Float

    public init(intensity: Float, vignetteAmount: Float, time: Float,
                kaleidoscopeFolds: Int32, perPixelAlphaMode: Float,
                brightness: Float = 1) {
        self.intensity = intensity
        self.vignetteAmount = vignetteAmount
        self.time = time
        self.kaleidoscopeFolds = kaleidoscopeFolds
        self.perPixelAlphaMode = perPixelAlphaMode
        self.brightness = brightness
    }
}

/// Pure mapping from settings to the composite uniform. `kaleidoscopeFolds`
/// is clamped to the shader's 0...12 domain (0 = off) so a persisted or
/// hand-edited value can't drive the fold math out of range. `time` is
/// supplied by the caller (the renderer's frame clock) to keep this testable.
public func makeCompositeUniforms(intensity: Float,
                                  settings: VisualizerSettings,
                                  time: Float) -> CompositeUniforms {
    CompositeUniforms(
        intensity: intensity,
        vignetteAmount: settings.vignetteAmount,
        time: time,
        kaleidoscopeFolds: Int32(max(0, min(12, settings.kaleidoscopeFolds))),
        perPixelAlphaMode: settings.windowTransparencyMode == .perPixelAlpha ? 1.0 : 0.0,
        // Non-finite persisted values fall back to full brightness rather than
        // blanking the screen.
        brightness: effectiveOutputBrightness(settings)
    )
}

/// Bound at fragment buffer 0 of every shader-driven visualizer: the frame
/// clock, overall energy, and the 16-bucket band reduction. Stride 72.
public struct ShaderInputs {
    public var time: Float = 0
    public var energy: Float = 0
    public var bands: (Float, Float, Float, Float, Float, Float, Float, Float,
                       Float, Float, Float, Float, Float, Float, Float, Float) =
        (0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0)

    public init() {}
}

/// Pure reduction of a frame's band array into the fixed 16 shader buckets:
/// each bucket is the mean of its band range; when there are fewer bands than
/// buckets the nearest band fills in, and no bands at all leaves zeros.
public func makeShaderInputs(frame: AudioFrame, time: Float) -> ShaderInputs {
    var inputs = ShaderInputs()
    inputs.time = time
    inputs.energy = frame.rms
    let bandCount = frame.bands.count
    var arr = [Float](repeating: 0, count: 16)
    if bandCount > 0 {
        for i in 0..<16 {
            let lo = (i * bandCount) / 16
            let hi = ((i + 1) * bandCount) / 16
            var sum: Float = 0
            if hi > lo {
                for k in lo..<hi { sum += frame.bands[k] }
                arr[i] = sum / Float(hi - lo)
            } else {
                arr[i] = frame.bands[min(lo, bandCount - 1)]
            }
        }
    }
    inputs.bands = (arr[0],  arr[1],  arr[2],  arr[3],  arr[4],  arr[5],  arr[6],  arr[7],
                    arr[8],  arr[9],  arr[10], arr[11], arr[12], arr[13], arr[14], arr[15])
    return inputs
}

/// One palette stop as the shader sees it: packed RGB + normalized position.
public struct PaletteStopUniform {
    public var r: Float = 0
    public var g: Float = 0
    public var b: Float = 0
    public var position: Float = 0

    public init() {}
    public init(r: Float, g: Float, b: Float, position: Float) {
        self.r = r; self.g = g; self.b = b; self.position = position
    }
}

/// Bound at fragment buffer 1 of every shader-driven visualizer: up to 8
/// palette stops plus the active count. Stride 132.
public struct PaletteUniform {
    public var stops: (PaletteStopUniform, PaletteStopUniform, PaletteStopUniform, PaletteStopUniform,
                       PaletteStopUniform, PaletteStopUniform, PaletteStopUniform, PaletteStopUniform) =
        (.init(), .init(), .init(), .init(), .init(), .init(), .init(), .init())
    public var stopCount: Int32 = 0

    public init() {}
}

/// Pure mapping from a palette to its shader uniform: the first 8 stops copy
/// through with evenly distributed positions (matching the Swift
/// `ColorPalette.sample` semantics the shader mirrors).
public func makePaletteUniform(from palette: ColorPalette) -> PaletteUniform {
    var u = PaletteUniform()
    let n = min(palette.stops.count, 8)
    u.stopCount = Int32(n)
    var arr = [PaletteStopUniform](repeating: .init(), count: 8)
    for i in 0..<n {
        let c = palette.stops[i]
        arr[i] = PaletteStopUniform(r: c.r, g: c.g, b: c.b,
                                    position: Float(i) / Float(max(n - 1, 1)))
    }
    u.stops = (arr[0], arr[1], arr[2], arr[3], arr[4], arr[5], arr[6], arr[7])
    return u
}

/// Named-palette convenience: unknown names bind the fallback palette.
public func makePaletteUniform(named name: String) -> PaletteUniform {
    makePaletteUniform(from: ColorPalette.preset(named: name) ?? .fallback)
}

/// The clamped global dimmer: 0...1, falling back to full brightness for a
/// non-finite persisted value. Shared by `makeCompositeUniforms` and the direct
/// no-glow geometry path so both apply exactly the same factor.
public func effectiveOutputBrightness(_ settings: VisualizerSettings) -> Float {
    let b = Float(settings.outputBrightness)
    return b.isFinite ? min(1, max(0, b)) : 1
}
