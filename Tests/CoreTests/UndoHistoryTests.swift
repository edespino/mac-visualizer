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

final class UndoHistoryTests: XCTestCase {
    func testEmptyHasNothingToUndoOrRedo() {
        let h = UndoHistory<Int>()
        XCTAssertFalse(h.canUndo)
        XCTAssertFalse(h.canRedo)
    }

    func testUndoReturnsNilWhenEmpty() {
        var h = UndoHistory<Int>()
        XCTAssertNil(h.undo(current: 5))
    }

    func testRecordThenUndoRestoresPrevious() {
        var h = UndoHistory<Int>()
        h.record(1)            // previous state was 1, current is now 2
        XCTAssertTrue(h.canUndo)
        XCTAssertEqual(h.undo(current: 2), 1)
        XCTAssertFalse(h.canUndo)
    }

    func testMultiLevelUndoWalksBack() {
        var h = UndoHistory<Int>()
        h.record(1)   // 1 -> 2
        h.record(2)   // 2 -> 3
        h.record(3)   // 3 -> 4, current 4
        XCTAssertEqual(h.undo(current: 4), 3)
        XCTAssertEqual(h.undo(current: 3), 2)
        XCTAssertEqual(h.undo(current: 2), 1)
        XCTAssertNil(h.undo(current: 1))
    }

    func testRedoAfterUndoReturnsForward() {
        var h = UndoHistory<Int>()
        h.record(1)   // 1 -> 2, current 2
        let undone = h.undo(current: 2)
        XCTAssertEqual(undone, 1)
        XCTAssertTrue(h.canRedo)
        XCTAssertEqual(h.redo(current: 1), 2)
        XCTAssertFalse(h.canRedo)
        XCTAssertTrue(h.canUndo)
    }

    func testRecordingClearsRedoStack() {
        var h = UndoHistory<Int>()
        h.record(1)
        _ = h.undo(current: 2)   // redo now has 2
        XCTAssertTrue(h.canRedo)
        h.record(1)              // a fresh change invalidates redo
        XCTAssertFalse(h.canRedo)
    }

    func testMaxDepthDropsOldest() {
        var h = UndoHistory<Int>(maxDepth: 2)
        h.record(1)
        h.record(2)
        h.record(3)   // drops the oldest (1); stack holds [2, 3]
        XCTAssertEqual(h.undo(current: 4), 3)
        XCTAssertEqual(h.undo(current: 3), 2)
        XCTAssertNil(h.undo(current: 2))
    }

    func testClearEmptiesBothStacks() {
        var h = UndoHistory<Int>()
        h.record(1)
        _ = h.undo(current: 2)
        h.clear()
        XCTAssertFalse(h.canUndo)
        XCTAssertFalse(h.canRedo)
    }
}
