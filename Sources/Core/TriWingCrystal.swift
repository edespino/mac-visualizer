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

// View-dependent look of the Tri-wing's anti-reflective coated crystal. Face-on the glass is invisible; a thin blue
// sheen builds with the glancing angle, and a dim blue "ghost" of a four-pane window shows only near the pose where the
// scene's key light would mirror off the flat glass toward the camera. A physically based clear surface shows no usable
// reflection in the renderer, so both are drawn as transparent emissive overlays. These pure helpers give the sheen's
// strength and the ghost's strength and position from the pose.

public enum TriWingCrystal {

    /// Direction toward the scene's key light (the unit vector the RealityKit scene places its key light along; the
    /// renderer normalises the same three numbers). The camera looks along -z, so the view direction is +z.
    public static let keyLight: (x: Float, y: Float, z: Float) = normalised(-0.55, 0.60, 0.58)

    /// Surface normal that mirrors the key light straight into the camera: the half vector of the light and view directions.
    public static let mirrorNormal: (x: Float, y: Float, z: Float) = normalised(keyLight.x, keyLight.y, keyLight.z + 1)

    private static func normalised(_ x: Float, _ y: Float, _ z: Float) -> (x: Float, y: Float, z: Float) {
        let l: Float = (x * x + y * y + z * z).squareRoot()
        return (x / l, y / l, z / l)
    }

    /// Unit normal of the front face (the part's +z) in screen space for the pose R = Ry(yaw) * Rx(-pitch).
    public static func frontNormal(pitch: Float, yaw: Float) -> (x: Float, y: Float, z: Float) {
        (cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    }

    /// 1 - |cos| of the angle between the surface normal and the view axis: 0 face-on, 1 edge-on. Same for both faces.
    public static func glancing(pitch: Float, yaw: Float) -> Float {
        1 - abs(frontNormal(pitch: pitch, yaw: yaw).z)
    }

    /// Opacity of the blue anti-reflective sheen: exactly nothing face-on, thin at moderate tilt, modest at glancing angles.
    public static func sheenOpacity(pitch: Float, yaw: Float) -> Float {
        let g: Float = glancing(pitch: pitch, yaw: yaw)
        return 0.22 * g * g.squareRoot()
    }

    /// Normal of the face toward the camera (the front face's normal, or its negative for the back face).
    private static func visibleNormal(pitch: Float, yaw: Float, face: Int) -> (x: Float, y: Float, z: Float) {
        let n = frontNormal(pitch: pitch, yaw: yaw)
        if face == 0 { return n }
        return (-n.x, -n.y, -n.z)
    }

    /// The pose (pitch, yaw in radians) at which the given face's glass mirrors the key light into the camera.
    public static func mirrorPose(face: Int) -> (pitch: Float, yaw: Float) {
        let h = mirrorNormal
        if face == 0 { return (asin(h.y), atan2(h.x, h.z)) }
        return (asin(-h.y), atan2(-h.x, -h.z))
    }

    /// Angular reach of the ghost around the mirror pose (radians, about 15 degrees).
    public static let ghostReach: Float = 0.26

    /// Strength 0...1 of the window ghost: 1 at the mirror pose, smoothly 0 beyond `ghostReach` of it (so 0 face-on and far away).
    public static func ghostStrength(pitch: Float, yaw: Float, face: Int) -> Float {
        let m = visibleNormal(pitch: pitch, yaw: yaw, face: face)
        let h = mirrorNormal
        let dot: Float = min(max(m.x * h.x + m.y * h.y + m.z * h.z, -1), 1)
        let d: Float = acos(dot)
        let x: Float = d / ghostReach
        if x >= 1 { return 0 }
        let k: Float = 1 - x * x
        return k * k
    }

    /// Position of the ghost in the face's own crystal coordinates (crystal diameters from the centre; for the back face
    /// local x is mirrored). Zero at the mirror pose; the image slides opposite to the normal's deviation from it.
    public static func ghostOffset(pitch: Float, yaw: Float, face: Int) -> (x: Float, y: Float) {
        let m = visibleNormal(pitch: pitch, yaw: yaw, face: face)
        let h = mirrorNormal
        let gain: Float = 1.4
        let sx: Float = -(m.x - h.x) * gain
        let sy: Float = -(m.y - h.y) * gain
        if face == 0 { return (sx, sy) }
        return (-sx, sy)
    }
}
