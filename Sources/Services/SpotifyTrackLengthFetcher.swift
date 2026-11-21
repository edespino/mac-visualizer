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

/// Reads a track's true length from its public Spotify page. Sends only the
/// track id, with a generic client name. Stops reading as soon as the length
/// is found (it sits in the first ~15 KB of a ~290 KB page). Any failure is
/// nil: lyrics then use the length the player reported, as before.
enum SpotifyTrackLengthFetcher {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 20
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// Bytes read before giving up on finding the length.
    private static let maxBytes = 96 * 1024

    static func durationSeconds(trackID: String) async -> Int? {
        guard let url = SpotifyTrackPage.url(forTrackID: trackID) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("MacVisualizer", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { return nil }
            var buffer = [UInt8]()
            buffer.reserveCapacity(32 * 1024)
            for try await byte in bytes {
                buffer.append(byte)
                // Check at each tag end once the marker could be present.
                if byte == UInt8(ascii: ">"), buffer.count > 512,
                   let seconds = SpotifyTrackPage.durationSeconds(inHTML: String(decoding: buffer.suffix(256), as: UTF8.self)) {
                    return seconds
                }
                if buffer.count >= maxBytes { break }
            }
            return SpotifyTrackPage.durationSeconds(inHTML: String(decoding: buffer, as: UTF8.self))
        } catch {
            return nil
        }
    }
}
