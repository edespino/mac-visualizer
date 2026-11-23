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
import os

/// Minimal logging facility wrapping `os.Logger`.
///
/// One shared subsystem, one `Logger` per category. Categories are added here
/// as subsystems start emitting diagnostics; keep them coarse (one per module
/// concern) so log filtering stays useful. Use via `Log.<category>.error("…")`.
public enum Log {
    /// Subsystem string for all loggers. Derived from the running app's bundle id
    /// so it tracks the real identifier instead of drifting from it; falls back to
    /// the placeholder when there is no main-bundle id (e.g. unit-test host). See
    /// CLAUDE.md "Bundle ID" gotcha.
    public static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.MacVisualizer"

    /// Settings load/save/migration diagnostics.
    public static let settings = Logger(subsystem: subsystem, category: "settings")

    /// Core Audio process-tap capture diagnostics.
    public static let audioCapture = Logger(subsystem: subsystem, category: "audio-capture")

    /// Window identity / frame-restore diagnostics (AppKit layout-loop crash hunt).
    public static let window = Logger(subsystem: subsystem, category: "window")

    /// Lyrics fetch/translate/cache diagnostics. Never log lyric text or the API key.
    public static let lyrics = Logger(subsystem: subsystem, category: "lyrics")

    /// RealityKit Spinner setup/render diagnostics (a failure makes the Tri-wing Spinner fall back to the disc shader).
    public static let spinnerRender = Logger(subsystem: subsystem, category: "spinner-render")

    /// Bearing hum audio engine diagnostics.
    public static let spinnerHum = Logger(subsystem: subsystem, category: "spinner-hum")
}
