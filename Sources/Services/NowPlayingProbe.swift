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
import MacVisualizerCore

/// CLI verification: print each player's run/play state (raw FourCC) and, for the active
/// playing one, its track. First run triggers the Automation permission prompt per app.
enum NowPlayingProbe {
    static func run() {
        let order = [PlayerReader.spotifyBundle, PlayerReader.musicBundle]
        for id in order {
            let running = PlayerReader.isRunning(id)
            let raw = PlayerReader.playerStateRaw(id)
            let rawStr = raw.map { String(format: "0x%08X", $0) } ?? "nil"
            print("\(id): running=\(running) playerStateRaw=\(rawStr) isPlaying=\(PlayerReader.isPlaying(id))")
            if running {
                print("  raw duration:        \(PlayerReader.describeRaw(id, trackKey: "duration", appKey: nil))")
                print("  raw player position: \(PlayerReader.describeRaw(id, trackKey: nil, appKey: "playerPosition"))")
            }
        }
        let snaps = order.map { PlayerReader.snapshot($0) }
        if let active = selectActivePlayer(snaps, preferenceOrder: order) {
            print("active: \(active)")
            if let t = PlayerReader.track(active) {
                print("  title:  \(t.title ?? "?")")
                print("  artist: \(t.artist ?? "?")")
                print("  album:  \(t.album ?? "?")")
                print("  artwork: \(PlayerReader.artwork(active) != nil ? "present" : "none")")
            } else {
                print("  (no readable track)")
            }
        } else {
            print("active: none")
        }
    }
}