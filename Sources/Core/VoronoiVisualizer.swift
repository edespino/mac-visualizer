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

/// `voronoiSeedCount` random seed points (default 75; deterministic from a fixed
/// RNG seed). Three render modes: cells (Voronoi polygons via Delaunay dual),
/// blobs (fragment shader), softCells (vertex emit + post-process blur).
///
/// On `frame.beat`: cell brightness boost `1 + voronoiCpuBeatBoost * beatIntensity`
/// (default 0.3) with a `voronoiCpuBeatHalfLife` half-life (default 100ms).
/// On `useStereoImage == true`: cells with x < 0 use bandsLeft, x ≥ 0 use bandsRight.
///
/// Per-cell tint is `1.0 ± voronoiTintRange` (default 0.1 → 0.9..1.1); the raw
/// RNG factor is baked at build time and the range is applied at emit, so the
/// tint control needs no reseed. `voronoiSeedCount`/`voronoiSeedSpread` changes
/// DO reseed (stateful, restart-from-seed).
///
/// Shape modes (voronoiShapeMode):
///   fixed    — seeds/cells are constant (original behavior).
///   cycle    — reshuffle seeds every `voronoiCyclePeriod`s (default 60) with a fade.
///   drift    — per-seed value-noise drift (`voronoiDriftSpeed`/`voronoiDriftStrength`,
///              defaults 0.15/0.05), re-triangulate every frame.
///   perTrack — reshuffle on actual track change (via AudioFrame.trackId) with a
///              fade-to-black transition. Seed is derived deterministically from the
///              track ID so the same track always produces the same layout.
///
/// Fade transition (cycle + perTrack): fade-out → swap seeds at full black →
/// fade-in, each leg `voronoiFadeDuration`s (default 0.5). The
/// `currentFadeBrightness()` method is read by MetalRenderer to apply the same
/// dimming to the blobs shader path via VoronoiUniforms.fadeBrightness.
public final class VoronoiVisualizer: Visualizer {

    private let baseSeed: UInt64 = 0xCE110155

    // Defaults match VisualizerSettings.defaults so a freshly constructed
    // visualizer needs no rebuild under default settings (byte-identical look).
    private static let defaultSeedCount: Int = 75
    private static let defaultSeedSpread: Float = 0.95

    private var seeds: [SIMD2<Float>] = []
    private var cells: [Delaunay.VoronoiCell] = []
    // Per-cell tint *factors* in 0..1 (raw RNG units); the final tint is computed
    // at emit time as `(1 - tintRange) + factor * (2 * tintRange)`, so the
    // `voronoiTintRange` control needs no reseed and the default (0.1) reproduces
    // the prior `0.9 + factor * 0.2` baked tints exactly.
    private var cellTintFactors: [Float] = []
    private var cellBandIdx: [Int] = []   // bandIdx assignment per cell (matches seeds order)

    // Live structural state driven by settings; reseed when either changes.
    private var currentSeedCount: Int = VoronoiVisualizer.defaultSeedCount
    private var currentSeedSpread: Float = VoronoiVisualizer.defaultSeedSpread
    private var activeSeed: UInt64 = 0xCE110155   // seed basis used for the current layout

    // Cycle state
    private var cycleStartTime: CFTimeInterval = -1
    private var cycleSeedOffset: UInt64 = 0

    // PerTrack state
    private var lastTrackId: String? = nil   // sentinel: never seen yet

    // Fade-to-black transition state
    private enum FadeState {
        case stable
        case fadingOut(progress: Float)   // 0..1, climbing toward 1
        case fadingIn(progress: Float)    // 0..1, climbing toward 1
    }
    private var fadeState: FadeState = .stable
    private var pendingFadeSeed: UInt64 = 0  // seed to install when fade-out completes

    private var beatBoost: Float = 0
    private var lastTimestamp: CFTimeInterval = -1

    public init() {
        rebuildSeeds(seed: baseSeed,
                     count: VoronoiVisualizer.defaultSeedCount,
                     spread: VoronoiVisualizer.defaultSeedSpread)
    }

    // MARK: - Seed building

    private static func buildSeeds(seed: UInt64, count: Int, spread: Float)
        -> (seeds: [SIMD2<Float>], cells: [Delaunay.VoronoiCell], tintFactors: [Float]) {
        var rng = SeededRNG(seed: seed)
        var s: [SIMD2<Float>] = []
        s.reserveCapacity(count)
        for _ in 0..<count {
            s.append(SIMD2<Float>(rng.nextSigned() * spread, rng.nextSigned() * spread))
        }
        let c = Delaunay.voronoiCells(points: s)
        var t: [Float] = []
        t.reserveCapacity(count)
        for _ in 0..<count {
            t.append(rng.nextUnit())   // raw 0..1 factor; tint range applied at emit
        }
        return (s, c, t)
    }

    /// Rebuild the seed set for the given basis seed, count and spread. Updates
    /// the cached structural state so settings-driven reseeds are stateful.
    private func rebuildSeeds(seed: UInt64, count: Int, spread: Float) {
        let v = VoronoiVisualizer.buildSeeds(seed: seed, count: count, spread: spread)
        self.seeds = v.seeds
        self.cells = v.cells
        self.cellTintFactors = v.tintFactors
        self.cellBandIdx = (0..<count).map { $0 }
        self.activeSeed = seed
        self.currentSeedCount = count
        self.currentSeedSpread = spread
    }

    /// Reshuffle to a new basis seed, keeping the current count/spread.
    private func rebuildSeeds(seed: UInt64) {
        rebuildSeeds(seed: seed, count: currentSeedCount, spread: currentSeedSpread)
    }

    // MARK: - makeVertices

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        // Beat decay.
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }

        // Settings-driven tunables (clamped at the read site so persisted/edited
        // values can't break the CPU path). Defaults reproduce the prior literals.
        let fadeDuration = Float(max(1e-4, settings.voronoiFadeDuration))
        let cyclePeriod = CFTimeInterval(max(1e-4, settings.voronoiCyclePeriod))
        let driftSpeed = settings.voronoiDriftSpeed
        let driftStrength = Float(settings.voronoiDriftStrength)

        // Reseed on seed-count / seed-spread change (stateful; positions restart
        // from the current basis seed). Count clamped to 1...capacity.
        let targetCount = max(1, min(kVoronoiSeedCapacity, settings.voronoiSeedCount))
        let targetSpread = Float(settings.voronoiSeedSpread)
        if targetCount != currentSeedCount || targetSpread != currentSeedSpread {
            rebuildSeeds(seed: activeSeed, count: targetCount, spread: targetSpread)
        }

        // Advance any in-progress fade transition.
        switch fadeState {
        case .stable:
            break
        case .fadingOut(var p):
            p += realDt / fadeDuration
            if p >= 1.0 {
                // Swap seeds at the moment of full black.
                rebuildSeeds(seed: pendingFadeSeed)
                fadeState = .fadingIn(progress: 0)
            } else {
                fadeState = .fadingOut(progress: p)
            }
        case .fadingIn(var p):
            p += realDt / fadeDuration
            if p >= 1.0 {
                fadeState = .stable
            } else {
                fadeState = .fadingIn(progress: p)
            }
        }

        // Shape evolution per voronoiShapeMode
        switch settings.current.voronoiShapeMode {
        case .fixed:
            break   // no-op; seeds + cells stay as-initialized
        case .cycle:
            if cycleStartTime < 0 { cycleStartTime = frame.timestamp }
            if frame.timestamp - cycleStartTime >= cyclePeriod, case .stable = fadeState {
                cycleSeedOffset &+= 0x9E3779B97F4A7C15
                pendingFadeSeed = baseSeed &+ cycleSeedOffset
                // Consume the current dt immediately so the fade is visible this frame.
                fadeState = .fadingOut(progress: min(realDt / fadeDuration, 0.99))
                cycleStartTime = frame.timestamp
            }
        case .drift:
            // Per-seed value-noise-driven drift; re-triangulate every frame.
            for i in 0..<seeds.count {
                let nx = VoronoiVisualizer.value2D(
                    x: Double(seeds[i].x) + frame.timestamp * driftSpeed,
                    y: Double(seeds[i].y),
                    seed: UInt64(truncatingIfNeeded: Int64(i) &* Int64(bitPattern: 0x9E3779B97F4A7C15))
                )
                let ny = VoronoiVisualizer.value2D(
                    x: Double(seeds[i].x),
                    y: Double(seeds[i].y) + frame.timestamp * driftSpeed,
                    seed: UInt64(truncatingIfNeeded: Int64(i) &* Int64(bitPattern: 0xBF58476D1CE4E5B9))
                )
                let drift = SIMD2<Float>((Float(nx) - 0.5) * driftStrength, (Float(ny) - 0.5) * driftStrength)
                seeds[i] += drift * realDt
                // Soft wrap.
                if seeds[i].x > 0.95  { seeds[i].x -= 1.9 }
                if seeds[i].x < -0.95 { seeds[i].x += 1.9 }
                if seeds[i].y > 0.95  { seeds[i].y -= 1.9 }
                if seeds[i].y < -0.95 { seeds[i].y += 1.9 }
            }
            cells = Delaunay.voronoiCells(points: seeds)
        case .perTrack:
            // Detect actual track changes via AudioFrame.trackId.
            // On first call lastTrackId is nil (sentinel); we record the ID without
            // triggering a transition so the initial render is not faded.
            let currentId = frame.trackId
            if currentId != lastTrackId {
                let wasNeverSeen = lastTrackId == nil
                lastTrackId = currentId
                if !wasNeverSeen, let id = currentId {
                    // Derive a deterministic seed from the track ID so the same
                    // track always maps to the same layout (reproducible).
                    // Guard against a mid-fade track change — defer until stable.
                    if case .stable = fadeState {
                        let hash = UInt64(bitPattern: Int64(id.hashValue))
                        pendingFadeSeed = baseSeed &+ hash
                        // Consume the current dt immediately so the fade is visible this frame.
                        fadeState = .fadingOut(progress: min(realDt / fadeDuration, 0.99))
                    }
                }
            }
        }

        lastTimestamp = frame.timestamp
        let beatHalfLife = Float(max(1e-4, settings.voronoiCpuBeatHalfLife))
        beatBoost *= powf(0.5, realDt / beatHalfLife)
        if frame.beat {
            beatBoost = max(beatBoost, Float(settings.voronoiCpuBeatBoost) * max(0, min(1, frame.beatIntensity)))
        }

        switch settings.current.voronoiRenderMode {
        case .cells:
            return emitCells(frame: frame, settings: settings, palette: palette, aspect: aspect)
        case .blobs:
            // Fragment-shader-driven; visualizer emits nothing. Renderer routes
            // via VisualizerStyle.customShader(settings:) → .voronoiBlobs (wired in Task 9).
            return []
        case .softCells:
            return emitCells(frame: frame, settings: settings, palette: palette, aspect: aspect)   // same vertices; blur applied by renderer (Task 10)
        }
    }

    // MARK: - Fade brightness

    /// Returns the current fade multiplier (1 = fully visible, 0 = full black).
    /// Called by MetalRenderer to propagate the fade to the blobs shader path
    /// via `VoronoiUniforms.fadeBrightness`.
    public func currentFadeBrightness() -> Float {
        switch fadeState {
        case .stable:          return 1.0
        case .fadingOut(let p): return 1.0 - p   // 1 → 0
        case .fadingIn(let p):  return p           // 0 → 1
        }
    }

    // MARK: - Emit cells

    private func emitCells(frame: AudioFrame, settings: VisualizerSettings,
                           palette: ColorPalette, aspect: Float) -> [BarVertex] {
        guard !frame.bands.isEmpty else { return [] }
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        let fadeBrightness = currentFadeBrightness()
        // Per-cell tint half-range: tint = 1.0 ± tintRange (default 0.1 → 0.9..1.1).
        let tintRange = Float(settings.voronoiTintRange)

        var verts: [BarVertex] = []
        verts.reserveCapacity(currentSeedCount * 18)   // ~6 triangles average per cell

        for cell in cells {
            guard cell.vertices.count >= 3 else { continue }
            let seed = seeds[cell.seedIndex]
            // Pick band source per cell based on stereo + cell X position.
            let level: Float
            if settings.useStereoImage {
                let leftHalf = seed.x < 0
                let source = leftHalf ? frame.bandsLeft : frame.bandsRight
                let bi = cellBandIdx[cell.seedIndex] % max(source.count, 1)
                level = source.isEmpty ? 0 : source[bi]
            } else {
                let bi = cellBandIdx[cell.seedIndex] % frame.bands.count
                level = frame.bands[bi]
            }
            let clampedLevel = min(max(level, 0), 1)
            let tint = (1.0 - tintRange) + cellTintFactors[cell.seedIndex] * (2 * tintRange)
            let beatMul = 1 + beatBoost
            let c = palette.sample(at: clampedLevel)
            let color = SIMD4<Float>(
                min(1, c.r * tint * beatMul * fadeBrightness),
                min(1, c.g * tint * beatMul * fadeBrightness),
                min(1, c.b * tint * beatMul * fadeBrightness),
                1
            )
            // Triangle fan from the seed to each cell vertex pair (i, i+1).
            // Clamp cell polygon circumcenters to ±2.5 (pre-scale) so that
            // super-triangle adjacency circumcenters (which can lie far outside
            // the seed domain) don't produce off-screen geometry. The composite
            // pass clips anything remaining outside NDC, so this is just a
            // sanity guard.
            let clampBound: Float = 2.5
            for i in 0..<cell.vertices.count {
                let next = (i + 1) % cell.vertices.count
                let v0 = cell.vertices[i], v1 = cell.vertices[next]
                let cx0 = min(max(v0.x, -clampBound), clampBound)
                let cy0 = min(max(v0.y, -clampBound), clampBound)
                let cx1 = min(max(v1.x, -clampBound), clampBound)
                let cy1 = min(max(v1.y, -clampBound), clampBound)
                let p0 = SIMD4<Float>(seed.x * sx, seed.y * sy, 0, 1)
                let p1 = SIMD4<Float>(cx0 * sx, cy0 * sy, 0, 1)
                let p2 = SIMD4<Float>(cx1 * sx, cy1 * sy, 0, 1)
                verts.append(BarVertex(position: p0, color: color))
                verts.append(BarVertex(position: p1, color: color))
                verts.append(BarVertex(position: p2, color: color))
            }
        }
        return verts
    }

    // MARK: - 2D value noise (inline; same algorithm as LavaLampVisualizer.value2D)

    static func value2D(x: Double, y: Double, seed: UInt64) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Double(xi), yf = y - Double(yi)
        func hash(_ ix: Int, _ iy: Int) -> Double {
            var h = UInt64(bitPattern: Int64(ix &* 374761393 &+ iy &* 668265263)) &+ seed
            h = (h ^ (h >> 13)) &* 1274126177
            return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
        }
        let v00 = hash(xi, yi)
        let v10 = hash(xi + 1, yi)
        let v01 = hash(xi, yi + 1)
        let v11 = hash(xi + 1, yi + 1)
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)
        let x0 = v00 + (v10 - v00) * u
        let x1 = v01 + (v11 - v01) * u
        return x0 + (x1 - x0) * v
    }
}