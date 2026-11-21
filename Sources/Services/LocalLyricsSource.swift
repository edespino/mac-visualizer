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

/// Reads a local `.lrc` file matching the track from a user-chosen folder.
/// The folder and its files are the user's own data; their contents are
/// parsed but never logged.
struct LocalLyricsReader {
    func read(folder: String, track: LyricsTrack) -> LyricsResult {
        let path = (folder as NSString).expandingTildeInPath
        guard !path.isEmpty else { return .none }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return .none }
        guard let match = LocalLyricsMatcher.match(filenames: names,
                                                   title: track.title, artist: track.artist) else {
            return .none
        }
        let fileURL = URL(fileURLWithPath: path).appendingPathComponent(match)
        guard let data = try? Data(contentsOf: fileURL),
              let text = LyricsTextDecoder.decode(data) else { return .none }

        let synced = LRCParser.parse(text)
        if !synced.isEmpty { return .synced(lines: synced, lrclibId: nil, approximate: false) }

        // No timestamps: treat it as plain lyrics (trimmed at the ends).
        var plain = text
            .split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        while plain.first?.isEmpty == true { plain.removeFirst() }
        while plain.last?.isEmpty == true { plain.removeLast() }
        return plain.isEmpty ? .none : .plain(lines: plain, lrclibId: nil)
    }
}

/// Lyrics fetcher pairing the local `.lrc` folder with a remote service.
/// The local folder is surfaced through `localOverride` (which the model
/// consults before its cache, so a local file is the user's explicit choice
/// and wins); `fetch` serves only the remote service. Blocking file I/O is
/// moved off the Swift-concurrency cooperative pool via `Task.detached`.
struct CompositeLyricsFetcher: LyricsFetching {
    let local: LocalLyricsReader
    let remote: LyricsFetching

    func fetch(track: LyricsTrack, options: LyricsFetchOptions) async throws -> LyricsResult {
        try await remote.fetch(track: track, options: options)
    }

    func localOverride(track: LyricsTrack, options: LyricsFetchOptions) async -> LyricsResult? {
        guard let folder = options.localFolder, !folder.isEmpty else { return nil }
        let reader = local
        let result = await Task.detached { reader.read(folder: folder, track: track) }.value
        if case .none = result { return nil }
        return result
    }
}
