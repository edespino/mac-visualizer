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

/// A bounded undo/redo stack over snapshots of some `State`. Pure value logic,
/// unit-tested independently of what it stores: the caller records the state as
/// it was *before* a change, and on undo/redo passes the *current* state so it
/// can ride the opposite stack.
///
/// Recording a new change invalidates the redo stack (standard linear-history
/// behavior). The stack is capped at `maxDepth`; the oldest entries drop first.
public struct UndoHistory<State> {
    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private let maxDepth: Int

    public init(maxDepth: Int = 50) {
        self.maxDepth = max(1, maxDepth)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Record the state as it was *before* a just-applied change. Clears the
    /// redo stack and drops the oldest entry past `maxDepth`.
    public mutating func record(_ previous: State) {
        undoStack.append(previous)
        if undoStack.count > maxDepth {
            undoStack.removeFirst(undoStack.count - maxDepth)
        }
        redoStack.removeAll()
    }

    /// Step back: push `current` onto the redo stack and return the state to
    /// restore, or nil if there is nothing to undo.
    public mutating func undo(current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Step forward: push `current` onto the undo stack and return the state to
    /// restore, or nil if there is nothing to redo.
    public mutating func redo(current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
