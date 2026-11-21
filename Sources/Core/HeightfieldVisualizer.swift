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

/// N×N grid of vertices in 3D (default 16×16). Each vertex's Z is driven by an
/// audio band (indexed by column). Camera: orthographic with a tilt for a
/// perspective feel. Two render modes:
///   - `.wireframe`: horizontal + vertical line segments
///   - `.solid`:     pre-shaded filled triangles with flat lighting
///
/// When `useStereoImage == true`: left columns driven by bandsLeft, right by
/// bandsRight. On `frame.beat`: Z-amplitude pulse `1 + beatBoost * beatIntensity`
/// with a configurable half-life. Stateful — beat boost decays across frames.
///
/// Every visual tunable is read fresh per frame from `VisualizerSettings`
/// (`heightfield*` fields) with clamps applied at the read site so a
/// persisted/edited value can never break geometry. Defaults reproduce the
/// prior hardcoded look byte-identically for BOTH render modes.
///
/// Z displacement is row-weighted (back rows = full height, front row = zero)
/// and added to the projected y with a positive sign so that taller cells appear
/// higher on screen. This makes beat boosts and stereo asymmetry directly visible
/// as y-range expansion.
public final class HeightfieldVisualizer: Visualizer {

    // Internal robustness, not a visual control: cap the per-frame dt so a
    // long pause (window occluded, app backgrounded) can't apply one giant beat
    // decay step. Left hardcoded.
    private let deltaTimeCap: CFTimeInterval = 0.1

    private var beatBoost: Float = 0
    private var lastTimestamp: CFTimeInterval = -1

    public init() {}

    /// All per-frame tunables resolved from settings, with clamps applied.
    private struct Resolved {
        var gridSize: Int
        var tiltAngle: Float
        var zScale: Float
        var lineHalfThickness: Float
        var lightDir: SIMD3<Float>
        var ambient: Float
        var verticalFit: Float
        var verticalCenter: Float
        var beatBoostCoeff: Float
        var beatHalfLife: Float
        var xExtent: Float
        var yExtent: Float
        var opacity: Float
    }

    private func resolve(_ settings: VisualizerSettings) -> Resolved {
        // Light direction: clamp each component to -1...1 (matching the UI range
        // so a persisted/edited value can't bypass it) BEFORE the zero-guard +
        // normalize. A (near-)zero vector can't be normalized, so fall back to the
        // default direction (which normalizes to the same value the prior
        // hardcoded path used). Clamps are inert at the default (0.5, 0.7, 0.5).
        var lightDir = SIMD3<Float>(min(1, max(-1, Float(settings.heightfieldLightX))),
                                    min(1, max(-1, Float(settings.heightfieldLightY))),
                                    min(1, max(-1, Float(settings.heightfieldLightZ))))
        if simd_length(lightDir) < 1e-6 {
            lightDir = SIMD3<Float>(0.5, 0.7, 0.5)
        }
        lightDir = simd_normalize(lightDir)

        return Resolved(
            gridSize: min(64, max(2, settings.heightfieldGridSize)),
            tiltAngle: min(1.5, max(0, Float(settings.heightfieldTiltAngle))),
            // Positive floor: zScale also divides for color levels.
            zScale: max(Float(settings.heightfieldZScale), 1e-3),
            lineHalfThickness: max(Float(settings.heightfieldLineHalfThickness), 0),
            lightDir: lightDir,
            ambient: min(max(Float(settings.heightfieldAmbientLight), 0), 1),
            verticalFit: min(1.2, max(0.5, Float(settings.heightfieldVerticalFit))),
            verticalCenter: min(0.5, max(-0.5, Float(settings.heightfieldVerticalCenter))),
            beatBoostCoeff: min(3, max(0, Float(settings.heightfieldBeatBoost))),
            // Half-life divides in the decay exponent, so keep it strictly positive.
            beatHalfLife: max(Float(settings.heightfieldBeatHalfLife), 1e-4),
            xExtent: max(Float(settings.heightfieldXExtent), 1e-4),
            yExtent: max(Float(settings.heightfieldYExtent), 1e-4),
            opacity: min(max(Float(settings.heightfieldOpacity), 0), 1)
        )
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        guard !frame.bands.isEmpty else { return [] }

        var r = resolve(settings)
        let gridSize = r.gridSize

        // Auto-placement, derived from the live aspect so it survives a window
        // resize. Both are closed-form here because the projection is affine in
        // the grid coordinates:
        //   x_screen = nx * aspectSx,  nx ∈ [-xExtent, xExtent]
        //     → filling the width means xExtent = 1 / aspectSx.
        //   y_screen = (ny*cosT + z*sinT - verticalCenter) * verticalFit * aspectSy
        //     → at rest (z = 0) the lowest row is ny = -yExtent, so pinning it to
        //       -1 means verticalCenter = 1/(verticalFit*aspectSy) - yExtent*cosT.
        //       (verticalCenter is SUBTRACTED in the projection, so larger values
        //       move the grid DOWN.)
        // Fitted to the RESTING grid, matching Wireframe: audio and beat lift the
        // back rows past the top edge rather than leaving the grid inset. The
        // computed center bypasses resolve()'s -0.5...0.5 manual clamp (which is a
        // UI-range guard, not a geometric one) but stays bounded well inside NDC.
        var autoAspectSx: Float = 1, autoAspectSy: Float = 1
        if aspect >= 1 { autoAspectSx = 1 / aspect } else { autoAspectSy = aspect }
        if settings.heightfieldFillWidth {
            r.xExtent = 1 / max(autoAspectSx, 1e-4)
        }
        if settings.heightfieldAnchorBottom {
            let cosTilt = cos(r.tiltAngle)
            r.verticalCenter = 1 / (r.verticalFit * max(autoAspectSy, 1e-4)) - r.yExtent * cosTilt
        }

        // Beat-boost decay.
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), deltaTimeCap))
        }
        lastTimestamp = frame.timestamp
        beatBoost *= powf(0.5, realDt / r.beatHalfLife)
        if frame.beat {
            beatBoost = max(beatBoost, r.beatBoostCoeff * max(0, min(1, frame.beatIntensity)))
        }
        let zMul: Float = 1 + beatBoost

        // Build Z-displaced grid in 3D. The working buffers are allocated fresh
        // per frame at the resolved grid size, so a gridSize change between
        // frames is handled cleanly with no stale-buffer state to reconcile.
        // rowFactor: 0 at front row → 1 at back row (the "receding grid" look:
        // back rows show full Z height, front row is flat). rowFactor means beat
        // (via zMul) scales the non-zero rows, extending the screen-y range.
        var grid = [[SIMD3<Float>]](repeating: [SIMD3<Float>](repeating: .zero, count: gridSize), count: gridSize)
        for row in 0..<gridSize {
            let rowFactor = Float(row) / Float(gridSize - 1)   // 0..1
            for col in 0..<gridSize {
                // extent 1.0 reproduces the prior -1..1 mapping exactly.
                let nx = (Float(col) / Float(gridSize - 1) * 2 - 1) * r.xExtent
                let ny = (Float(row) / Float(gridSize - 1) * 2 - 1) * r.yExtent
                // Choose band source per column.
                let level: Float
                if settings.useStereoImage {
                    let leftHalf = col < gridSize / 2
                    let source = leftHalf ? frame.bandsLeft : frame.bandsRight
                    let bandIdx = source.isEmpty ? 0 : (col * source.count) / gridSize
                    level = source.isEmpty ? 0 : source[min(bandIdx, source.count - 1)]
                } else {
                    let bandIdx = (col * frame.bands.count) / gridSize
                    level = frame.bands[min(bandIdx, frame.bands.count - 1)]
                }
                // z is row-weighted: back rows show full displacement, front row is flat.
                let z = min(max(level, 0), 1) * r.zScale * zMul * rowFactor
                grid[row][col] = SIMD3<Float>(nx, ny, z)
            }
        }

        // Project to 2D: tilt the grid so the back rows recede.
        // z is added positively to projected y so taller cells appear higher on screen.
        let cosT = cos(r.tiltAngle), sinT = sin(r.tiltAngle)
        var aspectSx: Float = 1, aspectSy: Float = 1
        if aspect >= 1 { aspectSx = 1 / aspect } else { aspectSy = aspect }
        func project(_ p3: SIMD3<Float>) -> SIMD2<Float> {
            // Back rows (large ny) recede upward; z lifts cells further.
            let yt = (p3.y * cosT + p3.z * sinT - r.verticalCenter) * r.verticalFit
            return SIMD2<Float>(p3.x * aspectSx, yt * aspectSy)
        }
        var grid2 = [[SIMD2<Float>]](repeating: [SIMD2<Float>](repeating: .zero, count: gridSize), count: gridSize)
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                grid2[row][col] = project(grid[row][col])
            }
        }

        switch settings.current.heightfieldRenderMode {
        case .wireframe:
            return emitWireframe(grid: grid, grid2: grid2, palette: palette, r: r)
        case .solid:
            return emitSolid(grid: grid, palette: palette, aspectSx: aspectSx, aspectSy: aspectSy, r: r)
        }
    }

    private func emitWireframe(grid: [[SIMD3<Float>]], grid2: [[SIMD2<Float>]], palette: ColorPalette, r: Resolved) -> [BarVertex] {
        let gridSize = r.gridSize
        var verts: [BarVertex] = []
        verts.reserveCapacity(gridSize * (gridSize - 1) * 2 * 6)   // rows + cols, each a quad
        for row in 0..<gridSize {
            for col in 0..<(gridSize - 1) {
                let p0 = grid2[row][col], p1 = grid2[row][col + 1]
                appendLineQuad(&verts, p0: p0, p1: p1,
                               level0: grid[row][col].z / r.zScale, level1: grid[row][col + 1].z / r.zScale,
                               palette: palette, r: r)
            }
        }
        for col in 0..<gridSize {
            for row in 0..<(gridSize - 1) {
                let p0 = grid2[row][col], p1 = grid2[row + 1][col]
                appendLineQuad(&verts, p0: p0, p1: p1,
                               level0: grid[row][col].z / r.zScale, level1: grid[row + 1][col].z / r.zScale,
                               palette: palette, r: r)
            }
        }
        return verts
    }

    private func emitSolid(grid: [[SIMD3<Float>]], palette: ColorPalette, aspectSx: Float, aspectSy: Float, r: Resolved) -> [BarVertex] {
        let gridSize = r.gridSize
        var verts: [BarVertex] = []
        verts.reserveCapacity((gridSize - 1) * (gridSize - 1) * 6)
        for row in 0..<(gridSize - 1) {
            for col in 0..<(gridSize - 1) {
                let p00 = grid[row][col], p10 = grid[row][col + 1], p01 = grid[row + 1][col], p11 = grid[row + 1][col + 1]
                // Triangle 1: (p00, p10, p11). Triangle 2: (p00, p11, p01).
                emitShadedTriangle(&verts, a: p00, b: p10, c: p11, palette: palette, aspectSx: aspectSx, aspectSy: aspectSy, r: r)
                emitShadedTriangle(&verts, a: p00, b: p11, c: p01, palette: palette, aspectSx: aspectSx, aspectSy: aspectSy, r: r)
            }
        }
        return verts
    }

    private func emitShadedTriangle(_ verts: inout [BarVertex], a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>, palette: ColorPalette, aspectSx: Float, aspectSy: Float, r: Resolved) {
        let n = simd_normalize(simd_cross(b - a, c - a))
        let light = max(r.ambient, simd_dot(n, r.lightDir))
        let avgZ = (a.z + b.z + c.z) / 3
        // Normalize level against maximum possible z (zScale * zMul * rowFactor could exceed zScale).
        let level = min(max(avgZ / r.zScale, 0), 1)
        let baseColor = palette.sample(at: level)
        let color = SIMD4<Float>(baseColor.r * light, baseColor.g * light, baseColor.b * light, r.opacity)
        let cosT = cos(r.tiltAngle), sinT = sin(r.tiltAngle)
        func proj(_ p: SIMD3<Float>) -> SIMD2<Float> {
            let yt = (p.y * cosT + p.z * sinT - r.verticalCenter) * r.verticalFit
            return SIMD2<Float>(p.x * aspectSx, yt * aspectSy)
        }
        let pa = proj(a), pb = proj(b), pc = proj(c)
        verts.append(BarVertex(position: SIMD4<Float>(pa.x, pa.y, 0, 1), color: color))
        verts.append(BarVertex(position: SIMD4<Float>(pb.x, pb.y, 0, 1), color: color))
        verts.append(BarVertex(position: SIMD4<Float>(pc.x, pc.y, 0, 1), color: color))
    }

    private func appendLineQuad(_ verts: inout [BarVertex], p0: SIMD2<Float>, p1: SIMD2<Float>, level0: Float, level1: Float, palette: ColorPalette, r: Resolved) {
        // Build a thin quad perpendicular to (p1 - p0).
        var dir = p1 - p0
        let len = simd_length(dir)
        guard len > 1e-5 else { return }
        dir /= len
        let perp = SIMD2<Float>(-dir.y, dir.x) * r.lineHalfThickness
        let c0 = palette.sample(at: max(0, min(1, level0)))
        let c1 = palette.sample(at: max(0, min(1, level1)))
        let color0 = SIMD4<Float>(c0.r, c0.g, c0.b, r.opacity)
        let color1 = SIMD4<Float>(c1.r, c1.g, c1.b, r.opacity)
        let a = p0 - perp, b = p0 + perp, c = p1 + perp, d = p1 - perp
        verts.append(BarVertex(position: SIMD4<Float>(a.x, a.y, 0, 1), color: color0))
        verts.append(BarVertex(position: SIMD4<Float>(b.x, b.y, 0, 1), color: color0))
        verts.append(BarVertex(position: SIMD4<Float>(d.x, d.y, 0, 1), color: color1))
        verts.append(BarVertex(position: SIMD4<Float>(b.x, b.y, 0, 1), color: color0))
        verts.append(BarVertex(position: SIMD4<Float>(c.x, c.y, 0, 1), color: color1))
        verts.append(BarVertex(position: SIMD4<Float>(d.x, d.y, 0, 1), color: color1))
    }
}
