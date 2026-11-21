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

/// Picks the render frame rate: the active style's override, else the
/// app-wide rate; and a low idle rate once the scene has faded out, so an
/// idle window stops loading the GPU and the window compositor.
public enum FrameRatePolicy {
    /// Rate while idle: enough to notice audio returning (the idle check and
    /// the capture watchdog run on the draw path) at a fraction of the cost.
    public static let idleFPS = 10
    /// Seconds inactive before dropping to `idleFPS`: past the ~2 s fade-out.
    public static let idleDelaySeconds: Double = 3
    public static let minimumActiveFPS = 30

    /// `idleSeconds` is nil while the visualization is active.
    public static func rate(globalFPS: Int, styleOverride: Int?, idleSeconds: Double?) -> Int {
        if let idleSeconds, idleSeconds >= idleDelaySeconds { return idleFPS }
        return max(minimumActiveFPS, styleOverride ?? globalFPS)
    }
}

public extension VisualizerSettings {
    /// The frame rate for the active visualization while it is playing.
    var activeFrameRate: Int {
        FrameRatePolicy.rate(globalFPS: targetFPS, styleOverride: current.frameRateOverride, idleSeconds: nil)
    }
}
