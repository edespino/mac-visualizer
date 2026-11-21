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

final class InputControlsTests: XCTestCase {
    private let none = ModifierState()

    // MARK: keys

    func testBareKeysMap() {
        let table: [(String, ControlAction)] = [
            ("h", .previousVisualization), ("l", .nextVisualization),
            ("j", .nextPalette), ("k", .previousPalette),
            ("r", .randomVisualization),
            (",", .previousSong), (".", .nextSong),
            (" ", .togglePlayPause), ("f", .toggleFullscreen),
            ("?", .toggleCheatSheet),
        ]
        for (ch, action) in table {
            XCTAssertEqual(keyAction(characters: ch, keyCode: 0, modifiers: none, isRepeat: false), action, ch)
        }
    }

    func testEscapeMapsToDismissByKeyCode() {
        XCTAssertEqual(keyAction(characters: "\u{1B}", keyCode: 53, modifiers: none, isRepeat: false), .dismissCheatSheet)
    }

    func testLettersAreCaseInsensitive() {
        XCTAssertEqual(keyAction(characters: "L", keyCode: 37, modifiers: ModifierState(shift: true), isRepeat: false), .nextVisualization)
        XCTAssertEqual(keyAction(characters: "H", keyCode: 4, modifiers: none, isRepeat: false), .previousVisualization)
    }

    func testQuestionMarkWorksWithShiftHeld() {
        XCTAssertEqual(keyAction(characters: "?", keyCode: 44, modifiers: ModifierState(shift: true), isRepeat: false), .toggleCheatSheet)
    }

    func testCommandControlOptionBlockKeys() {
        for m in [ModifierState(command: true), ModifierState(control: true), ModifierState(option: true)] {
            XCTAssertNil(keyAction(characters: "l", keyCode: 37, modifiers: m, isRepeat: false))
            XCTAssertNil(keyAction(characters: " ", keyCode: 49, modifiers: m, isRepeat: false))
        }
    }

    func testRepeatsIgnored() {
        XCTAssertNil(keyAction(characters: "l", keyCode: 37, modifiers: none, isRepeat: true))
        XCTAssertNil(keyAction(characters: "\u{1B}", keyCode: 53, modifiers: none, isRepeat: true))
    }

    func testUnmappedKeysIgnored() {
        XCTAssertNil(keyAction(characters: "x", keyCode: 7, modifiers: none, isRepeat: false))
        XCTAssertNil(keyAction(characters: "", keyCode: 0, modifiers: none, isRepeat: false))
        XCTAssertNil(keyAction(characters: "hh", keyCode: 0, modifiers: none, isRepeat: false))
    }

    // MARK: mouse

    func testModifierClicks() {
        let shift = ModifierState(shift: true)
        XCTAssertEqual(mouseBinding(button: .left, clickCount: 1, held: shift, configured: .shift)?.action, .previousVisualization)
        XCTAssertEqual(mouseBinding(button: .right, clickCount: 1, held: shift, configured: .shift)?.action, .nextVisualization)
        XCTAssertEqual(mouseBinding(button: .middle, clickCount: 1, held: shift, configured: .shift)?.action, .randomVisualization)
        XCTAssertEqual(mouseBinding(button: .left, clickCount: 1, held: shift, configured: .shift)?.consume, true)
    }

    func testEachConfiguredModifierMatchesOnlyItself() {
        let held: [(MouseControlModifier, ModifierState)] = [
            (.shift, ModifierState(shift: true)),
            (.option, ModifierState(option: true)),
            (.command, ModifierState(command: true)),
        ]
        for (cfg, state) in held {
            XCTAssertEqual(mouseBinding(button: .left, clickCount: 1, held: state, configured: cfg)?.action, .previousVisualization)
            for (otherCfg, _) in held where otherCfg != cfg {
                XCTAssertNil(mouseBinding(button: .left, clickCount: 1, held: state, configured: otherCfg))
            }
        }
    }

    func testExtraModifierDisqualifies() {
        XCTAssertNil(mouseBinding(button: .left, clickCount: 1,
                                  held: ModifierState(shift: true, command: true), configured: .shift))
        XCTAssertNil(mouseBinding(button: .left, clickCount: 1,
                                  held: ModifierState(shift: true, control: true), configured: .shift))
    }

    func testOffDisablesModifierLayerButKeepsBareGestures() {
        XCTAssertNil(mouseBinding(button: .left, clickCount: 1, held: ModifierState(shift: true), configured: .off))
        XCTAssertEqual(mouseBinding(button: .right, clickCount: 1, held: none, configured: .off)?.action, .showContextMenu)
        XCTAssertEqual(mouseBinding(button: .left, clickCount: 2, held: none, configured: .off)?.action, .toggleFullscreen)
    }

    func testBareRightClickShowsMenuAndConsumes() {
        let b = mouseBinding(button: .right, clickCount: 1, held: none, configured: .shift)
        XCTAssertEqual(b?.action, .showContextMenu)
        XCTAssertEqual(b?.consume, true)
    }

    func testBareDoubleClickTogglesFullscreenWithoutConsuming() {
        let b = mouseBinding(button: .left, clickCount: 2, held: none, configured: .shift)
        XCTAssertEqual(b?.action, .toggleFullscreen)
        XCTAssertEqual(b?.consume, false)
    }

    func testBareSingleClickAndMiddleAreUntouched() {
        XCTAssertNil(mouseBinding(button: .left, clickCount: 1, held: none, configured: .shift))
        XCTAssertNil(mouseBinding(button: .left, clickCount: 3, held: none, configured: .shift))
        XCTAssertNil(mouseBinding(button: .middle, clickCount: 1, held: none, configured: .shift))
    }

    func testModifierDoubleClickIsStillAPreviousVisualizationClick() {
        XCTAssertEqual(mouseBinding(button: .left, clickCount: 2, held: ModifierState(shift: true), configured: .shift)?.action,
                       .previousVisualization)
    }

    // MARK: scroll

    func testWheelOneStepPerEventRegardlessOfMagnitude() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -1, precise: false), 1)    // down = next
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -9, precise: false), 1)
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: 2, precise: false), -1)    // up = previous
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: 0, precise: false), 0)
    }

    func testWheelUsesLargerAxis() {
        var acc = ScrollStepAccumulator()
        // Shift+wheel arrives as horizontal delta.
        XCTAssertEqual(acc.steps(deltaX: -3, deltaY: 0, precise: false), 1)
        XCTAssertEqual(acc.steps(deltaX: 3, deltaY: -1, precise: false), -1)
        XCTAssertEqual(acc.steps(deltaX: 1, deltaY: -3, precise: false), 1)
    }

    func testPreciseAccumulatesToThreshold() {
        var acc = ScrollStepAccumulator(preciseThreshold: 40)
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -15, precise: true), 0)
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -15, precise: true), 0)
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -15, precise: true), 1)   // 45 -> 1, remainder 5
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -30, precise: true), 0)   // 35
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -10, precise: true), 1)   // 45
    }

    func testPreciseBigDeltaCanYieldMultipleSteps() {
        var acc = ScrollStepAccumulator(preciseThreshold: 40)
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: 85, precise: true), -2)
    }

    func testPreciseDirectionReversalDiscardsRemainder() {
        var acc = ScrollStepAccumulator(preciseThreshold: 40)
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -30, precise: true), 0)
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: 30, precise: true), 0)    // not 0 net; restarts at 30
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: 15, precise: true), -1)
    }

    func testResetClearsRemainder() {
        var acc = ScrollStepAccumulator(preciseThreshold: 40)
        _ = acc.steps(deltaX: 0, deltaY: -30, precise: true)
        acc.reset()
        XCTAssertEqual(acc.steps(deltaX: 0, deltaY: -30, precise: true), 0)
    }

    // MARK: setting

    func testMouseControlModifierSettingDefaultAndRoundTrip() throws {
        XCTAssertEqual(VisualizerSettings.defaults.mouseControlModifier, .shift)
        XCTAssertEqual(MouseControlModifier.allCases, [.off, .shift, .option, .command])
        for m in MouseControlModifier.allCases {
            var s = VisualizerSettings.defaults
            s.mouseControlModifier = m
            let decoded = try JSONDecoder().decode(VisualizerSettings.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(decoded.mouseControlModifier, m)
        }
    }

    func testMouseControlModifierMissingKeyDefaultsToShift() throws {
        let json = #"{ "visualizerStyle": "bars" }"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(VisualizerSettings.self, from: json).mouseControlModifier, .shift)
    }

    func testMouseControlModifierUnknownValueFallsBackToDefault() throws {
        let json = #"{ "visualizerStyle": "bars", "mouseControlModifier": "control" }"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(VisualizerSettings.self, from: json).mouseControlModifier, .shift)
    }
}
