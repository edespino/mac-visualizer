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

// Two-angle orientation of the Spinner puck. Pure; the caller supplies dt.
//
// Convention (screen space, x right, y up, z toward the viewer; the puck is centered on the origin):
//   * `pitch` rotates about the screen's horizontal axis (x). Positive pitch tips the top edge AWAY from the viewer.
//   * `yaw` rotates about the screen's vertical axis (y). Positive yaw turns the right edge AWAY from the viewer.
//   * The orientation applied is YAW AFTER PITCH in screen space: pitch about screen-x first, then yaw about
//     screen-y (rotation matrix R = Ry(yaw) * Rx(-pitch) acting on puck coordinates; the RealityKit transform uses
//     exactly this product).
// Both angles are unwrapped radians: key steps move the TARGET by one step either way, the current value eases
// toward it, and a value is reduced to one turn only when it is sent to a renderer.

public struct SpinnerOrientation: Equatable {
    /// Current (eased) angles and their targets, unwrapped radians.
    public private(set) var pitch: Double = 0
    public private(set) var yaw: Double = 0
    public private(set) var pitchTarget: Double = 0
    public private(set) var yawTarget: Double = 0
    /// Last face that was clearly shown; kept when the disc is exactly edge-on so the answer cannot flip-flop.
    public private(set) var lastFront: Bool = true

    /// |z| of the front face's normal below which the disc counts as edge-on.
    static let edgeOnEpsilon: Double = 1e-9

    /// Self-levelling roll (radians) of the hub buttons about the puck's own axis: the rotation that makes the hub
    /// marks' "up" point as close to screen-up as the current pitch and yaw allow (see `SpinnerHubRoll`). Kept at
    /// its previous value while the faces are edge-on.
    public private(set) var hubRoll: Double = 0

    public init() {}

    /// Z component (toward the viewer) of the FRONT face's outward normal for the two angles.
    /// n = R * (0, 0, 1) = (cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)).
    public static func frontNormalZ(pitch: Double, yaw: Double) -> Double {
        let cosPitch: Double = cos(pitch)
        let cosYaw: Double = cos(yaw)
        return cosPitch * cosYaw
    }

    /// True while the FRONT face points toward the viewer (positive z component). Exactly edge-on keeps the last face shown.
    public var facesViewerFront: Bool { lastFront }

    private mutating func updateRoll() {
        let rolls = SpinnerHubRoll.rolls(pitch: pitch, yaw: yaw, previous: (front: hubRoll, back: hubRoll))
        hubRoll = rolls.front
    }

    private mutating func updateFacing() {
        updateRoll()
        let z: Double = Self.frontNormalZ(pitch: pitch, yaw: yaw)
        if z > Self.edgeOnEpsilon {
            lastFront = true
        } else if z < -Self.edgeOnEpsilon {
            lastFront = false
        }
    }

    /// Pins both angles (and their targets) at once. At an exactly edge-on pose with no yaw, the face follows the
    /// pitch-only convention (90 degrees reads front, 270 reads back) so a pose set directly has a defined face.
    public mutating func set(pitch newPitch: Double, yaw newYaw: Double = 0) {
        pitch = newPitch
        yaw = newYaw
        pitchTarget = newPitch
        yawTarget = newYaw
        let z: Double = Self.frontNormalZ(pitch: newPitch, yaw: newYaw)
        if abs(z) <= Self.edgeOnEpsilon && SpinnerTilt.normalized(newYaw) < 1e-9 {
            lastFront = !SpinnerTilt.scrollIsBack(radians: newPitch)
            updateRoll()
        } else {
            updateFacing()
        }
    }

    /// Moves the pitch target one step forward (+1) or back (-1).
    public mutating func step(pitch direction: Int, stepRadians: Double) {
        let sign: Double = (direction < 0) ? -1 : 1
        pitchTarget += sign * stepRadians
    }

    /// Moves the yaw target one step right (+1) or left (-1).
    public mutating func step(yaw direction: Int, stepRadians: Double) {
        let sign: Double = (direction < 0) ? -1 : 1
        yawTarget += sign * stepRadians
    }

    /// Free dragging: moves current and target together, so there is no easing lag and the pose stays where it is.
    public mutating func nudge(pitchBy dPitch: Double, yawBy dYaw: Double) {
        pitch += dPitch
        pitchTarget += dPitch
        yaw += dYaw
        yawTarget += dYaw
        updateFacing()
    }

    /// Eases both angles back to face-on front by the shortest way (the nearest whole turn of each).
    public mutating func reset() {
        let turn: Double = 2 * Double.pi
        pitchTarget = (pitch / turn).rounded() * turn
        yawTarget = (yaw / turn).rounded() * turn
    }

    /// True when the pitch TARGET and the yaw TARGET are each a multiple of half a turn (180 degrees): a standard
    /// face-on pose, front or back, however it was reached.
    private var targetIsFaceOn: Bool {
        let eps: Double = 1e-3
        let halfTurn: Double = Double.pi
        let pitchRem: Double = abs(pitchTarget - (pitchTarget / halfTurn).rounded() * halfTurn)
        let yawRem: Double = abs(yawTarget - (yawTarget / halfTurn).rounded() * halfTurn)
        return pitchRem < eps && yawRem < eps
    }

    /// The `0` key: from any pose other than a standard face-on one (see `targetIsFaceOn`), eases back to the front
    /// pose (`reset()`); at a face-on TARGET it flips instead by moving the pitch target half a turn forward (the `t`
    /// direction, a tumble about the horizontal axis). Decided from the targets (not the eased values), so a second
    /// press during the reset animation flips.
    public mutating func resetOrFlip() {
        if targetIsFaceOn {
            pitchTarget += Double.pi
        } else {
            reset()
        }
    }

    /// Option+`0`: same rule as `resetOrFlip()`, but the flip is about the vertical screen axis (the yaw target moves
    /// half a turn in the `y` / yaw-right direction). Flips by either key chain in any order.
    public mutating func resetOrFlipYaw() {
        if targetIsFaceOn {
            yawTarget += Double.pi
        } else {
            reset()
        }
    }

    /// Advances the easing by `dt` seconds (first-order lag, never overshoots).
    public mutating func ease(dt: Double, timeConstant: Double) {
        let tau: Double = max(timeConstant, 1e-6)
        let k: Double = 1 - exp(-max(dt, 0) / tau)
        pitch += (pitchTarget - pitch) * k
        yaw += (yawTarget - yaw) * k
        updateFacing()
    }

    /// Both angles reduced to one turn [0, 2 pi) for a renderer.
    public var normalizedPitch: Double { SpinnerTilt.normalized(pitch) }
    public var normalizedYaw: Double { SpinnerTilt.normalized(yaw) }
}

/// Orientation requests collected from keys and the Option-drag between frames (main thread).
public struct SpinnerOrientationRequests: Equatable {
    public var pitchSteps: Int = 0
    public var yawSteps: Int = 0
    public var reset: Bool = false
    /// The `0` key: reset, or flip to the other face when already face-on (see `SpinnerOrientation.resetOrFlip`).
    public var resetOrFlip: Bool = false
    /// Option+`0`: reset, or flip about the vertical axis when face-on (see `SpinnerOrientation.resetOrFlipYaw`).
    public var resetOrFlipYaw: Bool = false
    public var dragPitchRadians: Double = 0
    public var dragYawRadians: Double = 0
    public init() {}
    public var isEmpty: Bool {
        pitchSteps == 0 && yawSteps == 0 && !reset && !resetOrFlip && !resetOrFlipYaw && dragPitchRadians == 0 && dragYawRadians == 0
    }
}

/// Option-drag trackball limited to two axes: horizontal movement changes yaw, vertical movement changes pitch.
/// Movement below `movementThresholdPoints` of travel is held back (so a plain Option-click is still a click);
/// once the threshold is crossed the gesture is a rotation and the held-back movement is released with it.
public struct SpinnerDragGesture: Equatable {
    public static let movementThresholdPoints: Double = 4
    public private(set) var rotating: Bool = false
    private var heldX: Double = 0
    private var heldY: Double = 0

    public init() {}

    /// Rotation to apply (radians) for a mouse movement of (`deltaX`, `deltaY`) points, where positive `deltaY` is
    /// DOWNWARD on screen (AppKit's drag deltas). The surface under the pointer follows it: dragging right turns the
    /// right edge toward the viewer (negative yaw), dragging down turns the top edge toward the viewer (negative pitch).
    public mutating func move(deltaX: Double, deltaY: Double, degreesPerPoint: Double) -> (pitch: Double, yaw: Double) {
        var moveX: Double = deltaX
        var moveY: Double = deltaY
        if !rotating {
            heldX += deltaX
            heldY += deltaY
            let travel: Double = (heldX * heldX + heldY * heldY).squareRoot()
            if travel < Self.movementThresholdPoints { return (0, 0) }
            rotating = true
            moveX = heldX
            moveY = heldY
            heldX = 0
            heldY = 0
        }
        let radiansPerPoint: Double = degreesPerPoint * Double.pi / 180
        let pitch: Double = -moveY * radiansPerPoint
        let yaw: Double = -moveX * radiansPerPoint
        return (pitch, yaw)
    }
}

/// Self-levelling hub marks. Each hub button is free to turn about the puck's own axis (it is the bearing's hub), so
/// every frame it is rolled so that its mark's "up" direction, projected onto the screen, points to screen-up.
///
/// Convention. The puck's orientation is R = Ry(yaw) * Rx(-pitch) (see `SpinnerOrientation`). The hub-local axes
/// x (right) and y (up) map to screen vectors c1 = (cos yaw, 0) and c2 = (-sin yaw sin pitch, cos pitch); the hub's
/// local-to-screen matrix M = [c1 c2] has determinant cos pitch * cos yaw, the front face's normal z. A hub rolled
/// by theta (counter-clockwise about the hub's +z, applied before R) has local up (-sin theta, cos theta); the roll
/// that sends it to screen-up solves M * (-sin theta, cos theta) ~ (0, 1), which gives
/// theta = atan2(-sin yaw sin pitch, cos yaw) when det > 0, and the same direction negated when det < 0.
///
/// Front and back hubs share one roll: both textures are authored for the view in which their face is visible (the
/// back texture is authored mirrored in x, so it reads correctly through the mirrored `det < 0` view), so the same
/// in-plane rotation levels either. The roll is continuous while a face is visible; the unavoidable 180-degree
/// flip happens exactly as `det` passes through zero (the faces are edge-on and invisible). At exactly edge-on
/// (|det| < `edgeOnEpsilon`) the previous roll is kept.
public enum SpinnerHubRoll {
    /// |det| below which the faces count as edge-on and the previous roll is kept.
    public static let edgeOnEpsilon: Double = 1e-6

    /// Rolls (radians, in (-pi, pi]) for the front and back hubs at `pitch` and `yaw` (radians).
    public static func rolls(pitch: Double, yaw: Double,
                             previous: (front: Double, back: Double)?) -> (front: Double, back: Double) {
        let cp: Double = cos(pitch)
        let sp: Double = sin(pitch)
        let cy: Double = cos(yaw)
        let sy: Double = sin(yaw)
        let det: Double = cy * cp
        if abs(det) < edgeOnEpsilon {
            if let previous { return previous }
            return (front: 0, back: 0)
        }
        let spSy: Double = sy * sp
        var roll: Double
        if det > 0 {
            roll = atan2(-spSy, cy)
        } else {
            roll = atan2(spSy, -cy)
        }
        if roll <= -Double.pi { roll += 2 * Double.pi }
        return (front: roll, back: roll)
    }

    /// Where the hub-local "up" lands on screen (orthographic) for a hub rolled by `roll` at `pitch` and `yaw`.
    /// Returns the unit-less screen vector; (0, +1) is upright. Used by tests and probes.
    public static func screenUp(pitch: Double, yaw: Double, roll: Double) -> (x: Double, y: Double) {
        let cp: Double = cos(pitch)
        let sp: Double = sin(pitch)
        let cy: Double = cos(yaw)
        let sy: Double = sin(yaw)
        let localX: Double = -sin(roll)
        let localY: Double = cos(roll)
        let screenX: Double = cy * localX - sy * sp * localY
        let screenY: Double = cp * localY
        return (x: screenX, y: screenY)
    }
}
