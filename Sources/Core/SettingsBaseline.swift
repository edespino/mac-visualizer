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

/// The two reset targets behind every "reset to default" control:
///
/// - **baseline** ("my defaults"): a whole `VisualizerSettings` the user saved,
///   or, when none is saved (or the file is unreadable), the factory defaults.
/// - **factory**: the built-in defaults.
///
/// Values are looked up by key path so call sites never retype a default. Cheap
/// value lookups only; file I/O happens in `load`/`save`/`clear`, never per read.
///
/// Key paths must be STORED-field paths. The forwarding properties on
/// `VisualizerSettings` (`gain`, `paletteName`, ...) resolve against the
/// snapshot's *own* current style, so per-style fields use the `StyleProfile`
/// overloads with an explicit style.
public struct SettingsBaseline: Equatable {
    public private(set) var snapshot: VisualizerSettings?
    /// File modification time of the snapshot, when loaded from / saved to disk.
    public private(set) var savedAt: Date?

    public init(snapshot: VisualizerSettings? = nil, savedAt: Date? = nil) {
        self.snapshot = snapshot
        self.savedAt = savedAt
    }

    public var hasUserDefaults: Bool { snapshot != nil }

    /// The whole-settings baseline: the snapshot, else factory.
    public var effective: VisualizerSettings { snapshot ?? .defaults }

    // MARK: App-wide fields

    public func baselineValue<T>(_ keyPath: WritableKeyPath<VisualizerSettings, T>) -> T {
        effective[keyPath: keyPath]
    }

    public func factoryValue<T>(_ keyPath: WritableKeyPath<VisualizerSettings, T>) -> T {
        VisualizerSettings.defaults[keyPath: keyPath]
    }

    // MARK: Per-style profile fields

    public func baselineProfile(for style: VisualizerStyle) -> StyleProfile {
        snapshot?.profiles[style] ?? .defaults(for: style)
    }

    public func baselineValue<T>(_ keyPath: WritableKeyPath<StyleProfile, T>,
                                 style: VisualizerStyle) -> T {
        baselineProfile(for: style)[keyPath: keyPath]
    }

    public func factoryValue<T>(_ keyPath: WritableKeyPath<StyleProfile, T>,
                                style: VisualizerStyle) -> T {
        StyleProfile.defaults(for: style)[keyPath: keyPath]
    }

    // MARK: Whole-style comparison

    /// True when `resetCurrentStyle(to: effective)` would change `settings`.
    public func currentStyleDiffersFromBaseline(_ settings: VisualizerSettings) -> Bool {
        Self.resetWouldChange(settings, to: effective)
    }

    /// True when `resetCurrentStyle(to: .defaults)` would change `settings`.
    public func currentStyleDiffersFromFactory(_ settings: VisualizerSettings) -> Bool {
        Self.resetWouldChange(settings, to: .defaults)
    }

    /// The snapshot that results from saving only `live`'s active style: the
    /// existing snapshot (or factory) with that style's profile and exclusive
    /// top-level fields copied from `live`. Everything else, including the
    /// snapshot's own `visualizerStyle`, is untouched.
    public func snapshotSavingCurrentStyle(of live: VisualizerSettings) -> VisualizerSettings {
        var out = effective
        let originalStyle = out.visualizerStyle
        out.visualizerStyle = live.visualizerStyle
        out.resetCurrentStyle(to: live)
        out.visualizerStyle = originalStyle
        return out
    }

    private static func resetWouldChange(_ settings: VisualizerSettings,
                                         to base: VisualizerSettings) -> Bool {
        var copy = settings
        copy.resetCurrentStyle(to: base)
        return copy != settings
    }

    // MARK: Persistence

    /// `<Application Support>/MacVisualizer/user-defaults.json`, next to settings.json.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("MacVisualizer", isDirectory: true)
            .appendingPathComponent("user-defaults.json")
    }

    /// Loads the snapshot. A missing, unreadable or undecodable file yields the
    /// factory baseline; the file is left in place (never moved or rewritten).
    public static func load(from url: URL) -> SettingsBaseline {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(VisualizerSettings.self, from: data) else {
            return SettingsBaseline()
        }
        return SettingsBaseline(snapshot: settings, savedAt: modificationDate(of: url))
    }

    /// Writes `settings` as the snapshot and returns the resulting baseline.
    @discardableResult
    public static func save(_ settings: VisualizerSettings, to url: URL) throws -> SettingsBaseline {
        try settings.save(to: url)
        return SettingsBaseline(snapshot: settings, savedAt: modificationDate(of: url) ?? Date())
    }

    /// Deletes the snapshot file. A file that is already absent is not an error.
    public static func clear(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
