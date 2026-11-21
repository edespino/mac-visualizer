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
import Combine

/// Fetches lyrics for a track from a lyrics service.
public protocol LyricsFetching {
    func fetch(track: LyricsTrack, options: LyricsFetchOptions) async throws -> LyricsResult
    /// Lyrics from a local source the user explicitly configured (a `.lrc`
    /// folder), which must win over the translation cache and the remote
    /// service. Returns nil when there is no local match. The default has
    /// no local source.
    func localOverride(track: LyricsTrack, options: LyricsFetchOptions) async -> LyricsResult?
}

public extension LyricsFetching {
    func localOverride(track: LyricsTrack, options: LyricsFetchOptions) async -> LyricsResult? { nil }
}

/// One displayed lyric pair.
public struct LyricRow: Equatable, Identifiable {
    /// Line index within the song.
    public var id: Int
    public var timeMs: Int
    /// Original-language text; empty for an instrumental gap.
    public var original: String
    /// Translated text, or nil when not available (yet). Never the
    /// original text standing in for a translation.
    public var translation: String?

    public init(id: Int, timeMs: Int, original: String, translation: String?) {
        self.id = id
        self.timeMs = timeMs
        self.original = original
        self.translation = translation
    }
}

/// What the overlay draws for the current track.
public struct LyricsDisplay: Equatable {
    public var rows: [LyricRow]
    /// True for songs already in English: one centered column.
    public var singleColumn: Bool
    /// The song this display is for, shown as the scrolling lyric-header. Carried
    /// on the display (not read live) so that during a cross-song transition each
    /// block shows its own song.
    public var title: String
    public var artist: String

    public init(rows: [LyricRow], singleColumn: Bool, title: String, artist: String) {
        self.rows = rows
        self.singleColumn = singleColumn
        self.title = title
        self.artist = artist
    }
}

/// Lyrics state for the current track, shown as one line in Settings.
public enum LyricsStatus: Equatable {
    case off
    case nothingPlaying
    case loading
    case noSyncedLyrics
    case instrumental
    case lyricsError
    case englishNoTranslation
    case translating
    case translated
    case noKey
    case translationFailed(String)

    public var message: String {
        switch self {
        case .off: return "Lyrics off"
        case .nothingPlaying: return "Nothing playing"
        case .loading: return "Loading lyrics..."
        case .noSyncedLyrics: return "No synced lyrics found"
        case .instrumental: return "Instrumental"
        case .lyricsError: return "Lyrics service error"
        case .englishNoTranslation: return "Synced lyrics (English, no translation)"
        case .translating: return "Translating..."
        case .translated: return "Synced lyrics, translated"
        case .noKey: return "No Gemini key set"
        case .translationFailed(let reason): return "Translation failed: \(reason)"
        }
    }
}

/// Orchestrates lyrics for the current track: cache, fetch, English
/// detection, translation. Publishes what the overlay should draw and a
/// status line. All network and file work runs off the main actor; a
/// result that arrives for a track that is no longer current, or after
/// lyrics were turned off, is dropped.
@MainActor
public final class LyricsModel: ObservableObject {
    @Published public private(set) var display: LyricsDisplay?
    @Published public private(set) var status: LyricsStatus = .off
    /// True while the shown lyrics come from an approximate (different
    /// length) recording, so the status line can warn that timing may drift.
    @Published public private(set) var approximateMatch = false

    private let fetcher: LyricsFetching
    private let makeProvider: (_ apiKey: String, _ model: String) -> TranslationProvider
    private let cache: LyricsCacheStore
    private let keyStore: GeminiKeyStore
    private let sleep: (Int) async -> Void

    private var tracker = PlaybackPositionTracker()
    private var lines: [LyricLine] = []
    private var enabled = false
    private var geminiModel = LyricsSettings.defaultGeminiModel
    private var acceptApproximateMatches = true
    private var localLyricsFolder = ""
    private var timingOffsetMs = 0
    private var currentKey: String?
    /// Bumped whenever the current load is superseded; results carry the
    /// generation they were started under and are dropped if it moved on.
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    private var taskSerial = 0
    /// Debounces a retry after the model name is edited (the text field
    /// writes on every keystroke).
    private var modelRetryTask: Task<Void, Never>?
    static let modelRetryDebounceMs = 800
    /// Synced lyrics shown without a translation, kept so a new key can
    /// retry the translation without refetching.
    private var pending: (track: LyricsTrack, lines: [LyricLine], lrclibId: Int?, approximate: Bool)?

    public init(fetcher: LyricsFetching,
                makeProvider: @escaping (_ apiKey: String, _ model: String) -> TranslationProvider,
                cache: LyricsCacheStore,
                keyStore: GeminiKeyStore,
                sleep: @escaping (Int) async -> Void) {
        self.fetcher = fetcher
        self.makeProvider = makeProvider
        self.cache = cache
        self.keyStore = keyStore
        self.sleep = sleep
    }

    /// Call on every player poll and whenever lyrics settings change.
    public func update(playback: PlaybackSnapshot?, settings: LyricsSettings) {
        let wasEnabled = enabled
        let modelChanged = settings.geminiModel != geminiModel
        // A changed lyric source (local folder or approximate-match policy)
        // re-fetches the current track so the new source takes effect now.
        let sourceChanged = settings.localLyricsFolder != localLyricsFolder
            || settings.acceptApproximateMatches != acceptApproximateMatches
        enabled = settings.enabled
        geminiModel = settings.geminiModel
        acceptApproximateMatches = settings.acceptApproximateMatches
        localLyricsFolder = settings.localLyricsFolder
        timingOffsetMs = settings.timingOffsetMs

        guard settings.enabled else {
            if wasEnabled || status != .off { clear(status: .off) }
            return
        }
        guard let playback else {
            if currentKey != nil || status != .nothingPlaying { clear(status: .nothingPlaying) }
            return
        }

        let key = LyricsCacheKey.make(for: playback.track)
        let trackChanged = key != currentKey
        if trackChanged { tracker.reset() }
        tracker.update(polledPositionMs: Double(playback.positionMs),
                       isPlaying: playback.isPlaying,
                       nowMs: playback.sampledAtMs)
        if trackChanged || !wasEnabled {
            currentKey = key
            startLoad(playback.track)
        } else if sourceChanged {
            startLoad(playback.track)
        } else if modelChanged, case .translationFailed = status, pending != nil {
            // The failure message tells the user to fix the model; do not
            // make them wait for the next track once they have.
            scheduleModelRetry()
        }
    }

    private func scheduleModelRetry() {
        modelRetryTask?.cancel()
        let model = geminiModel
        taskSerial += 1
        modelRetryTask = Task { [weak self] in
            guard let self else { return }
            await self.sleep(Self.modelRetryDebounceMs)
            guard !Task.isCancelled, self.geminiModel == model else { return }
            self.retryTranslation()
        }
    }

    /// Reruns the translation for lyrics already on screen. Bumps the
    /// generation so an attempt it supersedes cannot report a failure
    /// over the new one.
    private func retryTranslation() {
        guard enabled, let pending else { return }
        switch status {
        case .noKey, .translationFailed:
            generation += 1
            let gen = generation
            run { await $0.translate(pending.track, pending.lines, pending.lrclibId, pending.approximate, gen) }
        default:
            break
        }
    }

    /// Call after the key file changes so a track waiting on a key (or
    /// whose translation failed) retries without a track change.
    public func keyDidChange() {
        retryTranslation()
    }

    /// Index of the active line at the given monotonic clock time (ms),
    /// or -1 when there is none.
    public func activeIndex(atMs nowMs: Double) -> Int {
        guard !lines.isEmpty else { return -1 }
        return findActiveLine(lines, positionMs: Int(tracker.position(atMs: nowMs)) + timingOffsetMs)
    }

    /// Awaits any in-flight load. For tests.
    public func waitForIdle() async {
        var seen = -1
        while seen != taskSerial {
            seen = taskSerial
            await modelRetryTask?.value
            await loadTask?.value
        }
    }

    // MARK: - Loading

    private func clear(status newStatus: LyricsStatus) {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        modelRetryTask?.cancel()
        modelRetryTask = nil
        currentKey = nil
        pending = nil
        lines = []
        tracker.reset()
        if display != nil { display = nil }
        if approximateMatch { approximateMatch = false }
        if status != newStatus { status = newStatus }
    }

    /// The current fetch configuration from settings.
    private func fetchOptions() -> LyricsFetchOptions {
        LyricsFetchOptions(
            localFolder: localLyricsFolder.isEmpty ? nil : localLyricsFolder,
            allowApproximateMatch: acceptApproximateMatches)
    }

    private func run(_ body: @escaping (LyricsModel) async -> Void) {
        loadTask?.cancel()
        taskSerial += 1
        loadTask = Task { [weak self] in
            guard let self else { return }
            await body(self)
        }
    }

    private func isCurrent(_ gen: Int) -> Bool {
        gen == generation && enabled
    }

    private func startLoad(_ track: LyricsTrack) {
        generation += 1
        let gen = generation
        loadTask?.cancel()
        loadTask = nil
        modelRetryTask?.cancel()
        modelRetryTask = nil
        pending = nil
        lines = []
        display = nil
        approximateMatch = false
        guard track.isLookupable else {
            status = .nothingPlaying
            return
        }
        status = .loading
        run { await $0.load(track, gen) }
    }

    private func load(_ track: LyricsTrack, _ gen: Int) async {
        let options = fetchOptions()
        // A matching local file is the user's explicit choice: it wins over
        // the cache and the remote service, so a stale cached entry (or a
        // wrong LRCLIB match) never masks it.
        if !localLyricsFolder.isEmpty {
            let local = await fetcher.localOverride(track: track, options: options)
            guard isCurrent(gen) else { return }
            if let local {
                await present(local, track, gen)
                return
            }
        }

        let cache = self.cache
        let cached = await Task.detached { cache.read(track) }.value
        guard isCurrent(gen) else { return }
        // An approximate cached entry is only authoritative while approximate
        // matching is on. With it off, skip the cache and refetch strictly so
        // the toggle takes effect for a song already cached under a loose match.
        let approximateCacheDisallowed = cached?.approximate == true && !acceptApproximateMatches
        // An entry cached from a mis-timed record (its lines run past the end
        // of this track) is refetched, so a better record replaces it without a
        // cache wipe. Approximate entries are exempt: they are a different-length
        // recording by definition, and the mis-timed fallback is stamped
        // approximate, so this cannot loop.
        let mistimedCache = cached?.approximate != true && LRCLIBMatch.linesOverrun(
            lastLineMs: cached?.lines.map(\.timeMs).max() ?? 0, trackDurationMs: track.durationMs)
        if let cached, !cached.lines.isEmpty, !approximateCacheDisallowed, !mistimedCache {
            approximateMatch = cached.approximate == true
            lines = cached.lines.map { LyricLine(timeMs: $0.timeMs, text: $0.editedEs ?? $0.es) }
            // A cached entry may have been translated on an earlier run that
            // misclassified an English song. Re-check the source: if it is
            // English, show one centered column and drop the (degenerate)
            // translation, matching the fresh-fetch English path — so the fix
            // reaches songs already cached before it, with no cache wipe.
            if EnglishLyricsDetector.isEnglish(
                cached.lines.map { $0.editedEs ?? $0.es }.joined(separator: "\n")) {
                display = LyricsDisplay(
                    rows: cached.lines.enumerated().map { index, line in
                        LyricRow(id: index, timeMs: line.timeMs,
                                 original: line.editedEs ?? line.es, translation: nil)
                    },
                    singleColumn: true,
                    title: track.title, artist: track.artist)
                status = .englishNoTranslation
                return
            }
            // An entry saved without translations (cached as English) that no
            // longer reads as English falls through to a fresh fetch + translate
            // rather than showing an empty translation column.
            let untranslated = cached.lines.allSatisfy { ($0.editedEn ?? $0.en).isEmpty }
            if !untranslated {
                display = LyricsDisplay(
                    rows: cached.lines.enumerated().map { index, line in
                        LyricRow(id: index, timeMs: line.timeMs,
                                 original: line.editedEs ?? line.es,
                                 translation: line.editedEn ?? line.en)
                    },
                    singleColumn: false,
                    title: track.title, artist: track.artist)
                status = .translated
                return
            }
        }

        let result: LyricsResult
        do {
            result = try await fetcher.fetch(track: track, options: options)
        } catch {
            guard isCurrent(gen) else { return }
            display = headerOnlyDisplay(for: track)
            status = .lyricsError
            return
        }
        guard isCurrent(gen) else { return }
        await present(result, track, gen)
    }

    /// A header-only display (no lyric rows): a song with no lyrics still shows
    /// its title and performer where the lyrics would be (instrumental, or no
    /// lyrics available).
    private func headerOnlyDisplay(for track: LyricsTrack) -> LyricsDisplay {
        LyricsDisplay(rows: [], singleColumn: true, title: track.title, artist: track.artist)
    }

    /// Shows a fetched (remote or local) result and, for a non-English
    /// synced result, reuses a matching cached translation or translates.
    private func present(_ result: LyricsResult, _ track: LyricsTrack, _ gen: Int) async {
        switch result {
        case .none, .plain:
            display = headerOnlyDisplay(for: track)
            status = .noSyncedLyrics
        case .instrumental:
            display = headerOnlyDisplay(for: track)
            status = .instrumental
        case .synced(let synced, let lrclibId, let approximate):
            let hasText = synced.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            guard hasText else {
                display = headerOnlyDisplay(for: track)
                status = .instrumental
                return
            }
            approximateMatch = approximate
            lines = synced
            let rows = synced.enumerated().map { index, line in
                LyricRow(id: index, timeMs: line.timeMs, original: line.text, translation: nil)
            }
            if EnglishLyricsDetector.isEnglish(synced.map(\.text).joined(separator: "\n")) {
                display = LyricsDisplay(rows: rows, singleColumn: true, title: track.title, artist: track.artist)
                status = .englishNoTranslation
                // Cache English lyrics too (no translation: `en` stays empty), so a
                // song played again needs no lookup. Exact matches only: an
                // approximate one may be replaced by a better record later.
                if !approximate {
                    let entry = TranslationEntry(
                        title: track.title, artist: track.artist, titleEn: nil, lrclibId: lrclibId,
                        lines: synced.map { TranslationLine(timeMs: $0.timeMs, es: $0.text, en: "") })
                    let cache = self.cache
                    await Task.detached {
                        do {
                            try cache.write(entry, for: track)
                        } catch {
                            Log.lyrics.error("Failed to write lyrics cache: \(String(describing: error), privacy: .public)")
                        }
                    }.value
                }
                return
            }
            display = LyricsDisplay(rows: rows, singleColumn: false, title: track.title, artist: track.artist)
            // Reuse a cached translation only when it is for these exact
            // source lines, so a local override replaces a stale remote entry
            // and an edited local file re-translates instead of showing old text.
            if let reuse = await cachedTranslationRows(for: track, matching: synced) {
                guard isCurrent(gen) else { return }
                display = LyricsDisplay(rows: reuse, singleColumn: false, title: track.title, artist: track.artist)
                status = .translated
                return
            }
            guard isCurrent(gen) else { return }
            pending = (track, synced, lrclibId, approximate)
            await translate(track, synced, lrclibId, approximate, gen)
        }
    }

    /// Rows built from a cached translation when it is for exactly these
    /// source lines (original text equal, in order), else nil.
    private func cachedTranslationRows(for track: LyricsTrack, matching synced: [LyricLine]) async -> [LyricRow]? {
        let cache = self.cache
        let cached = await Task.detached { cache.read(track) }.value
        guard let cached, cached.lines.map(\.es) == synced.map(\.text) else { return nil }
        return synced.enumerated().map { index, line in
            LyricRow(id: index, timeMs: line.timeMs, original: line.text,
                     translation: cached.lines[index].editedEn ?? cached.lines[index].en)
        }
    }

    private func translate(_ track: LyricsTrack, _ synced: [LyricLine], _ lrclibId: Int?,
                           _ approximate: Bool, _ gen: Int) async {
        let keyStore = self.keyStore
        let key = await Task.detached { keyStore.read() }.value
        guard isCurrent(gen) else { return }
        guard let key else {
            // No API key: show the lyrics untranslated in a single centered column
            // (the layout English songs use), for ANY language — not a two-column
            // view with a blank translation side. `pending` stays set, so adding a
            // key later retries the translation (see keyDidChange).
            display = LyricsDisplay(
                rows: synced.enumerated().map { index, line in
                    LyricRow(id: index, timeMs: line.timeMs, original: line.text, translation: nil)
                },
                singleColumn: true,
                title: track.title, artist: track.artist)
            status = .noKey
            return
        }
        status = .translating
        let provider = makeProvider(key, geminiModel)
        let meta = TranslationMeta(title: track.title, artist: track.artist, titleFirst: true)
        do {
            let result = try await LyricsTranslator.translateWithTitle(
                provider: provider, lines: synced.map(\.text), meta: meta, sleep: sleep)
            guard isCurrent(gen) else { return }
            guard result.en.count == synced.count else {
                status = .translationFailed("Translation returned the wrong number of lines")
                return
            }
            display = LyricsDisplay(
                rows: synced.enumerated().map { index, line in
                    LyricRow(id: index, timeMs: line.timeMs, original: line.text, translation: result.en[index])
                },
                singleColumn: false,
                title: track.title, artist: track.artist)
            status = .translated
            pending = nil
            let entry = TranslationEntry(
                title: track.title, artist: track.artist, titleEn: result.titleEn, lrclibId: lrclibId,
                lines: synced.enumerated().map { index, line in
                    TranslationLine(timeMs: line.timeMs, es: line.text, en: result.en[index])
                },
                approximate: approximate ? true : nil)
            let cache = self.cache
            await Task.detached {
                do {
                    try cache.write(entry, for: track)
                } catch {
                    Log.lyrics.error("Failed to write lyrics cache: \(String(describing: error), privacy: .public)")
                }
            }.value
        } catch let failure as TranslationFailed {
            guard isCurrent(gen) else { return }
            status = .translationFailed(failure.message)
        } catch {
            // Cancellation (track changed, lyrics turned off) lands here
            // with a moved-on generation and is dropped.
            guard isCurrent(gen) else { return }
            status = .translationFailed("Translation was interrupted")
        }
    }
}
