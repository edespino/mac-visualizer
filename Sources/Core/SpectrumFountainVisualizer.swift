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

/// A per-band fountain: each frequency band is a column along the bottom; the band's
/// level drives the spawn rate and launch velocity of particles in that column.
/// Gravity pulls particles back down; they fade and die over `lifetime`.
/// Stateful — keep one instance alive across frames (the renderer caches it).
public final class SpectrumFountainVisualizer: Visualizer {
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

    public init(maxParticles: Int = 600, seed: UInt64 = 0xFEEDFACE) {
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
        let maxParticles = max(1, min(4000, settings.fountainMaxParticles))
        let spawnRate = Float(max(0, settings.fountainSpawnRate))
        let spawnFloor = Float(min(max(settings.fountainSpawnFloor, 0), 1))
        let baseUp = Float(max(0, settings.fountainBaseUp))
        let launchScale = Float(max(0, settings.fountainLaunchScale))
        let launchJitter = Float(min(max(settings.fountainLaunchJitter, 0), 1))
        let gravity = Float(max(0, settings.fountainGravity))
        let horizontalJitter = Float(settings.fountainHorizontalJitter)
        let horizontalDrag = Float(min(max(settings.fountainHorizontalDrag, 0), 1))
        let baseLifetime = Float(max(settings.fountainBaseLifetime, 1e-6))
        let baseSize = Float(max(0, settings.fountainBaseSize))
        let beatLaunchBoost = Float(max(0, settings.fountainBeatLaunchBoost))

        // Stateful capacity reconciliation: the persistent particle array tracks the
        // (clamped) maxParticles setting. Growing keeps existing particles and appends
        // dead slots; shrinking drops the tail. nextIndex is reset if now out of range
        // so the `% particles.count` write wrap stays valid.
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

        var dt: Float = 0
        if lastTimestamp >= 0 {
            dt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1)) * settings.particleSpeed
        }
        lastTimestamp = frame.timestamp

        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        let beatLaunch: Float = frame.beat ? (1 + beatLaunchBoost * max(0, min(1, frame.beatIntensity))) : 1

        // Advance all particles.
        for i in 0..<particles.count {
            var p = particles[i]
            if p.age <= p.lifetime {
                p.position += p.velocity * dt
                p.velocity.y -= gravity * dt
                p.velocity.x *= horizontalDrag
                p.age += dt
                particles[i] = p
            }
        }

        // Spawn from each band probabilistically: P(spawn) = L * spawnRate * dt (clamped).
        let n = frame.bands.count
        if n > 0 && dt > 0 {
            for i in 0..<n {
                let L = frame.bands[i]
                guard L >= spawnFloor else { continue }
                let p = min(L * spawnRate * dt, 1)
                if rng.nextUnit() < p {
                    let x = -1 + 2 * Float(i) / Float(max(n - 1, 1))
                    // Per-spawn launch jitter so particles in the same column
                    // reach different apex heights — softens the visible ceiling.
                    let vyBase = baseUp + L * launchScale
                    let vy = vyBase * (1 + rng.nextSigned() * launchJitter) * beatLaunch
                    let vx = rng.nextSigned() * horizontalJitter
                    particles[nextIndex] = Particle(
                        position: SIMD2(x, -1),
                        velocity: SIMD2(vx, vy),
                        age: 0,
                        lifetime: baseLifetime,
                        colorPos: Float(i) / Float(max(n - 1, 1))
                    )
                    nextIndex = (nextIndex + 1) % particles.count
                }
            }
        }

        // Emit live particles as small aspect-corrected quads.
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
}