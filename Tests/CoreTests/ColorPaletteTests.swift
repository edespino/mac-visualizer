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

final class ColorPaletteTests: XCTestCase {
    func testClassicPresetExists() {
        let palette = ColorPalette.preset(named: "classic")
        XCTAssertNotNil(palette)
        XCTAssertGreaterThanOrEqual(palette!.stops.count, 2)
    }

    func testAllNamedPresetsExist() {
        // Every name advertised in SettingsView's palette picker must resolve
        // to a valid ColorPalette with at least two stops.
        let names = ["classic", "phosphor", "synthwave",
                     "inferno", "aurora", "ember", "ice", "mono"]
        for name in names {
            let p = ColorPalette.preset(named: name)
            XCTAssertNotNil(p, "missing preset: \(name)")
            XCTAssertGreaterThanOrEqual(p!.stops.count, 2, "preset \(name) needs ≥2 stops")
        }
    }

    func testInfernoTopIsBright() {
        let p = ColorPalette.preset(named: "inferno")!
        let top = p.sample(at: 1.0)
        XCTAssertGreaterThan(top.r, 0.9, "inferno top should be hot")
        XCTAssertGreaterThan(top.g, 0.9, "inferno top should be near white-hot")
    }

    func testIceTopIsCool() {
        let p = ColorPalette.preset(named: "ice")!
        let top = p.sample(at: 1.0)
        XCTAssertGreaterThan(top.b, 0.95, "ice top should be near-pure white/cyan")
        XCTAssertGreaterThan(top.g, 0.95)
    }

    func testMonoIsGrayscale() {
        let p = ColorPalette.preset(named: "mono")!
        // Every stop in the mono palette should be on the R=G≈B diagonal.
        for stop in p.stops {
            XCTAssertEqual(stop.r, stop.g, accuracy: 0.04,
                           "mono stop drifted off grayscale: r=\(stop.r) g=\(stop.g)")
            XCTAssertEqual(stop.g, stop.b, accuracy: 0.04,
                           "mono stop drifted off grayscale: g=\(stop.g) b=\(stop.b)")
        }
    }

    func testUnknownPresetReturnsNil() {
        XCTAssertNil(ColorPalette.preset(named: "no-such-palette"))
    }

    func testSampleAtStopsReturnsStopColors() {
        let palette = ColorPalette(stops: [
            RGBAColor(r: 0, g: 0, b: 0, a: 1),
            RGBAColor(r: 1, g: 1, b: 1, a: 1)
        ])
        let low = palette.sample(at: 0)
        let high = palette.sample(at: 1)
        XCTAssertEqual(low.r, 0, accuracy: 0.0001)
        XCTAssertEqual(high.r, 1, accuracy: 0.0001)
    }

    func testSampleInterpolatesMidpoint() {
        let palette = ColorPalette(stops: [
            RGBAColor(r: 0, g: 0, b: 0, a: 1),
            RGBAColor(r: 1, g: 1, b: 1, a: 1)
        ])
        let mid = palette.sample(at: 0.5)
        XCTAssertEqual(mid.r, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mid.g, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mid.b, 0.5, accuracy: 0.0001)
    }

    func testSampleClampsOutOfRange() {
        let palette = ColorPalette(stops: [
            RGBAColor(r: 0.2, g: 0, b: 0, a: 1),
            RGBAColor(r: 0.8, g: 0, b: 0, a: 1)
        ])
        XCTAssertEqual(palette.sample(at: -5).r, 0.2, accuracy: 0.0001)
        XCTAssertEqual(palette.sample(at: 5).r, 0.8, accuracy: 0.0001)
    }

    func testWarmPalettesHaveHDRTopStop() {
        // The HDR-upgraded warm palettes have at least one component > 1
        // at the top stop (used by the bloom pass to produce highlight blowout).
        for name in ["inferno", "ember", "aurora"] {
            let p = ColorPalette.preset(named: name)!
            let top = p.stops.last!
            let maxComponent = max(top.r, max(top.g, top.b))
            XCTAssertGreaterThan(maxComponent, 1.0,
                                 "\(name) top stop should have an HDR component > 1.0, got max=\(maxComponent)")
        }
    }
}