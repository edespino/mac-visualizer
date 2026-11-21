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
import AudioToolbox
import CoreAudio
import MacVisualizerCore

/// Finds the Core Audio process-object IDs for target apps (by bundle id).
struct ProcessLocator {
    /// Bundle ids we care about. Every running one is tapped at once (see
    /// `allTargets`), so the order is just the deterministic tie-break for the
    /// built id set, not a winner-take-all priority.
    static let defaultTargets = ["com.spotify.client", "com.apple.Music"]

    /// All current audio process objects paired with their bundle id (when available).
    static func runningAudioProcesses() -> [(id: AudioObjectID, bundleID: String)] {
        let ids = CoreAudioHAL.objectIDs(AudioObjectID(kAudioObjectSystemObject),
                                         kAudioHardwarePropertyProcessObjectList)
        return ids.compactMap { id in
            guard let bundle = CoreAudioHAL.string(id, kAudioProcessPropertyBundleID) else { return nil }
            return (id, bundle)
        }
    }

    /// The process-object ids of ALL running target players, ordered by
    /// `targets`' priority. Empty when no target is running. The tap captures
    /// every id at once, so switching between players needs no re-selection.
    static func allTargets(_ targets: [String] = defaultTargets) -> [AudioObjectID] {
        let running = runningAudioProcesses().map { AudioProcessInfo(id: $0.id, bundleID: $0.bundleID) }
        return TargetProcessSelection.select(from: running, wanted: targets)
    }
}