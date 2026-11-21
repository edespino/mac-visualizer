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

final class ColorPaletteNewPresetsTests: XCTestCase {
    private let originalEight = ["classic","phosphor","synthwave","inferno","aurora","ember","ice","mono"]
    private let newSix = ["viridis","plasma","spectrum","pastel","forest","oceanic"]
    private let expectedUnchangedStops: [String: [RGBAColor]] = [
        "classic": [
            RGBAColor(r: 0.0, g: 0.8, b: 0.2, a: 1),
            RGBAColor(r: 0.9, g: 0.9, b: 0.0, a: 1),
            RGBAColor(r: 0.9, g: 0.1, b: 0.1, a: 1)
        ],
        "phosphor": [
            RGBAColor(r: 0.0, g: 0.15, b: 0.0, a: 1),
            RGBAColor(r: 0.2, g: 1.0, b: 0.3, a: 1)
        ],
        "synthwave": [
            RGBAColor(r: 0.15, g: 0.0, b: 0.4, a: 1),
            RGBAColor(r: 0.9, g: 0.1, b: 0.6, a: 1),
            RGBAColor(r: 0.1, g: 0.9, b: 1.0, a: 1)
        ],
        "inferno": [
            RGBAColor(r: 0.05, g: 0.0, b: 0.05, a: 1),
            RGBAColor(r: 0.6,  g: 0.0, b: 0.0,  a: 1),
            RGBAColor(r: 1.0,  g: 0.4, b: 0.0,  a: 1),
            RGBAColor(r: 1.8,  g: 1.4, b: 0.3,  a: 1),
            RGBAColor(r: 3.0,  g: 2.5, b: 1.5,  a: 1)
        ],
        "aurora": [
            RGBAColor(r: 0.02, g: 0.05, b: 0.12, a: 1),
            RGBAColor(r: 0.0,  g: 0.55, b: 0.55, a: 1),
            RGBAColor(r: 0.15, g: 0.95, b: 0.6,  a: 1),
            RGBAColor(r: 0.65, g: 0.5,  b: 1.4,  a: 1),
            RGBAColor(r: 1.7,  g: 1.1,  b: 2.4,  a: 1)
        ],
        "ember": [
            RGBAColor(r: 0.02, g: 0.0,  b: 0.0,  a: 1),
            RGBAColor(r: 0.62, g: 0.27, b: 0.20, a: 1),
            RGBAColor(r: 1.0,  g: 0.49, b: 0.38, a: 1),
            RGBAColor(r: 1.7,  g: 1.4,  b: 0.9,  a: 1),
            RGBAColor(r: 2.5,  g: 2.2,  b: 1.5,  a: 1)
        ],
        "ice": [
            RGBAColor(r: 0.0, g: 0.0, b: 0.18, a: 1),
            RGBAColor(r: 0.0, g: 0.3, b: 0.7, a: 1),
            RGBAColor(r: 0.0, g: 0.85, b: 1.0, a: 1),
            RGBAColor(r: 0.7, g: 0.97, b: 1.0, a: 1),
            RGBAColor(r: 1.0, g: 1.0, b: 1.0, a: 1)
        ],
        "mono": [
            RGBAColor(r: 0.0, g: 0.0, b: 0.0, a: 1),
            RGBAColor(r: 0.25, g: 0.25, b: 0.27, a: 1),
            RGBAColor(r: 0.6, g: 0.6, b: 0.62, a: 1),
            RGBAColor(r: 0.92, g: 0.92, b: 0.95, a: 1),
            RGBAColor(r: 1.0, g: 1.0, b: 1.0, a: 1)
        ],
        "viridis": [
            RGBAColor(r: 0.26667, g: 0.00392, b: 0.32941, a: 1),
            RGBAColor(r: 0.23137, g: 0.32157, b: 0.54510, a: 1),
            RGBAColor(r: 0.12941, g: 0.56863, b: 0.54902, a: 1),
            RGBAColor(r: 0.36863, g: 0.78824, b: 0.38431, a: 1),
            RGBAColor(r: 0.99216, g: 0.90588, b: 0.14510, a: 1)
        ],
        "plasma": [
            RGBAColor(r: 0.05098, g: 0.03137, b: 0.52941, a: 1),
            RGBAColor(r: 0.80000, g: 0.27843, b: 0.47059, a: 1),
            RGBAColor(r: 0.97255, g: 0.58431, b: 0.25098, a: 1),
            RGBAColor(r: 0.94118, g: 0.97647, b: 0.12941, a: 1)
        ],
        "spectrum": [
            RGBAColor(r: 1.0, g: 0.0, b: 0.0, a: 1),
            RGBAColor(r: 1.0, g: 1.0, b: 0.0, a: 1),
            RGBAColor(r: 0.0, g: 1.0, b: 0.0, a: 1),
            RGBAColor(r: 0.0, g: 1.0, b: 1.0, a: 1),
            RGBAColor(r: 0.0, g: 0.0, b: 1.0, a: 1),
            RGBAColor(r: 1.0, g: 0.0, b: 1.0, a: 1)
        ],
        "forest": [
            RGBAColor(r: 0.10588, g: 0.22745, b: 0.10588, a: 1),
            RGBAColor(r: 0.18039, g: 0.36471, b: 0.20392, a: 1),
            RGBAColor(r: 0.41569, g: 0.65882, b: 0.30980, a: 1),
            RGBAColor(r: 0.47843, g: 0.32157, b: 0.18824, a: 1)
        ],
        "oceanic": [
            RGBAColor(r: 0.00392, g: 0.12549, b: 0.21961, a: 1),
            RGBAColor(r: 0.00784, g: 0.30196, b: 0.36078, a: 1),
            RGBAColor(r: 0.16863, g: 0.76863, b: 0.78824, a: 1)
        ]
    ]

    func testOriginalEightUnchangedAndFirst() {
        // The original presets must remain the first 8 entries, in order.
        XCTAssertEqual(Array(ColorPalette.orderedPresetNames.prefix(8)), originalEight)
    }

    func testAllFourteenResolve() {
        XCTAssertEqual(ColorPalette.orderedPresetNames.count, 14)
        for name in originalEight + newSix {
            // Real resolver (Task 0): ColorPalette.preset(named:) -> ColorPalette?
            XCTAssertNotNil(ColorPalette.preset(named: name), "\(name) must resolve")
        }
    }

    func testNewPalettesNonDegenerate() {
        for name in newSix {
            let p = ColorPalette.preset(named: name)!
            // Real stop accessor (Task 0): ColorPalette.stops: [RGBAColor]
            let comps = p.stops
            XCTAssertGreaterThanOrEqual(comps.count, 2, "\(name) needs >=2 stops")
            // not all-identical stops (avoid a flat/degenerate palette)
            let first = comps.first!
            XCTAssertFalse(comps.dropFirst().allSatisfy { $0 == first }, "\(name) is degenerate")
        }
    }

    func testPastelStopsAreNotNearWhite() {
        let pastel = ColorPalette.preset(named: "pastel")!
        XCTAssertEqual(pastel.stops.count, 4)
        for stop in pastel.stops {
            XCTAssertLessThanOrEqual(max(stop.r, max(stop.g, stop.b)), 0.85,
                                     "pastel stop needs bloom headroom: \(stop)")
            XCTAssertFalse(stop.r >= 0.85 && stop.g >= 0.85 && stop.b >= 0.85,
                           "pastel stop is near-white: \(stop)")
        }
    }

    func testPastelStopsHaveMeaningfulSaturation() {
        let pastel = ColorPalette.preset(named: "pastel")!
        for stop in pastel.stops {
            let saturation = channelSpread(stop)
            XCTAssertGreaterThanOrEqual(saturation, 0.30,
                                        "pastel stop needs visible hue; spread=\(saturation) stop=\(stop)")
        }
    }

    func testPastelSamplesStayHuedAndDistinguishable() {
        let pastel = ColorPalette.preset(named: "pastel")!
        let samples = [Float(0), 0.25, 0.5, 0.75, 1.0].map { pastel.sample(at: $0) }

        for sample in samples {
            XCTAssertLessThanOrEqual(max(sample.r, max(sample.g, sample.b)), 0.85,
                                     "pastel sample needs bloom headroom: \(sample)")
            // At least one channel must stay below 0.70 so interpolated colors
            // keep bloom headroom instead of collapsing toward white.
            XCTAssertLessThan(min(sample.r, min(sample.g, sample.b)), 0.70,
                              "pastel sample is too close to white: \(sample)")
        }

        for i in 0..<samples.count {
            for j in (i + 1)..<samples.count {
                let distance = colorDistance(samples[i], samples[j])
                XCTAssertGreaterThanOrEqual(distance, 0.10,
                                            "pastel samples at indexes \(i) and \(j) are not distinguishable; distance=\(distance)")
            }
        }
    }

    func testAllNonPastelPaletteStopsRemainByteIdentical() {
        for (name, expectedStops) in expectedUnchangedStops {
            XCTAssertEqual(ColorPalette.preset(named: name)?.stops, expectedStops,
                           "\(name) stops must remain unchanged")
        }
    }

    private func channelSpread(_ color: RGBAColor) -> Float {
        max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b))
    }

    private func colorDistance(_ lhs: RGBAColor, _ rhs: RGBAColor) -> Float {
        abs(lhs.r - rhs.r) + abs(lhs.g - rhs.g) + abs(lhs.b - rhs.b)
    }
}
