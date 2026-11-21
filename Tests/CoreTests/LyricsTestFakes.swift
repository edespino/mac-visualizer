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
@testable import MacVisualizerCore

/// Scripted translation provider. `impl` receives the lyric lines parsed
/// back out of the prompt and the 1-based call number, and returns the
/// lines the "model" answers with (encoded as a JSON array).
final class FakeTranslationProvider: TranslationProvider {
    private(set) var calls: [[String]] = []
    private(set) var prompts: [String] = []
    private let impl: ([String], Int) async throws -> [String]

    init(_ impl: @escaping ([String], Int) async throws -> [String]) {
        self.impl = impl
    }

    func generate(prompt: String) async throws -> String {
        let lines = Self.lines(from: prompt)
        calls.append(lines)
        prompts.append(prompt)
        let out = try await impl(lines, calls.count)
        return String(data: try JSONEncoder().encode(out), encoding: .utf8)!
    }

    static func lines(from prompt: String) -> [String] {
        guard let json = prompt.components(separatedBy: "\n").last,
              let data = json.data(using: .utf8),
              let lines = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return lines
    }
}

/// Records requested sleep durations (ms) and returns immediately.
final class SleepRecorder {
    private(set) var delays: [Int] = []
    func sleep(_ ms: Int) async { delays.append(ms) }
}

func numberedLines(_ n: Int) -> [String] {
    (1...n).map { "linea \($0)" }
}

/// A one-shot gate a fake can wait on until the test releases it.
actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

struct FakeFetchError: Error {}

/// Scripted lyrics fetcher keyed by track title.
final class FakeLyricsFetcher: LyricsFetching {
    private let lock = NSLock()
    private var _calls: [LyricsTrack] = []
    private var _lastOptions: LyricsFetchOptions?
    private var _localOverrides: [String: LyricsResult] = [:]
    var results: [String: LyricsResult] = [:]
    var failing: Set<String> = []
    var gates: [String: TestGate] = [:]

    var calls: [LyricsTrack] { lock.withLock { _calls } }
    var lastOptions: LyricsFetchOptions? { lock.withLock { _lastOptions } }
    /// Local-folder matches keyed by track title; drives `localOverride`.
    var localOverrides: [String: LyricsResult] {
        get { lock.withLock { _localOverrides } }
        set { lock.withLock { _localOverrides = newValue } }
    }

    func fetch(track: LyricsTrack, options: LyricsFetchOptions) async throws -> LyricsResult {
        lock.withLock { _calls.append(track); _lastOptions = options }
        if let gate = gates[track.title] { await gate.wait() }
        if failing.contains(track.title) { throw FakeFetchError() }
        return results[track.title] ?? .none
    }

    func localOverride(track: LyricsTrack, options: LyricsFetchOptions) async -> LyricsResult? {
        lock.withLock { _localOverrides[track.title] }
    }
}
