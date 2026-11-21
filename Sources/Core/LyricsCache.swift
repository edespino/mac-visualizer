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
import CryptoKit

/// One cached lyric line: original and translation, plus optional manual
/// edits (unused until line editing exists; present so the file format
/// does not change later).
public struct TranslationLine: Codable, Equatable {
    public var timeMs: Int
    public var es: String
    public var en: String
    public var editedEs: String?
    public var editedEn: String?

    public init(timeMs: Int, es: String, en: String, editedEs: String? = nil, editedEn: String? = nil) {
        self.timeMs = timeMs
        self.es = es
        self.en = en
        self.editedEs = editedEs
        self.editedEn = editedEn
    }
}

/// The cached translation of one track. Mirrors the web app's entry shape.
public struct TranslationEntry: Codable, Equatable {
    public var title: String
    public var artist: String
    public var titleEn: String?
    public var lrclibId: Int?
    public var lines: [TranslationLine]
    /// True when these lyrics came from an approximate (different-length)
    /// LRCLIB recording. Optional and omitted when false so old cache files
    /// decode unchanged.
    public var approximate: Bool?

    public init(title: String, artist: String, titleEn: String?, lrclibId: Int?,
                lines: [TranslationLine], approximate: Bool? = nil) {
        self.title = title
        self.artist = artist
        self.titleEn = titleEn
        self.lrclibId = lrclibId
        self.lines = lines
        self.approximate = approximate
    }
}

public enum LyricsCacheKey {
    /// Lowercase hex SHA-256 of the normalized title, artist, album and
    /// whole-second duration joined by U+001F. Normalization: lowercased,
    /// trimmed, inner whitespace runs collapsed to one space. Works for
    /// any player (no Spotify track id needed).
    public static func make(for track: LyricsTrack) -> String {
        let fields = [
            normalize(track.title), normalize(track.artist), normalize(track.album),
            String(track.durationMs / 1000),
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

/// Disk cache for translations: one JSON file per track. These files are
/// user data derived from copyrighted lyrics and live outside the repo.
public struct LyricsCacheStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `<Application Support>/MacVisualizer/lyrics`, next to settings.json.
    public static func defaultDirectory() -> URL {
        VisualizerSettings.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("lyrics", isDirectory: true)
    }

    private func fileURL(_ track: LyricsTrack) -> URL {
        directory.appendingPathComponent("\(LyricsCacheKey.make(for: track)).json")
    }

    /// The cached entry, or nil when missing or undecodable. A corrupt
    /// file is a cache miss; the next successful write replaces it.
    public func read(_ track: LyricsTrack) -> TranslationEntry? {
        guard let data = try? Data(contentsOf: fileURL(track)) else { return nil }
        return try? JSONDecoder().decode(TranslationEntry.self, from: data)
    }

    /// Writes via a temp file and rename, so a crash never leaves a
    /// half-written entry at the final path.
    public func write(_ entry: TranslationEntry, for track: LyricsTrack) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entry).write(to: fileURL(track), options: .atomic)
    }
}

/// The Gemini API key, kept in its own owner-only file outside the repo
/// and outside settings.json. (The Keychain was rejected for now: the app
/// is ad-hoc signed, so it would prompt after every rebuild.)
public struct GeminiKeyStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `<Application Support>/MacVisualizer/gemini-key`.
    public static func defaultFileURL() -> URL {
        VisualizerSettings.defaultFileURL()
            .deletingLastPathComponent()
            .appendingPathComponent("gemini-key")
    }

    /// The stored key, or nil when missing or blank.
    public func read() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// Stores the trimmed key with owner-only permissions. A blank value
    /// removes the file.
    public func write(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let fm = FileManager.default
        if trimmed.isEmpty {
            if fm.fileExists(atPath: fileURL.path) { try fm.removeItem(at: fileURL) }
            return
        }
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Create the file owner-only before any key bytes are written, so
        // the key is never readable by others even briefly.
        if fm.fileExists(atPath: fileURL.path) { try fm.removeItem(at: fileURL) }
        guard fm.createFile(atPath: fileURL.path, contents: Data(trimmed.utf8),
                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
