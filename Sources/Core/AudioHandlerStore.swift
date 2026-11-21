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

import os

/// Thread-safe storage for the capture service's live sample handler.
///
/// **Why a box, not a bare closure in the lock.** The obvious implementation
/// stores the function-typed handler directly as the generic state of
/// `OSAllocatedUnfairLock<(([Float],[Float],Double)->Void)?>`, with a computed
/// property whose getter is `withLock { $0 }` and setter `withLock { $0 = new }`.
/// That pushes the *function value* through `withLock`'s generic boundary in
/// both directions: the getter returns the generic result `R` (a function
/// type) and the setter assigns into the generic `inout` state. The compiler
/// must convert between the function's concrete calling convention
/// (`@callee_guaranteed (@guaranteed [Float], [Float], @unowned Double) -> ()`)
/// and the maximally-abstract generic one
/// (`@in_guaranteed ... -> (@out ())`), emitting a *bidirectional pair* of
/// reabstraction thunks. Under the app target's `-Onone` explicit-module build
/// those partial-applied thunks formed a self-feeding cycle: invoking the
/// handler read back from the lock recursed thunk→thunk thousands of levels
/// deep on the real-time audio IO thread (a small stack), crashing with
/// "Thread stack size exceeded due to excessive recursion".
///
/// Boxing the handler in a `final class` fixes this at the source: the lock's
/// generic state is a *class reference* (`Box?`), a single retainable pointer
/// with no calling convention to reabstract. The function value is only ever
/// stored as, and read from, the box's concrete stored property — never routed
/// through the generic lock. No reabstraction-thunk pair is generated, so the
/// cycle cannot exist. To be doubly safe, `withLock` here only ever moves
/// `Box?` across its boundary; the closure is unwrapped from / wrapped into the
/// box *outside* the locked region.
///
/// **Preserved semantics** (required by the capture service): the handler is
/// read at call time (reassigning after `start()` takes effect immediately),
/// get/set are safe across the main-thread writer and the real-time
/// audio-thread reader, and the underlying `os_unfair_lock` supports priority
/// donation. The read path performs no heap allocation (only a retain of the
/// boxed closure); allocation of a new `Box` happens on the writer (main)
/// thread, off the real-time hot path.
public final class AudioHandlerStore {
    public typealias Handler = ([Float], [Float], Double) -> Void

    /// Holds the handler in its concrete representation so the bare function
    /// type never crosses the generic lock boundary.
    private final class Box {
        let handler: Handler
        init(_ handler: @escaping Handler) { self.handler = handler }
    }

    private let lock = OSAllocatedUnfairLock<Box?>(initialState: nil)

    public init() {}

    /// The live sample handler. Reading copies the current handler out under
    /// the lock and returns it; callers invoke it outside the lock.
    public var handler: Handler? {
        get {
            // Move only the class reference across the generic lock boundary,
            // then read the concrete closure off the box outside the lock.
            let box = lock.withLock { $0 }
            return box?.handler
        }
        set {
            // Build the box (and any allocation) outside the locked region;
            // only the class reference is assigned into the generic state.
            let box = newValue.map(Box.init)
            lock.withLock { $0 = box }
        }
    }
}
