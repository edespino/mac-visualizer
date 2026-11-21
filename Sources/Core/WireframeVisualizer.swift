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

/// 9th visualizer style: subdivided icosphere wireframe with audio-deformed
/// vertices. Rotates slowly on the Y axis with a constant X tilt; each vertex
/// pushes outward along its normal by the audio band mapped to its azimuth.
/// Stateful — the renderer caches one instance across frames.
///
/// Placement (`wireframeXExtent` / `wireframeYExtent` / `wireframeVerticalCenter`,
/// mirroring the Heightfield extent/center knobs) scales the projected footprint
/// per axis and shifts it vertically. Identity defaults (1, 1, 0) reproduce the
/// centered, aspect-corrected sphere byte-for-byte; raising `xExtent` past the
/// aspect correction fills a wide window (the sphere reads as an ellipsoid) and
/// a negative `verticalCenter` anchors it toward the bottom edge, letting a large
/// sphere sit as a dome cropped by the window. Extent scaling deliberately does
/// NOT touch the edge-quad perpendicular, so line thickness stays uniform on
/// screen however far the geometry is stretched.
public final class WireframeVisualizer: Visualizer {

    // Mesh cache, keyed on the resolved subdivision level. Rebuilt only when the
    // setting changes — at the default (and steady state) it is built once.
    private var baseVertices: [SIMD3<Float>]
    private var edges: [(Int, Int)]
    private var cachedSubdivisions: Int

    // Animation state.
    private var rotationY: Float = 0
    private var lastTimestamp: CFTimeInterval = -1

    public init() {
        let level = 2
        let mesh = WireframeMesh.icosphere(subdivisions: level)
        self.baseVertices = mesh.vertices
        self.edges = mesh.edges
        self.cachedSubdivisions = level
    }

    public func makeVertices(frame: AudioFrame, settings: VisualizerSettings,
                             palette: ColorPalette, aspect: Float) -> [BarVertex] {
        // --- Resolve settings-driven tunables -----------------------------
        let baseRadius = Float(settings.wireframeBaseRadius)
        let displaceScale = Float(settings.wireframeDisplaceScale)
        let edgeHalfThickness = Float(settings.wireframeLineThickness)
        let rotationSpeed = Float(settings.wireframeRotationSpeed)   // rad/s on Y axis
        let tiltX = Float(settings.wireframeTiltX)                   // constant X tilt (rad)
        let lineAlpha = Float(settings.wireframeLineOpacity)
        // Placement, clamped at the read site so a persisted/hand-edited value
        // can never collapse the mesh (non-positive or non-finite extent) or
        // push it entirely out of view.
        var xExtent = max(finiteOrOne(settings.wireframeXExtent), 1e-4)
        let yExtent = max(finiteOrOne(settings.wireframeYExtent), 1e-4)
        var verticalCenter = min(1, max(-1, finiteOrZero(settings.wireframeVerticalCenter)))

        // Rebuild the mesh only when the subdivision level changes (clamped 0...4).
        let subdivisions = min(max(settings.wireframeSubdivisions, 0), 4)
        if subdivisions != cachedSubdivisions {
            let mesh = WireframeMesh.icosphere(subdivisions: subdivisions)
            baseVertices = mesh.vertices
            edges = mesh.edges
            cachedSubdivisions = subdivisions
        }

        // --- Advance rotation ---------------------------------------------
        let dt: Float
        if lastTimestamp < 0 {
            dt = 0
        } else {
            dt = Float(min(max(frame.timestamp - lastTimestamp, 0), 0.1))
        }
        lastTimestamp = frame.timestamp
        rotationY += dt * rotationSpeed

        // --- Aspect correction --------------------------------------------
        var sx: Float = 1, sy: Float = 1
        if aspect >= 1 { sx = 1 / aspect } else { sy = aspect }

        // Fill mode: derive the placement from the live aspect instead of the
        // manual knobs, so the sphere keeps filling the width and sitting on
        // the bottom edge as the window is resized. Fitted to the RESTING
        // radius, so audio displacement crops slightly past the edges rather
        // than leaving the sphere permanently inset. Height (yExtent) still
        // applies — it sets how tall the dome is — and the bottom stays pinned
        // as it changes.
        let resting = max(baseRadius, 1e-4)
        if settings.wireframeFillWidth {
            xExtent = 1 / (resting * sx)
        }
        if settings.wireframeAnchorBottom {
            // Offset by the mesh's own half-height, so the bottom stays pinned
            // independently of whatever width is in effect.
            verticalCenter = -1 + resting * sy * yExtent
        }

        // --- Per-vertex: deform, rotate, project, sample color -----------
        let bandCount = max(frame.bands.count, 1)
        let cosX = cos(tiltX), sinX = sin(tiltX)
        let cosY = cos(rotationY), sinY = sin(rotationY)

        struct ProjectedVertex {
            var screen: SIMD2<Float>
            var color: SIMD4<Float>
        }
        var projected = [ProjectedVertex](repeating: ProjectedVertex(screen: .zero, color: .zero),
                                          count: baseVertices.count)
        for i in 0..<baseVertices.count {
            let v = baseVertices[i]
            // Map azimuth angle in XZ-plane → band index. Use BASE vertex (not
            // rotated) so each vertex always reads the same band — the band
            // physically rotates with the mesh as the user sees the geometry
            // turn.
            let azimuth = atan2(v.x, v.z)              // ∈ [-π, π]
            let t = (azimuth + .pi) / (2 * .pi)        // 0..1
            let bandIndex = min(bandCount - 1, max(0, Int(t * Float(bandCount))))
            let energy = frame.bands[bandIndex]
            // Push outward along the vertex's own normal (== position on unit sphere).
            let displaced = v * (baseRadius + energy * displaceScale)

            // Apply tilt-X, then rotate-Y.
            let v1 = SIMD3<Float>(displaced.x,
                                  displaced.y * cosX - displaced.z * sinX,
                                  displaced.y * sinX + displaced.z * cosX)
            let v2 = SIMD3<Float>( v1.x * cosY + v1.z * sinY,
                                   v1.y,
                                  -v1.x * sinY + v1.z * cosY)

            // Orthographic projection: drop z, apply aspect correction, then
            // the placement transform (per-axis extent + vertical offset).
            let screen = SIMD2<Float>(v2.x * sx * xExtent,
                                      v2.y * sy * yExtent + verticalCenter)

            // Color: palette sampled by energy.
            let c = palette.sample(at: energy)
            projected[i] = ProjectedVertex(screen: screen,
                                           color: SIMD4<Float>(c.r, c.g, c.b, lineAlpha))
        }

        // --- Emit edge-quads -----------------------------------------------
        var verts: [BarVertex] = []
        verts.reserveCapacity(edges.count * 6)
        for (a, b) in edges {
            let pa = projected[a].screen
            let pb = projected[b].screen
            let ca = projected[a].color
            let cb = projected[b].color

            // Perpendicular offset for the thin quad. Aspect-correct so the
            // line looks uniformly thick on screen.
            let dir = pb - pa
            let len = simd_length(dir)
            let perp: SIMD2<Float>
            if len > 1e-6 {
                let n = dir / len
                perp = SIMD2<Float>(-n.y, n.x) * edgeHalfThickness
            } else {
                perp = SIMD2<Float>(0, edgeHalfThickness)
            }
            let perpCorrected = SIMD2<Float>(perp.x * sx, perp.y * sy)

            let p00 = pa - perpCorrected
            let p01 = pa + perpCorrected
            let p10 = pb - perpCorrected
            let p11 = pb + perpCorrected

            // Two triangles: (p00, p10, p01) and (p10, p11, p01).
            // Colors interpolate from a→b across the quad.
            verts.append(BarVertex(position: SIMD4(p00.x, p00.y, 0, 1), color: ca))
            verts.append(BarVertex(position: SIMD4(p10.x, p10.y, 0, 1), color: cb))
            verts.append(BarVertex(position: SIMD4(p01.x, p01.y, 0, 1), color: ca))
            verts.append(BarVertex(position: SIMD4(p10.x, p10.y, 0, 1), color: cb))
            verts.append(BarVertex(position: SIMD4(p11.x, p11.y, 0, 1), color: cb))
            verts.append(BarVertex(position: SIMD4(p01.x, p01.y, 0, 1), color: ca))
        }
        return verts
    }

    /// Non-finite persisted values fall back to the identity so a corrupt
    /// setting degrades to "no placement change" instead of NaN geometry.
    private func finiteOrOne(_ v: Double) -> Float {
        let f = Float(v)
        return f.isFinite ? f : 1
    }

    private func finiteOrZero(_ v: Double) -> Float {
        let f = Float(v)
        return f.isFinite ? f : 0
    }
}