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

/// Fetches lyrics from LRCLIB (https://lrclib.net). Unauthenticated GET;
/// sends only the track's title, artist, album and duration.
struct LRCLIBClient: LyricsFetching {
    struct HTTPError: Error {
        let statusCode: Int
    }

    /// Bounded timeouts so a stalled request can never hang a load.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// Generic client name plus app version; nothing that identifies the user.
    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "MacVisualizer/\(version)"
    }()

    /// Exact lookup first (title, artist, album, duration). When that
    /// finds nothing, finds an entry without timed lyrics, or finds one whose
    /// timings overrun its own length (mis-timed), search by title and artist
    /// and take the closest-duration match: the player's album name often
    /// differs from LRCLIB's. The decision logic is `LRCLIBMatch` (Core, tested).
    func fetch(track: LyricsTrack, options: LyricsFetchOptions) async throws -> LyricsResult {
        let exact = try await get(track)
        if LRCLIBMatch.exactSuffices(exact) { return exact?.result ?? .none }
        let found = (try? await search(track, allowLoose: options.allowApproximateMatch)) ?? .none
        return LRCLIBMatch.resolve(exact: exact, searched: found)
    }

    private func get(_ track: LyricsTrack) async throws -> LRCLIBRecord? {
        let (data, status) = try await request("get", [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int((Double(track.durationMs) / 1000).rounded()))),
        ])
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw HTTPError(statusCode: status) }
        return try JSONDecoder().decode(LRCLIBRecord.self, from: data)
    }

    private func search(_ track: LyricsTrack, allowLoose: Bool) async throws -> LyricsResult {
        let (data, status) = try await request("search", [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ])
        guard (200..<300).contains(status) else { throw HTTPError(statusCode: status) }
        let records = try JSONDecoder().decode([LRCLIBRecord].self, from: data)
        return LRCLIBMatch.best(records, durationMs: track.durationMs, allowLoose: allowLoose)?.result ?? .none
    }

    private func request(_ endpoint: String, _ query: [URLQueryItem]) async throws -> (Data, Int) {
        var components = URLComponents(string: "https://lrclib.net/api/\(endpoint)")!
        components.queryItems = query
        // URLComponents leaves "+" unescaped in a query, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Self.session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
