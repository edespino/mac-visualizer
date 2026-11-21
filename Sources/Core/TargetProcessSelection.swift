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

/// A running Core Audio process, identified by its object id and bundle id.
/// Pure (no CoreAudio import) so the selection below is unit-testable; the
/// `id` is the `AudioObjectID` (a `UInt32`) the Services layer reads from the HAL.
public struct AudioProcessInfo: Equatable, Hashable {
    public let id: UInt32
    public let bundleID: String

    public init(id: UInt32, bundleID: String) {
        self.id = id
        self.bundleID = bundleID
    }
}

/// Chooses which process object ids the audio tap should capture.
///
/// The visualizer taps EVERY running target player at once (Spotify AND Apple
/// Music), rather than one chosen by priority. A process that is silent (paused,
/// or the other player while one plays) contributes nothing to the stereo
/// mixdown, so switching players needs no re-selection and no rebuild as long as
/// both were present when the tap was built — whichever is playing is already in
/// the mix. The Services layer rebuilds only when the *set* of running targets
/// changes (a player launches or quits).
public enum TargetProcessSelection {
    /// The ids of all running processes whose bundle id is in `wanted`, ordered
    /// by `wanted`'s priority (and, within one bundle id, by discovery order). A
    /// wanted bundle id that is not running is skipped; an empty result means the
    /// caller should park in `.noTargetProcess`.
    public static func select(from running: [AudioProcessInfo], wanted: [String]) -> [UInt32] {
        var ids: [UInt32] = []
        for bundle in wanted {
            for process in running where process.bundleID == bundle {
                ids.append(process.id)
            }
        }
        return ids
    }
}
