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

/// Particle bursts triggered by `frame.beat == true`. Burst size scales with
/// `frame.beatIntensity` (0…1). Stateful — keep one instance alive across
/// frames (the renderer caches it).
public final class FireworksVisualizer: Visualizer {
    private struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var age: Float
        var lifetime: Float
        var colorPos: Float
    }

    private var particles: [Particle]
    private var nextIndex: Int = 0
    private var rng: SeededRNG
    private var lastTimestamp: CFTimeInterval = -1

    public init(maxParticles: Int = 600, seed: UInt64 = 0xBEEFC0DE) {
        self.particles = Array(repeating: Particle(position: .zero, velocity: .zero,
                                                    age: 999, lifetime: 1, colorPos: 0),
                               count: max(1, maxParticles))
        self.rng = SeededRNG(seed: seed)
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        // Read user-tunable fields with read-site clamps so persisted/edited JSON can't
        // break the particle state (e.g. a 0 capacity would divide-by-zero on wrap).
        // dt cap 0.1 stays hardcoded — it is a frame-time safety guard, not a control.
        let maxParticles = max(1, min(4000, settings.fireworksMaxParticles))

        // Stateful capacity reconciliation (mirror Fountain): the persistent particle
        // array tracks the clamped capacity. Growing keeps existing particles and appends
        // dead slots; shrinking drops the tail. nextIndex resets if now out of range so
        // the `% particles.count` write wrap stays valid.
        if particles.count != maxParticles {
            if maxParticles < particles.count {
                particles.removeLast(particles.count - maxParticles)
            } else {
                particles.append(contentsOf: repeatElement(
                    Particle(position: .zero, velocity: .zero, age: 999, lifetime: 1, colorPos: 0),
                    count: maxParticles - particles.count))
            }
            if nextIndex >= particles.count { nextIndex = 0 }
        }

        let gravity = Float(max(0, settings.fireworksGravity))
        let drag = Float(min(max(settings.fireworksDrag, 0), 1))
        let baseSize = Float(max(0, settings.fireworksBaseSize))

        var dt: Float = 0
        if lastTimestamp >= 0 {
            dt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1)) * settings.particleSpeed
        }
        lastTimestamp = frame.timestamp

        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        // Advance all particles.
        for i in 0..<particles.count {
            var p = particles[i]
            if p.age <= p.lifetime {
                p.position += p.velocity * dt
                p.velocity *= drag
                p.velocity.y -= gravity * dt
                p.age += dt
                particles[i] = p
            }
        }

        if frame.beat {
            spawnBurst(intensity: frame.beatIntensity, settings: settings)
        }

        // Emit live particles.
        var verts: [BarVertex] = []
        verts.reserveCapacity(particles.count * 6)
        let hx = baseSize * sx * settings.particleSize, hy = baseSize * sy * settings.particleSize
        for p in particles {
            guard p.age <= p.lifetime else { continue }
            let life = max(p.lifetime, 1e-6)
            let brightness = max(0, 1 - p.age / life)
            let c = palette.sample(at: p.colorPos)
            let color = SIMD4<Float>(c.r * brightness, c.g * brightness, c.b * brightness, 1)
            let x0 = p.position.x - hx, x1 = p.position.x + hx
            let y0 = p.position.y - hy, y1 = p.position.y + hy
            let bl = BarVertex(position: SIMD4(x0, y0, 0, 1), color: color)
            let br = BarVertex(position: SIMD4(x1, y0, 0, 1), color: color)
            let tl = BarVertex(position: SIMD4(x0, y1, 0, 1), color: color)
            let tr = BarVertex(position: SIMD4(x1, y1, 0, 1), color: color)
            verts.append(contentsOf: [bl, br, tl, br, tr, tl])
        }
        return verts
    }

    private func spawnBurst(intensity: Float, settings: VisualizerSettings) {
        // Read-site clamps: burstParticlesMax >= 1 (cap 400), burstParticlesMin in
        // 0...burstParticlesMax, baseLifetime/minLifetime > 0. The remaining fields are
        // free scalars (their UI sliders bound the editable range).
        let burstParticlesMax = max(1, min(400, settings.fireworksBurstParticlesMax))
        let burstParticlesMin = max(0, min(settings.fireworksBurstParticlesMin, burstParticlesMax))
        let scaleBase = Float(settings.fireworksBurstScaleBase)
        let scaleIntensity = Float(settings.fireworksBurstScaleIntensity)
        let baseSpeed = Float(settings.fireworksBaseSpeed)
        let spreadSpeed = Float(settings.fireworksSpreadSpeed)
        let baseLifetime = Float(max(settings.fireworksBaseLifetime, 1e-6))
        let lifetimeJitter = Float(settings.fireworksLifetimeJitter)
        let minLifetime = Float(max(settings.fireworksMinLifetime, 1e-6))
        let burstHalfX = Float(settings.fireworksBurstHalfX)
        let burstHalfY = Float(settings.fireworksBurstHalfY)
        let angleJitter = Float(settings.fireworksAngleJitter)

        let scale = scaleBase + scaleIntensity * max(0, min(1, intensity))   // default 0.7…1.3
        // Saturate the float product BEFORE Int(...) — Int(±inf) and Int(NaN) trap in
        // Swift, so a persisted/edited huge scale field (which narrows to Float.infinity)
        // or a NaN scale (e.g. +inf base plus -inf*intensity) must not crash. Finite
        // products clamp to [0, capacity]; +inf maps to capacity, -inf/NaN map to 0.
        // Default scale (~0.7…1.3) is finite and well within range, so behavior is
        // unchanged at defaults. The final min/max also caps to capacity and the floor.
        let raw = Float(burstParticlesMax) * scale
        let bounded: Float
        if raw.isFinite { bounded = min(max(raw, 0), Float(particles.count)) }
        else if raw > 0 { bounded = Float(particles.count) }   // +inf
        else { bounded = 0 }                                   // -inf or NaN
        // Cap the per-burst count to the ring capacity so a pathological max*scale can't
        // loop far past the buffer it writes into; the floor keeps a minimum visible burst.
        let burstCount = min(particles.count, max(burstParticlesMin, Int(bounded)))
        let cx = rng.nextSigned() * burstHalfX
        let cy = rng.nextSigned() * burstHalfY
        let colorPos = rng.nextUnit()
        for k in 0..<burstCount {
            let theta = (Float(k) / Float(burstCount)) * 2 * .pi + rng.nextSigned() * angleJitter
            let speed = (baseSpeed + rng.nextUnit() * spreadSpeed) * scale
            let lifetime = (baseLifetime + rng.nextSigned() * lifetimeJitter) * scale
            particles[nextIndex] = Particle(
                position: SIMD2(cx, cy),
                velocity: SIMD2(cosf(theta) * speed, sinf(theta) * speed),
                age: 0,
                lifetime: max(minLifetime, lifetime),
                colorPos: colorPos
            )
            nextIndex = (nextIndex + 1) % particles.count
        }
    }
}