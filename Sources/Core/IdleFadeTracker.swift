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

/// What the idle fade may treat as sound. Synthetic fallback frames are not a
/// sample: the caller passes `.noCapture` when the process tap is not delivering.
public enum IdleAudioSample: Equatable {
    case demo
    case noCapture
    case level(Float)
}

/// Decides whether the visualization and lyrics should be shown. A missing or
/// quiet capture starts the hold; past the hold the caller fades out. Demo mode
/// never goes idle. The view animation, not this clock, is the fade.
public struct IdleFadeTracker {
    public static let holdSeconds: TimeInterval = 2
    public static let levelEpsilon: Float = 0.003

    private var lastAudibleTime: TimeInterval

    public init(now: TimeInterval) {
        lastAudibleTime = now
    }

    public mutating func isActive(now: TimeInterval, sample: IdleAudioSample) -> Bool {
        let audible: Bool
        switch sample {
        case .demo:
            audible = true
        case .noCapture:
            audible = false
        case .level(let level):
            audible = level > Self.levelEpsilon
        }
        if audible { lastAudibleTime = now }
        return now - lastAudibleTime < Self.holdSeconds
    }
}
