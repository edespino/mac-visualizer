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
import XCTest
@testable import MacVisualizerCore

final class StyleProfileTests: XCTestCase {
    func testDefaultsAreSensible() {
        let d = StyleProfile.defaults
        XCTAssertEqual(d.paletteName, "classic")
        XCTAssertEqual(d.barCount, 48)
        XCTAssertTrue(d.glowEnabled)
        XCTAssertTrue(d.peakHoldEnabled)
        // Track overlay, always-on-top and frame rate are app-wide now; see
        // VisualizerSettingsTests for their defaults.
    }

    func testJSONRoundTrips() throws {
        var p = StyleProfile.defaults
        p.gain = 2.5
        p.paletteName = "phosphor"
        p.glowEnabled = false
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func testVoronoiRenderModeDefaultsCells() {
        XCTAssertEqual(StyleProfile.defaults.voronoiRenderMode, .cells)
    }

    func testHeightfieldRenderModeDefaultsWireframe() {
        XCTAssertEqual(StyleProfile.defaults.heightfieldRenderMode, .wireframe)
    }

    func testLavaLampRenderModeDefaultsShader() {
        XCTAssertEqual(StyleProfile.defaults.lavaLampRenderMode, .shader)
    }

    func testRenderModesRoundtripCodable() throws {
        var p = StyleProfile.defaults
        p.voronoiRenderMode = .blobs
        p.heightfieldRenderMode = .solid
        p.lavaLampRenderMode = .marchingSquares
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: data)
        XCTAssertEqual(decoded.voronoiRenderMode, .blobs)
        XCTAssertEqual(decoded.heightfieldRenderMode, .solid)
        XCTAssertEqual(decoded.lavaLampRenderMode, .marchingSquares)
    }

    // positionOffsetX/Y are per-style again; see PositionOffsetPerStyleTests.

    func testBarCountClampedToPositiveOnDecode() throws {
        // A persisted barCount <= 0 must not survive decode — BandMapper has
        // `precondition(bandCount > 0)`, so an unvalidated value crashes the app.
        for bad in [0, -5, Int.min] {
            let json = "{ \"barCount\": \(bad) }".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(StyleProfile.self, from: json)
            XCTAssertGreaterThanOrEqual(decoded.barCount, 1, "barCount \(bad) must clamp to >= 1")
        }
    }

    func testValidBarCountSurvivesDecodeUnchanged() throws {
        let json = "{ \"barCount\": 32 }".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: json)
        XCTAssertEqual(decoded.barCount, 32)
    }

    /// An unknown persisted enum raw value in a profile must fall back to that
    /// field's default instead of throwing away the whole profile (and with it
    /// the entire settings load).
    func testUnknownEnumRawValuesFallBackToDefaults() throws {
        let json = """
        { "backgroundStyle": "sparkles",
          "voronoiRenderMode": "hexagons",
          "voronoiShapeMode": "spin",
          "heightfieldRenderMode": "points",
          "lavaLampRenderMode": "metaballs",
          "gain": 2.5 }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: json)
        let d = StyleProfile.defaults
        XCTAssertEqual(decoded.backgroundStyle, d.backgroundStyle)
        XCTAssertEqual(decoded.voronoiRenderMode, d.voronoiRenderMode)
        XCTAssertEqual(decoded.voronoiShapeMode, d.voronoiShapeMode)
        XCTAssertEqual(decoded.heightfieldRenderMode, d.heightfieldRenderMode)
        XCTAssertEqual(decoded.lavaLampRenderMode, d.lavaLampRenderMode)
        // Sibling fields must survive the bad enum values.
        XCTAssertEqual(decoded.gain, 2.5)
    }

    func testKnownEnumRawValuesStillDecode() throws {
        let json = """
        { "heightfieldRenderMode": "solid", "voronoiRenderMode": "softCells" }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: json)
        XCTAssertEqual(decoded.heightfieldRenderMode, .solid)
        XCTAssertEqual(decoded.voronoiRenderMode, .softCells)
    }

    func testEnabledDefaultsTrue() {
        XCTAssertTrue(StyleProfile.defaults.enabled)
    }

    func testEnabledRoundTripsCodable() throws {
        var p = StyleProfile.defaults
        p.enabled = false
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: data)
        XCTAssertFalse(decoded.enabled)
    }

    func testLegacyJSONWithoutEnabledDecodesTrue() throws {
        // Old settings.json predates the enabled flag — it must default to true
        // (tolerant decode), and sibling fields must survive.
        let json = """
        { "gain": 2.5 }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: json)
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.gain, 2.5)
    }

    func testLegacyStyleProfileJSONDecodesSafely() throws {
        // Old JSON without the new render-mode fields — they should default.
        let legacy = """
        { "paletteName": "phosphor", "customStops": [], "gain": 1.0, "barCount": 48,
          "smoothing": 0.6, "peakHoldEnabled": true, "glowEnabled": true, "glowIntensity": 0.5,
          "overlayEnabled": true, "overlayPosition": "topTrailing", "overlayOpacity": 0.8,
          "alwaysOnTop": false, "targetFPS": 60, "backgroundStyle": "solid" }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StyleProfile.self, from: legacy)
        XCTAssertEqual(decoded.voronoiRenderMode, .cells)
        XCTAssertEqual(decoded.heightfieldRenderMode, .wireframe)
        XCTAssertEqual(decoded.lavaLampRenderMode, .shader)
    }
}