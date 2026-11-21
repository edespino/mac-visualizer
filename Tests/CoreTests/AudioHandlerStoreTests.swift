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

/// Tests for `AudioHandlerStore`, the thread-safe storage for the capture
/// service's sample handler. It boxes the function-typed handler in a class so
/// the bare function type never crosses `OSAllocatedUnfairLock`'s generic
/// boundary — see the type doc for why that matters (reabstraction-thunk crash).
final class AudioHandlerStoreTests: XCTestCase {

    /// The handler read back from the store invokes the closure that was set,
    /// forwarding the buffers and rate unmodified — the path the IO proc takes
    /// (read `handler`, then call it).
    func testReadBackHandlerInvokesAssignedClosure() {
        let store = AudioHandlerStore()
        var seenLeft: [Float] = []
        var seenRight: [Float] = []
        var seenRate: Double = 0
        var calls = 0
        store.handler = { l, r, rate in
            seenLeft = l; seenRight = r; seenRate = rate; calls += 1
        }

        guard let handler = store.handler else { return XCTFail("handler should be set") }
        handler([1, 2], [3, 4], 44100)

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(seenLeft, [1, 2])
        XCTAssertEqual(seenRight, [3, 4])
        XCTAssertEqual(seenRate, 44100)
    }

    /// Read-at-call-time semantics: reassigning the handler after the first set
    /// takes effect on the next read (the IO proc reads it fresh each callback).
    func testReassignmentTakesEffectOnNextRead() {
        let store = AudioHandlerStore()
        var which = ""
        store.handler = { _, _, _ in which = "first" }
        store.handler?( [0.1], [0.1], 48000)
        XCTAssertEqual(which, "first")

        store.handler = { _, _, _ in which = "second" }
        store.handler?( [0.1], [0.1], 48000)
        XCTAssertEqual(which, "second")
    }

    /// Assigning nil clears the handler.
    func testNilClearsHandler() {
        let store = AudioHandlerStore()
        store.handler = { _, _, _ in }
        XCTAssertNotNil(store.handler)
        store.handler = nil
        XCTAssertNil(store.handler)
    }

    /// A fresh store has no handler installed.
    func testInitiallyNil() {
        XCTAssertNil(AudioHandlerStore().handler)
    }

    /// Concurrent writes from one queue while another queue reads-and-invokes
    /// must not crash or deadlock, and every read either sees no handler or a
    /// valid, invocable one. Exercises the lock under contention (main-thread
    /// writer vs. RT-thread reader in production).
    func testConcurrentReadInvokeAndWriteIsSafe() {
        let store = AudioHandlerStore()
        store.handler = { _, _, _ in }
        let iterations = 5_000
        let writer = DispatchQueue(label: "writer")
        let reader = DispatchQueue(label: "reader")
        let group = DispatchGroup()

        writer.async(group: group) {
            for i in 0..<iterations {
                store.handler = { _, _, _ in _ = i }
            }
        }
        reader.async(group: group) {
            for _ in 0..<iterations {
                store.handler?([0.1], [0.1], 48000)
            }
        }
        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "concurrent read/write must not deadlock")
    }
}
