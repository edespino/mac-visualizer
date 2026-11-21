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

/// Returns `v` if it is finite, otherwise `fallback`. Applied to every user-tunable
/// float BEFORE clamping: Swift's `min`/`max` propagate NaN (`max(.nan, lo) == .nan`),
/// so a persisted/edited non-finite value would otherwise survive the clamp and poison
/// particle state (sizes, velocities, the beat boost). Falling back to the field's
/// default keeps the read-site clamps total.
private func finiteOr(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }

/// A bass-reactive starfield: particles drift, decay toward a baseline, and on bass
/// beats pulse brighter/larger and surge outward; off-screen particles respawn near
/// center. Stateful — keep one instance alive across frames (the renderer caches it).
public final class ParticleVisualizer: Visualizer {
    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var size: Float
        var brightness: Float
        var colorPos: Float
    }

    private var particles: [Particle]
    private var rng: SeededRNG
    private var lastTimestamp: CFTimeInterval = -1
    private var beatBoost: Float = 0   // decays toward 0 each frame; pulsed by frame.beat
    /// Running average of the bass level (-1 until the first frame), for the
    /// adaptive trigger.
    private var bassAverage: Float = -1
    private static let adaptiveAverageSeconds: Float = 1.0   // averaging time constant
    private static let adaptiveRatio: Float = 1.15           // beat must exceed average by 15%
    private static let adaptiveNoiseFloor: Float = 0.08      // ignore flicker near silence

    /// `count` is accepted for source compatibility (the factory and tests construct the
    /// visualizer without settings), but the persistent field is built lazily on the
    /// first frame and its capacity is governed by `settings.particlesMaxParticles`
    /// thereafter (mirror Fountain/Fireworks). The field starts empty so the first frame
    /// reconciles it up to the (clamped) capacity using the live settings.
    public init(count: Int = 200, seed: UInt64 = 0xC0FFEE) {
        _ = count
        self.particles = []
        self.rng = SeededRNG(seed: seed)
    }

    /// Builds one fresh starfield particle using the instance RNG. The draw order
    /// (posX, posY, velX, velY, brightness) and value formulas match the original
    /// hardcoded init, so at default settings the lazily-built field is bit-identical
    /// to the previous eager init.
    private func spawnParticle(index: Int, total: Int, initVelScale: Float,
                               baseSize: Float, baseBrightness: Float,
                               brightnessJitter: Float) -> Particle {
        Particle(position: SIMD2(rng.nextSigned(), rng.nextSigned()),
                 velocity: SIMD2(rng.nextSigned() * initVelScale, rng.nextSigned() * initVelScale),
                 size: baseSize,
                 brightness: baseBrightness + brightnessJitter * rng.nextUnit(),
                 colorPos: Float(index) / Float(max(total - 1, 1)))
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        // Read user-tunable fields with read-site clamps so persisted/edited JSON can't
        // break the particle state. dt cap 0.1, normalize epsilon 0.0001, and the
        // 6-verts-per-particle topology stay hardcoded — they are safety/structure, not
        // controls. Defaults reproduce today's look bit-exact (see the seeded golden).
        // finiteOr(...) drops a persisted/edited NaN/±inf back to the field default
        // BEFORE clamping, because Swift's min/max propagate NaN. lowBandPercent does its
        // own finite handling inside computeBass and is read there.
        let d = VisualizerSettings.defaults
        let target = max(1, min(4000, settings.particlesMaxParticles))
        let initVelScale = Float(finiteOr(settings.particlesInitialVelocityScale, d.particlesInitialVelocityScale))
        let respawnVelScale = Float(finiteOr(settings.particlesRespawnVelocityScale, d.particlesRespawnVelocityScale))
        let baseSize = Float(max(0, finiteOr(settings.particlesBaseSize, d.particlesBaseSize)))
        let baseBrightness = Float(min(max(finiteOr(settings.particlesBaseBrightness, d.particlesBaseBrightness), 0), 1))
        let brightnessJitter = Float(max(0, finiteOr(settings.particlesBrightnessJitter, d.particlesBrightnessJitter)))
        let bassThreshold = Float(finiteOr(settings.particlesBassThreshold, d.particlesBassThreshold))
        let velocityDamping = Float(min(max(finiteOr(settings.particlesVelocityDamping, d.particlesVelocityDamping), 0), 1))
        let returnLerpRate = Float(max(0, finiteOr(settings.particlesReturnLerpRate, d.particlesReturnLerpRate)))
        let beatHalfLife = Float(max(finiteOr(settings.particlesBeatHalfLife, d.particlesBeatHalfLife), 1e-6))   // > 0
        let beatPulseScale = Float(finiteOr(settings.particlesBeatPulseScale, d.particlesBeatPulseScale))
        let bassImpulse = Float(finiteOr(settings.particlesBassImpulse, d.particlesBassImpulse))
        let bassBrightnessGain = Float(finiteOr(settings.particlesBassBrightnessGain, d.particlesBassBrightnessGain))
        let brightnessCap = Float(max(0, finiteOr(settings.particlesBrightnessCap, d.particlesBrightnessCap)))
        let bassSizeGain = Float(finiteOr(settings.particlesBassSizeGain, d.particlesBassSizeGain))
        let sizeCapMultiplier = Float(max(0, finiteOr(settings.particlesSizeCapMultiplier, d.particlesSizeCapMultiplier)))
        let respawnBound = Float(max(finiteOr(settings.particlesRespawnOffscreenBound, d.particlesRespawnOffscreenBound), 1e-6))   // > 0
        let respawnCenterHalfRange = Float(max(0, finiteOr(settings.particlesRespawnCenterHalfRange, d.particlesRespawnCenterHalfRange)))

        // Stateful capacity reconciliation (mirror Fountain/Fireworks): the persistent
        // field tracks the clamped capacity. Growing keeps existing particles and appends
        // freshly-seeded ones; shrinking drops the tail. The first frame grows from an
        // empty field, which is the lazy initial build. The 0..<particles.count loop
        // below stays valid for any capacity (no wrap index to clamp).
        if particles.count != target {
            if target < particles.count {
                particles.removeLast(particles.count - target)
            } else {
                let oldCount = particles.count
                particles.reserveCapacity(target)
                for i in oldCount..<target {
                    particles.append(spawnParticle(index: i, total: target,
                                                    initVelScale: initVelScale,
                                                    baseSize: baseSize,
                                                    baseBrightness: baseBrightness,
                                                    brightnessJitter: brightnessJitter))
                }
            }
        }

        var dt: Float = 0
        var realDt: Float = 0
        if lastTimestamp >= 0 {
            realDt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
            dt = realDt * settings.particleSpeed
        }
        lastTimestamp = frame.timestamp

        // Beat-driven size pulse: decay current boost, then pulse on this frame.
        // Uses realDt (wall-clock) so the decay is independent of particleSpeed.
        beatBoost *= powf(0.5, realDt / beatHalfLife)   // half-life (default 150ms)
        if frame.beat {
            beatBoost = max(beatBoost, beatPulseScale * max(0, min(1, frame.beatIntensity)))
        }
        let sizeBoost: Float = 1 + beatBoost

        let bass = computeBass(frame, lowBandPercent: settings.particlesLowBandPercent)

        // Adaptive trigger. The absolute threshold alone only works at one loudness:
        // quiet playback whose beats peak just under it never pushes the field, which
        // then damps to a standstill. So a beat also counts when it stands out from the
        // music's own running bass level (a slow average), above a small noise floor.
        // A steady level, however loud or quiet, is not a beat and does not trigger.
        // Uses realDt (wall-clock) so it is independent of particleSpeed.
        if bassAverage < 0 { bassAverage = bass }   // first frame: start at the level
        let standsOut = bass > max(Self.adaptiveNoiseFloor, bassAverage * Self.adaptiveRatio)
        let triggered = bass > bassThreshold || standsOut
        bassAverage += (bass - bassAverage) * (1 - expf(-realDt / Self.adaptiveAverageSeconds))

        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        // Read once: `settings` is a very large struct, so per-particle access is costly.
        let particleSize = settings.particleSize
        var verts: [BarVertex] = []
        verts.reserveCapacity(particles.count * 6)

        for i in 0..<particles.count {
            var p = particles[i]
            p.position += p.velocity * dt
            p.velocity *= velocityDamping
            let lerp = min(dt * returnLerpRate, 1)
            p.brightness += (baseBrightness - p.brightness) * lerp
            p.size += (baseSize - p.size) * lerp

            if triggered {
                let len = simd_length(p.position)
                let dir = len > 0.0001 ? p.position / len : SIMD2<Float>(0, 1)
                p.velocity += dir * (bass * bassImpulse)
                p.brightness = min(brightnessCap, p.brightness + bass * bassBrightnessGain)
                p.size = min(baseSize * sizeCapMultiplier, p.size + bass * baseSize * bassSizeGain)
            }

            if abs(p.position.x) > respawnBound || abs(p.position.y) > respawnBound {
                p.position = SIMD2(rng.nextSigned() * respawnCenterHalfRange, rng.nextSigned() * respawnCenterHalfRange)
                p.velocity = SIMD2(rng.nextSigned() * respawnVelScale, rng.nextSigned() * respawnVelScale)
                p.brightness = baseBrightness
                p.size = baseSize
            }

            particles[i] = p

            let c = palette.sample(at: p.colorPos)
            let color = SIMD4<Float>(c.r * p.brightness, c.g * p.brightness, c.b * p.brightness, 1)
            let hx = p.size * sx * particleSize * sizeBoost
            let hy = p.size * sy * particleSize * sizeBoost
            let x0 = p.position.x - hx, x1 = p.position.x + hx
            let y0 = p.position.y - hy, y1 = p.position.y + hy
            let bl = BarVertex(position: SIMD4(x0, y0, 0, 1), color: color)
            let br = BarVertex(position: SIMD4(x1, y0, 0, 1), color: color)
            let tl = BarVertex(position: SIMD4(x0, y1, 0, 1), color: color)
            let tr = BarVertex(position: SIMD4(x1, y1, 0, 1), color: color)
            // Six plain appends: an array literal here allocates a temporary per
            // particle, which dominates the frame at high particle counts.
            verts.append(bl); verts.append(br); verts.append(tl)
            verts.append(br); verts.append(tr); verts.append(tl)
        }
        return verts
    }

    private func computeBass(_ frame: AudioFrame, lowBandPercent: Double) -> Float {
        guard !frame.bands.isEmpty else { return frame.rms }
        // The bass band count is Int(bands.count * percent). A persisted/edited huge or
        // NaN percent would make Int(...) TRAP (the Fireworks Float->Int bug). Fix: clamp
        // the percent to a finite range, then saturate the product to 1...bands.count with
        // explicit finite handling before Int(...). At the default percent (0.15) this
        // reproduces the prior integer math (bands.count * 15 / 100) bit-for-bit for every
        // band count, so the bass value is unchanged until the slider moves.
        let pct = lowBandPercent.isFinite ? min(max(lowBandPercent, 0.01), 1.0) : 0.15
        let raw = Double(frame.bands.count) * pct
        let n: Int
        if raw.isFinite { n = max(1, min(frame.bands.count, Int(raw))) }
        else if raw > 0 { n = frame.bands.count }   // +inf -> all bands
        else { n = 1 }                              // -inf or NaN -> minimum
        var sum: Float = 0
        for i in 0..<n { sum += frame.bands[i] }
        return sum / Float(n)
    }
}