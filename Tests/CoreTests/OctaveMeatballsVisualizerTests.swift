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

final class OctaveMeatballsVisualizerTests: XCTestCase {
    func testReturnsNoGeometry() {
        // OctaveMeatballsVisualizer is a stub: the fullscreen fragment shader
        // (octave_meatballs_fs) handles rendering, so makeVertices() is empty.
        let viz = OctaveMeatballsVisualizer()
        let frame = AudioFrame(bands: [0.5, 0.5, 0.5], bandPeaks: [], waveform: [],
                               rms: 0.5, peak: 0.5, timestamp: 0)
        let verts = viz.makeVertices(frame: frame, settings: .defaults, aspect: 1)
        XCTAssertTrue(verts.isEmpty)
    }

    func testStyleMetadataAndFactory() {
        XCTAssertTrue(VisualizerStyle.octaveMeatballs.makeVisualizer() is OctaveMeatballsVisualizer)
        XCTAssertEqual(VisualizerStyle.octaveMeatballs.displayName, "Octave Meatballs")
        XCTAssertFalse(VisualizerStyle.octaveMeatballs.usesRoundParticles)
    }

    func testTakesShaderPath() {
        // Always shader-driven, independent of settings.
        var settings = VisualizerSettings.defaults
        settings.visualizerStyle = .octaveMeatballs
        XCTAssertEqual(VisualizerStyle.octaveMeatballs.customShader(settings: settings), .octaveMeatballs)
    }

    /// Relative-order pin (position from the END shifts every time a style is
    /// appended, so assert neighbors instead).
    func testWrapsBetweenPolartoneAndStarNest() {
        XCTAssertEqual(VisualizerStyle.octaveMeatballs.next, .starNest)
        XCTAssertEqual(VisualizerStyle.octaveMeatballs.previous, .polartone)
    }

    func testShaderKindCaseExists() {
        XCTAssertTrue(ShaderKind.allCases.contains(.octaveMeatballs))
    }
}
