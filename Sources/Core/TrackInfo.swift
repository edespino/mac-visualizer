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

/// Currently-playing track metadata (artwork is resolved separately as an image).
public struct TrackInfo: Equatable {
    public var title: String?
    public var artist: String?
    public var album: String?

    public init(title: String?, artist: String?, album: String?) {
        self.title = title
        self.artist = artist
        self.album = album
    }

    public var isEmpty: Bool {
        (title?.isEmpty ?? true) && (artist?.isEmpty ?? true) && (album?.isEmpty ?? true)
    }
}

/// A snapshot of one media player's run/play status (no ScriptingBridge here — pure).
public struct PlayerSnapshot: Equatable {
    public let bundleID: String
    public let isRunning: Bool
    public let isPlaying: Bool

    public init(bundleID: String, isRunning: Bool, isPlaying: Bool) {
        self.bundleID = bundleID
        self.isRunning = isRunning
        self.isPlaying = isPlaying
    }
}

/// Choose the active player: a running+playing one (first in `preferenceOrder`),
/// else the first running one (preference order), else nil. Unknown bundles are ignored.
public func selectActivePlayer(_ snapshots: [PlayerSnapshot], preferenceOrder: [String]) -> String? {
    for id in preferenceOrder {
        if let s = snapshots.first(where: { $0.bundleID == id }), s.isRunning, s.isPlaying { return id }
    }
    for id in preferenceOrder {
        if let s = snapshots.first(where: { $0.bundleID == id }), s.isRunning { return id }
    }
    return nil
}