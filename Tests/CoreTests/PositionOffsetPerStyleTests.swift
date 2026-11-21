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

/// The position offset is stored per style (on `StyleProfile`) so each
/// visualization remembers its own placement. Old files carried one app-wide
/// offset, which must seed every profile so nothing moves on upgrade.
final class PositionOffsetPerStyleTests: XCTestCase {

    // MARK: helpers

    /// Encodes `s`, lets `mutate` edit the JSON root, and decodes the result.
    private func decode(_ s: VisualizerSettings,
                        mutate: (inout [String: Any]) -> Void) throws -> VisualizerSettings {
        let data = try JSONEncoder().encode(s)
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        mutate(&root)
        return try JSONDecoder().decode(VisualizerSettings.self,
                                        from: JSONSerialization.data(withJSONObject: root))
    }

    /// The `profiles` array is a flat [key, value, key, value, ...]; apply `edit` to each value.
    private func editProfiles(_ root: inout [String: Any], _ edit: (String, inout [String: Any]) -> Void) {
        var arr = root["profiles"] as! [Any]
        var i = 0
        while i + 1 < arr.count {
            var p = arr[i + 1] as! [String: Any]
            edit(arr[i] as! String, &p)
            arr[i + 1] = p
            i += 2
        }
        root["profiles"] = arr
    }

    // MARK: defaults

    func testDefaultsWireframeLowerOthersZero() {
        let d = VisualizerSettings.defaults
        for style in VisualizerStyle.allCases {
            let p = d.profiles[style]!
            XCTAssertEqual(p.positionOffsetX, 0, accuracy: 1e-6, "\(style)")
            XCTAssertEqual(p.positionOffsetY, style == .wireframe ? -0.07 : 0, accuracy: 1e-6, "\(style)")
        }
        XCTAssertEqual(StyleProfile.defaults(for: .wireframe).positionOffsetY, -0.07, accuracy: 1e-6)
        XCTAssertEqual(StyleProfile.defaults(for: .bars).positionOffsetY, 0, accuracy: 1e-6)
    }

    // MARK: forwarding

    func testForwardersProxyToCurrentProfileOnly() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .radial
        s.positionOffsetX = -0.4
        s.positionOffsetY = 0.25
        XCTAssertEqual(s.current.positionOffsetX, -0.4, accuracy: 1e-6)
        XCTAssertEqual(s.profiles[.radial]!.positionOffsetY, 0.25, accuracy: 1e-6)
        s.visualizerStyle = .iris            // another style is untouched
        XCTAssertEqual(s.positionOffsetX, 0, accuracy: 1e-6)
        XCTAssertEqual(s.positionOffsetY, 0, accuracy: 1e-6)
        s.visualizerStyle = .radial          // and radial remembers
        XCTAssertEqual(s.positionOffsetX, -0.4, accuracy: 1e-6)
        s.visualizerStyle = .wireframe
        XCTAssertEqual(s.positionOffsetY, -0.07, accuracy: 1e-6)
    }

    func testResetCurrentStyleRestoresItsOwnDefaultOffset() {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .wireframe
        s.positionOffsetY = 0.5
        s.resetCurrentStyle()
        XCTAssertEqual(s.positionOffsetY, -0.07, accuracy: 1e-6)
        s.visualizerStyle = .radial
        s.positionOffsetX = 0.3
        s.resetCurrentStyle()
        XCTAssertEqual(s.positionOffsetX, 0, accuracy: 1e-6)
    }

    // MARK: round trip

    func testRoundTripKeepsEachStylesOffset() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .radial
        s.positionOffsetX = 0.1; s.positionOffsetY = 0.2
        s.visualizerStyle = .iris
        s.positionOffsetX = -0.3; s.positionOffsetY = -0.4
        let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.profiles[.radial]!.positionOffsetX, 0.1, accuracy: 1e-6)
        XCTAssertEqual(decoded.profiles[.radial]!.positionOffsetY, 0.2, accuracy: 1e-6)
        XCTAssertEqual(decoded.profiles[.iris]!.positionOffsetX, -0.3, accuracy: 1e-6)
        XCTAssertEqual(decoded.profiles[.iris]!.positionOffsetY, -0.4, accuracy: 1e-6)
        XCTAssertEqual(decoded.profiles[.wireframe]!.positionOffsetY, -0.07, accuracy: 1e-6)
        XCTAssertEqual(decoded.profiles[.bars]!.positionOffsetY, 0, accuracy: 1e-6)
    }

    func testEncoderNoLongerWritesTopLevelOffset() throws {
        let data = try JSONEncoder().encode(VisualizerSettings.defaults)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(root["positionOffsetX"])
        XCTAssertNil(root["positionOffsetY"])
    }

    // MARK: migration from the app-wide offset

    func testAppWideOffsetSeedsEveryProfile() throws {
        // A 0.11-0.13 file: profiles without offset keys, one top-level offset.
        let d = try decode(.defaults) { root in
            editProfiles(&root) { _, p in p.removeValue(forKey: "positionOffsetX"); p.removeValue(forKey: "positionOffsetY") }
            root["positionOffsetX"] = 0.3
            root["positionOffsetY"] = -0.2
        }
        for style in VisualizerStyle.allCases {
            XCTAssertEqual(d.profiles[style]!.positionOffsetX, 0.3, accuracy: 1e-6, "\(style)")
            XCTAssertEqual(d.profiles[style]!.positionOffsetY, -0.2, accuracy: 1e-6, "\(style)")
        }
    }

    func testAppWideZeroOffsetKeepsWireframeWhereItWas() throws {
        // The saved offset was 0, so Wireframe's picture was at 0: it must not jump to -0.07.
        let d = try decode(.defaults) { root in
            editProfiles(&root) { _, p in p.removeValue(forKey: "positionOffsetX"); p.removeValue(forKey: "positionOffsetY") }
            root["positionOffsetX"] = 0.0
            root["positionOffsetY"] = 0.0
        }
        XCTAssertEqual(d.profiles[.wireframe]!.positionOffsetY, 0, accuracy: 1e-6)
    }

    func testFlatLegacyFileSeedsEveryProfileFromTopLevelOffset() throws {
        let json = #"{ "visualizerStyle": "radial", "positionOffsetX": 0.5, "positionOffsetY": 0.1 }"#
        let d = try JSONDecoder().decode(VisualizerSettings.self, from: Data(json.utf8))
        for style in VisualizerStyle.allCases {
            XCTAssertEqual(d.profiles[style]!.positionOffsetX, 0.5, accuracy: 1e-6, "\(style)")
            XCTAssertEqual(d.profiles[style]!.positionOffsetY, 0.1, accuracy: 1e-6, "\(style)")
        }
    }

    func testFileWithNoOffsetAnywhereUsesPerStyleDefaults() throws {
        let flat = try JSONDecoder().decode(VisualizerSettings.self, from: Data(#"{ "visualizerStyle": "bars" }"#.utf8))
        XCTAssertEqual(flat.profiles[.wireframe]!.positionOffsetY, -0.07, accuracy: 1e-6)
        XCTAssertEqual(flat.profiles[.radial]!.positionOffsetY, 0, accuracy: 1e-6)
        let profiled = try decode(.defaults) { root in
            editProfiles(&root) { _, p in p.removeValue(forKey: "positionOffsetX"); p.removeValue(forKey: "positionOffsetY") }
        }
        XCTAssertEqual(profiled.profiles[.wireframe]!.positionOffsetY, -0.07, accuracy: 1e-6)
        XCTAssertEqual(profiled.profiles[.radial]!.positionOffsetY, 0, accuracy: 1e-6)
    }

    // MARK: per-profile values win

    func testPerProfileValuesWinOverTopLevel() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .radial
        s.positionOffsetX = 0.6
        s.positionOffsetY = -0.6
        let d = try decode(s) { root in
            root["positionOffsetX"] = 0.9      // stray / stale top-level value
            root["positionOffsetY"] = 0.9
        }
        XCTAssertEqual(d.profiles[.radial]!.positionOffsetX, 0.6, accuracy: 1e-6)
        XCTAssertEqual(d.profiles[.radial]!.positionOffsetY, -0.6, accuracy: 1e-6)
        // Profiles that carry their own (default) values keep them as well.
        XCTAssertEqual(d.profiles[.iris]!.positionOffsetX, 0, accuracy: 1e-6)
        XCTAssertEqual(d.profiles[.wireframe]!.positionOffsetY, -0.07, accuracy: 1e-6)
    }

    func testProfileMissingKeysIsSeededWhileOthersKeepTheirs() throws {
        var s = VisualizerSettings.defaults
        s.visualizerStyle = .radial
        s.positionOffsetX = 0.6
        let d = try decode(s) { root in
            editProfiles(&root) { style, p in
                if style == "iris" { p.removeValue(forKey: "positionOffsetX"); p.removeValue(forKey: "positionOffsetY") }
            }
            root["positionOffsetX"] = 0.2
            root["positionOffsetY"] = 0.3
        }
        XCTAssertEqual(d.profiles[.radial]!.positionOffsetX, 0.6, accuracy: 1e-6)
        XCTAssertEqual(d.profiles[.iris]!.positionOffsetX, 0.2, accuracy: 1e-6)
        XCTAssertEqual(d.profiles[.iris]!.positionOffsetY, 0.3, accuracy: 1e-6)
    }

    func testStyleProfileDecodesMissingOffsetAsZero() throws {
        let p = try JSONDecoder().decode(StyleProfile.self, from: Data("{}".utf8))
        XCTAssertEqual(p.positionOffsetX, 0, accuracy: 1e-6)
        XCTAssertEqual(p.positionOffsetY, 0, accuracy: 1e-6)
    }
}
