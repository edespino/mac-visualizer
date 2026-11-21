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
import AudioToolbox
import CoreAudio
import AVFoundation
import os
import MacVisualizerCore

/// Captures the audio of the target players (Spotify AND Apple Music) via a
/// Core Audio process tap, delivering mono Float32 samples. The tap is a
/// stereo mixdown of every running target process, so whichever one is playing
/// comes through and switching between them is seamless. Not sandboxed; first
/// start triggers the system-audio TCC prompt (declared by
/// NSAudioCaptureUsageDescription). macOS 14.4+.
///
/// Threading: ALL Core Audio lifecycle work (tap/aggregate/IO-proc create, start,
/// stop, destroy, the property reads in `startBody`, listener install/remove,
/// `ProcessLocator` queries) runs on `lifecycleQueue`, never on main, because a
/// slow audio service can block a single call for 30 s. The public API
/// (`start`/`restart`/`stop`) only enqueues and returns at once.
final class AudioCaptureService: AudioCaptureSource {
    /// Capture state as seen by the UI. MAIN-THREAD ONLY: it is a mirror of
    /// `lifecycleState`, updated by `DispatchQueue.main.async` on every change.
    private(set) var state: CaptureState = .stopped

    /// True from the moment a lifecycle request is queued until the queue has
    /// drained (a start/rebuild is queued or in progress). MAIN-THREAD ONLY.
    /// Separate from `CaptureState` so that enum and its users are untouched.
    private(set) var isStarting = false

    /// Live sample handler. Read at call time inside the IO proc (not snapshotted
    /// at `start()`), so reassigning it after `start()` takes effect immediately.
    ///
    /// Backed by `AudioHandlerStore`, which guards the handler with an
    /// `os_unfair_lock` (priority-donation friendly, so the high-priority audio
    /// reader won't be inverted behind the main-thread writer) AND boxes it in a
    /// class so the bare function type never crosses the lock's generic boundary.
    /// Storing the closure directly as the lock's generic state emitted a
    /// reabstraction-thunk pair that self-recursed on the RT audio thread and
    /// overflowed its stack; see `AudioHandlerStore` for the full explanation.
    /// The handler is only *copied out* under the lock; it is invoked outside it.
    var onSamples: (([Float], [Float], Double) -> Void)? {
        get { handlerStore.handler }
        set { handlerStore.handler = newValue }
    }
    private let handlerStore = AudioHandlerStore()

    // INVARIANT: the lifecycle state below (tap id, aggregate id, IO proc id,
    // sample rate, built-with UID/process ids, listener blocks, `lifecycleState`)
    // is touched ONLY on `lifecycleQueue`. The one exception is `deinit`, which
    // runs the final teardown on that queue (see `deinit`).
    private let lifecycleQueue = DispatchQueue(
        label: "com.edespino.MacVisualizer.capture-lifecycle", qos: .userInitiated)
    private static let lifecycleKey = DispatchSpecificKey<Void>()

    /// Guards `requests` and `waiters` (touched from any thread).
    private let requestLock = NSLock()
    private var requests = CaptureRequestQueue()
    /// Completions registered since the drain loop last began an operation.
    private var waiters: [() -> Void] = []

    /// Authoritative state; lifecycle queue only. Mirrored to `state` on main.
    private var lifecycleState: CaptureState = .stopped

    init() {
        lifecycleQueue.setSpecific(key: Self.lifecycleKey, value: ())
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRate: Double = 48000
    private let ioQueue = DispatchQueue(label: "visualizer.audio.io")

    /// Serial queue the default-output-device change listener fires on.
    private let deviceListenerQueue = DispatchQueue(label: "visualizer.audio.devicelistener")
    /// The output-device UID the current aggregate was built with, so the
    /// listener only rebuilds on a real change. Lifecycle-queue-confined.
    private var builtWithOutputUID: String = ""
    /// Retained listener block, kept across rebuilds; removed on stop/deinit.
    private var outputDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    /// Serial queue the process-list change listener fires on.
    private let processListenerQueue = DispatchQueue(label: "visualizer.audio.processlistener")
    /// The set of target process ids the current tap was built with, so the
    /// process-list listener only rebuilds when a target player launches or
    /// quits (not on unrelated audio activity). Lifecycle-queue-confined.
    private var builtWithProcessIDs: Set<AudioObjectID> = []
    /// Retained process-list listener block, kept across rebuilds; removed on stop/deinit.
    private var processListenerBlock: AudioObjectPropertyListenerBlock?

    // IO-queue-confined reusable state. The IO proc runs on the real-time-ish
    // `ioQueue` every audio slice and must not allocate per callback:
    // `extractor` writes L/R into a preallocated ring of slots, and
    // `viewScratch` is a reused array of pointer views over the incoming
    // AudioBufferList (removeAll(keepingCapacity:) + append stays within
    // reserved capacity). Only ever touched from the IO proc block.
    private let extractor = StereoExtractorRing()
    private var viewScratch: [RawCaptureBufferView] = {
        var v = [RawCaptureBufferView]()
        v.reserveCapacity(8)
        return v
    }()

    func start() { start(reason: "unspecified") }

    /// Enqueue a (re)build and return immediately. Every (re)build funnels
    /// through `submit` so each one is logged with its trigger and outcome.
    func start(reason: String) { submit(.start(reason: reason), completion: nil) }

    /// `completion` runs on MAIN once the work covering this request finished.
    func start(reason: String, completion: @escaping () -> Void) {
        submit(.start(reason: reason), completion: completion)
    }

    /// Rebuild the whole tap/aggregate/IO-proc chain on the current default
    /// output device. A start already tears the old chain down first, so this
    /// reuses it — and, unlike `stop(); start()`, keeps the output-device
    /// listener installed across the rebuild.
    func restart() { start(reason: "unspecified") }
    func restart(reason: String) { start(reason: reason) }
    func restart(reason: String, completion: @escaping () -> Void) {
        start(reason: reason, completion: completion)
    }

    /// Enqueue a stop. Wins over any pending (not yet begun) start.
    func stop() { submit(.stop, completion: nil) }

    /// Any thread. Coalesces through `CaptureRequestQueue`: at most one
    /// operation waits behind the running one, latest request wins.
    private func submit(_ op: CaptureRequestQueue.Operation, completion: (() -> Void)?) {
        requestLock.lock()
        if let completion { waiters.append(completion) }
        let submission: CaptureRequestQueue.Submission
        switch op {
        case .start(let reason): submission = requests.requestStart(reason: reason)
        case .stop: submission = requests.requestStop()
        }
        if case .schedule = submission { publishStarting(true) }
        requestLock.unlock()

        switch submission {
        case .schedule:
            lifecycleQueue.async { [self] in drain() }
        case .coalesced(let replaced):
            switch op {
            case .start(let reason):
                Log.audioCapture.notice("Capture start coalesced: reason=\(reason, privacy: .public) pending")
            case .stop:
                if case .start(let skipped)? = replaced {
                    Log.audioCapture.notice("Capture start skipped: stop requested (reason=\(skipped, privacy: .public))")
                }
            }
        }
    }

    /// Mirror to main in lock order so true/false cannot reorder. Call with
    /// `requestLock` held.
    private func publishStarting(_ value: Bool) {
        DispatchQueue.main.async { [self] in isStarting = value }
    }

    /// Runs on `lifecycleQueue`: executes queued operations until none remain.
    private func drain() {
        dispatchPrecondition(condition: .onQueue(lifecycleQueue))
        while true {
            requestLock.lock()
            let op = requests.next()
            var mine: [() -> Void] = []
            if op != nil {
                mine = waiters
                waiters = []
            } else {
                publishStarting(false)
            }
            requestLock.unlock()
            guard let op else { return }
            switch op {
            case .start(let reason): performStart(reason: reason)
            case .stop: performStop()
            }
            if !mine.isEmpty {
                // After the state mirror above, so completions see the new state.
                DispatchQueue.main.async { for c in mine { c() } }
            }
        }
    }

    private func setState(_ new: CaptureState) {
        lifecycleState = new
        DispatchQueue.main.async { [self] in state = new }
    }

    private func performStart(reason: String) {
        let previous = Self.describe(lifecycleState)
        Log.audioCapture.notice("Capture start: reason=\(reason, privacy: .public) previousState=\(previous, privacy: .public) targets=\(ProcessLocator.allTargets().count, privacy: .public)")
        let startedAt = CACurrentMediaTime()
        startBody()
        Log.audioCapture.notice("Capture start total: \(Self.millis(since: startedAt), privacy: .public) ms")
        let result = Self.describe(lifecycleState)
        Log.audioCapture.notice("Capture start result: \(result, privacy: .public)")
    }

    private func performStop() {
        Log.audioCapture.notice("Capture stop")
        removeDefaultOutputDeviceListener()
        removeProcessListListener()
        setState(teardown() ? .stopped : .failed("TeardownIOProc"))
    }

    private static func millis(since start: CFTimeInterval) -> Int {
        Int(((CACurrentMediaTime() - start) * 1000).rounded())
    }

    /// Runs one Core Audio call and logs it when it takes over 50 ms. Diagnostic
    /// only: passes the result through, never alters control flow.
    private static func timed<T>(_ name: String, _ body: () -> T) -> T {
        let start = CACurrentMediaTime()
        let result = body()
        let ms = millis(since: start)
        if ms > 50 {
            Log.audioCapture.notice("Capture slow call: \(name, privacy: .public) \(ms, privacy: .public) ms")
        }
        return result
    }

    private static func describe(_ state: CaptureState) -> String {
        switch state {
        case .stopped: return "stopped"
        case .running: return "running"
        case .noTargetProcess: return "noTargetProcess"
        case .failed(let message): return "failed: \(message)"
        }
    }

    private func startBody() {
        // Idempotent restart — but only if the previous IO proc is provably
        // gone. extractor/viewScratch below are IO-queue-confined and not
        // thread-safe; mutating them while a failed-to-destroy callback could
        // still fire would race, so a teardown failure aborts the start.
        guard teardown() else {
            let message = "TeardownIOProc failed; previous IO proc may still be live"
            Log.audioCapture.error("\(message, privacy: .public)")
            setState(.failed(message))
            return
        }

        // Follow whichever target player is running: this listener rebuilds the
        // tap when one launches or quits. Installed once, BEFORE target
        // selection, so a start with no player running still picks one up when
        // it launches later (parked in `.noTargetProcess` until then).
        Self.timed("InstallProcessListListener") { installProcessListListener() }

        let targetIDs = Self.timed("ProcessLocator.allTargets") { ProcessLocator.allTargets() }
        guard !targetIDs.isEmpty else {
            builtWithProcessIDs = []
            setState(.noTargetProcess)
            return
        }
        builtWithProcessIDs = Set(targetIDs)

        // 1) Create the tap (stereo mixdown of ALL running target processes),
        // unmuted so audio still plays. A silent player (paused, or the one not
        // currently playing) contributes nothing, so both can be tapped at once
        // and switching between them needs no rebuild.
        let desc = CATapDescription(stereoMixdownOfProcesses: targetIDs)
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = Self.timed("AudioHardwareCreateProcessTap") { AudioHardwareCreateProcessTap(desc, &newTap) }
        guard tapStatus == noErr else {
            let message = "CreateProcessTap \(tapStatus)"
            Log.audioCapture.error("\(message, privacy: .public)")
            setState(.failed(message)); return
        }
        guard newTap != AudioObjectID(kAudioObjectUnknown) else {
            let message = "CreateProcessTap returned no tap"
            Log.audioCapture.error("\(message, privacy: .public)")
            setState(.failed(message)); return
        }
        tapID = newTap

        // 2) Read and VALIDATE the tap's stream format. The IO proc binds
        // buffer memory as Float32; a non-PCM, non-float, or non-32-bit layout
        // would be silently misread as garbage audio, so anything else is a
        // clear failure state — never a guess.
        var fmtAddr = CoreAudioHAL.address(kAudioTapPropertyFormat)
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let fmtStatus = Self.timed("ReadTapFormat") { AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &asbdSize, &asbd) }
        guard fmtStatus == noErr else {
            let message = "ReadTapFormat \(fmtStatus)"
            Log.audioCapture.error("\(message, privacy: .public)")
            setState(.failed(message)); teardown(); return
        }
        if let problem = AudioCaptureService.validateTapFormat(asbd) {
            Log.audioCapture.error("\(problem, privacy: .public)")
            setState(.failed(problem)); teardown(); return
        }
        sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000

        // 3) Create a private aggregate device whose tap list contains our tap.
        let outUID = Self.timed("DefaultOutputDeviceUID") { CoreAudioHAL.defaultOutputDeviceUID() } ?? ""
        builtWithOutputUID = outUID
        let aggUID = UUID().uuidString
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacVisualizerTap",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        var newAgg = AudioObjectID(kAudioObjectUnknown)
        let aggStatus = Self.timed("AudioHardwareCreateAggregateDevice") { AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAgg) }
        guard aggStatus == noErr else {
            let message = "CreateAggregate \(aggStatus)"
            Log.audioCapture.error("\(message, privacy: .public)")
            setState(.failed(message)); teardown(); return
        }
        aggregateID = newAgg

        // 3b) Size the extraction scratch for the LARGEST slice the device may
        // deliver, OFF the IO critical path. The nominal buffer frame size is
        // the SMALLEST callback size on devices that use variable buffer frame
        // sizes, so the governing bound is the max over the nominal size, the
        // buffer-frame-size range maximum, and the variable-size maximum when
        // published (kAudioDevicePropertyUsesVariableBufferFrameSizes reports
        // that maximum). prepare() never shrinks, so a restart with an
        // unchanged format reallocates nothing; growth happens here at start,
        // never inside the IO callback for conforming slices.
        let bufferReadsStart = CACurrentMediaTime()
        var nominal: UInt32 = 0
        var nominalSize = UInt32(MemoryLayout<UInt32>.size)
        var nominalAddr = CoreAudioHAL.address(kAudioDevicePropertyBufferFrameSize)
        let hasNominal = AudioObjectGetPropertyData(
            aggregateID, &nominalAddr, 0, nil, &nominalSize, &nominal) == noErr

        var range = AudioValueRange()
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        var rangeAddr = CoreAudioHAL.address(kAudioDevicePropertyBufferFrameSizeRange)
        let hasRange = AudioObjectGetPropertyData(
            aggregateID, &rangeAddr, 0, nil, &rangeSize, &range) == noErr

        var variableMax: UInt32 = 0
        var variableSize = UInt32(MemoryLayout<UInt32>.size)
        var variableAddr = CoreAudioHAL.address(kAudioDevicePropertyUsesVariableBufferFrameSizes)
        let hasVariable = AudioObjectGetPropertyData(
            aggregateID, &variableAddr, 0, nil, &variableSize, &variableMax) == noErr

        let bufferReadsMs = Self.millis(since: bufferReadsStart)
        if bufferReadsMs > 50 {
            Log.audioCapture.notice("Capture slow call: BufferPropertyReads \(bufferReadsMs, privacy: .public) ms")
        }
        if let capacity = StereoExtractorRing.governingFrameCapacity(
            nominal: hasNominal ? Int(nominal) : nil,
            rangeMaximum: hasRange ? Int(range.mMaximum) : nil,
            variableMaximum: hasVariable ? Int(variableMax) : nil) {
            extractor.prepare(frameCapacity: capacity)
        }
        viewScratch.reserveCapacity(max(8, Int(asbd.mChannelsPerFrame)))

        // 4) Install an IO proc that downmixes to mono and forwards samples.
        // Handle BOTH buffer layouts the tap may use: a single interleaved buffer
        // (mNumberChannels > 1) or one buffer per channel (non-interleaved).
        let rate = sampleRate
        var newProc: AudioDeviceIOProcID?
        let procStatus = Self.timed("AudioDeviceCreateIOProcIDWithBlock") { AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, ioQueue) {
            [weak self] _, inInputData, _, _, _ in
            // Read the live handler at call time so reassigning `onSamples` after
            // start() takes effect. Bail early if no handler is installed.
            guard let self, let handler = self.onSamples else { return }

            // View each AudioBuffer through a zero-copy RawCaptureBufferView and
            // extract into the preallocated ring (StereoExtractorRing in Core) —
            // the IO proc must not allocate per callback. The view preserves the
            // RAW buffer list faithfully: a null mData becomes `samples: nil`, a
            // present-but-empty buffer becomes a non-nil zero-count pointer. The
            // extractor branches on the raw count and distinguishes those two
            // cases exactly like extractStereoFromBuffers (parity is pinned by
            // StereoExtractorRingTests).
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            guard abl.count > 0 else { return }
            self.viewScratch.removeAll(keepingCapacity: true)
            for b in abl {
                let channels = Int(b.mNumberChannels)
                guard let data = b.mData else {
                    self.viewScratch.append(RawCaptureBufferView(samples: nil, channelCount: channels))
                    continue
                }
                let n = Int(b.mDataByteSize) / MemoryLayout<Float32>.size
                guard n > 0 else {
                    self.viewScratch.append(RawCaptureBufferView(
                        samples: UnsafeBufferPointer(start: nil, count: 0), channelCount: channels))
                    continue
                }
                let ptr = data.bindMemory(to: Float32.self, capacity: n)
                self.viewScratch.append(RawCaptureBufferView(
                    samples: UnsafeBufferPointer(start: ptr, count: n), channelCount: channels))
            }

            let (left, right) = self.extractor.extract(from: self.viewScratch)
            if !left.isEmpty { handler(left, right, rate) }
        } }
        guard procStatus == noErr, let proc = newProc else {
            let message = "CreateIOProc \(procStatus)"
            Log.audioCapture.error("\(message, privacy: .public)")
            setState(.failed(message)); teardown(); return
        }
        ioProcID = proc

        // 5) Start. First time, the system shows the audio-recording permission prompt.
        let startStatus = Self.timed("AudioDeviceStart") { AudioDeviceStart(aggregateID, proc) }
        guard startStatus == noErr else {
            let message = "DeviceStart \(startStatus)"
            Log.audioCapture.error("\(message, privacy: .public)")
            setState(.failed(message)); teardown(); return
        }
        setState(.running)
        Self.timed("InstallOutputDeviceListener") { installDefaultOutputDeviceListener() }
    }

    /// Listen for default-output-device changes. The aggregate is clocked to
    /// the output device captured when it was built; when the user switches
    /// output or a Bluetooth device connects/drops/sleeps, the old clock can
    /// strand and the IO proc stops delivering samples with no error. Rebuild
    /// on the new device. Installed once (kept across rebuilds), removed on
    /// stop/deinit. The listener fires on `deviceListenerQueue` (not main); the
    /// decision is made on the lifecycle queue and the rebuild goes through the
    /// coalescing `submit`, so a burst of events during a hang yields one rebuild.
    private func installDefaultOutputDeviceListener() {
        guard outputDeviceListenerBlock == nil else { return }
        var addr = CoreAudioHAL.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            let current = CoreAudioHAL.defaultOutputDeviceUID() ?? ""
            self?.lifecycleQueue.async { [weak self] in
                guard let self else { return }
                switch self.lifecycleState {
                case .running:
                    guard current != self.builtWithOutputUID else { return }
                case .failed:
                    break
                default:
                    return
                }
                self.submit(.start(reason: "output-device-changed"), completion: nil)
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, deviceListenerQueue, block)
        if status == noErr {
            outputDeviceListenerBlock = block
        } else {
            Log.audioCapture.error("AddPropertyListener default-output \(status, privacy: .public)")
        }
    }

    private func removeDefaultOutputDeviceListener() {
        guard let block = outputDeviceListenerBlock else { return }
        var addr = CoreAudioHAL.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, deviceListenerQueue, block)
        outputDeviceListenerBlock = nil
    }

    /// Listen for changes to the system's audio-process list. The tap captures
    /// every running target player; when one launches or quits, the set of ids
    /// to tap changes, so rebuild on the new set. This is what makes switching
    /// players automatic — a player that started after the tap was built is
    /// added — and it also recovers the case where NO player was running at
    /// start (parked in `.noTargetProcess`) and one launches later. Unrelated
    /// audio activity leaves the target set unchanged and is ignored. Installed
    /// once (kept across rebuilds), removed on stop/deinit. Fires on
    /// `processListenerQueue` (not main); the decision runs on the lifecycle
    /// queue and the rebuild goes through the coalescing `submit`.
    private func installProcessListListener() {
        guard processListenerBlock == nil else { return }
        var addr = CoreAudioHAL.address(kAudioHardwarePropertyProcessObjectList)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            let current = Set(ProcessLocator.allTargets())
            self?.lifecycleQueue.async { [weak self] in
                guard let self, self.lifecycleState != .stopped,
                      current != self.builtWithProcessIDs else { return }
                self.submit(.start(reason: "target-set-changed"), completion: nil)
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, processListenerQueue, block)
        if status == noErr {
            processListenerBlock = block
        } else {
            Log.audioCapture.error("AddPropertyListener process-list \(status, privacy: .public)")
        }
    }

    private func removeProcessListListener() {
        guard let block = processListenerBlock else { return }
        var addr = CoreAudioHAL.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, processListenerQueue, block)
        processListenerBlock = nil
    }

    /// Nil when the ASBD is a layout the IO proc can read; otherwise a
    /// human-readable description of the mismatch for the `.failed` state.
    ///
    /// The IO proc binds each buffer's bytes as densely packed Float32
    /// (`mDataByteSize / 4` samples, no padding), so beyond PCM/float/
    /// endian/bit-width this also requires the packed flag and byte counts
    /// that match that dense layout exactly: 4 bytes × channels per frame
    /// when interleaved, 4 bytes per frame when each channel has its own
    /// buffer, one frame per packet either way.
    static func validateTapFormat(_ asbd: AudioStreamBasicDescription) -> String? {
        guard asbd.mFormatID == kAudioFormatLinearPCM else {
            return "Tap format not linear PCM (formatID \(asbd.mFormatID))"
        }
        guard asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            return "Tap format not float (flags 0x\(String(asbd.mFormatFlags, radix: 16)))"
        }
        guard asbd.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else {
            return "Tap format big-endian (flags 0x\(String(asbd.mFormatFlags, radix: 16)))"
        }
        guard asbd.mBitsPerChannel == 32 else {
            return "Tap format not 32-bit (bitsPerChannel \(asbd.mBitsPerChannel))"
        }
        guard asbd.mFormatFlags & kAudioFormatFlagIsPacked != 0 else {
            return "Tap format not packed (flags 0x\(String(asbd.mFormatFlags, radix: 16)))"
        }
        guard asbd.mChannelsPerFrame >= 1 else {
            return "Tap format has no channels"
        }
        let interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let expectedBytesPerFrame = interleaved ? 4 * asbd.mChannelsPerFrame : 4
        guard asbd.mBytesPerFrame == expectedBytesPerFrame else {
            return "Tap format bytesPerFrame \(asbd.mBytesPerFrame) != \(expectedBytesPerFrame) for "
                 + "\(interleaved ? "interleaved" : "non-interleaved") \(asbd.mChannelsPerFrame)-channel Float32"
        }
        guard asbd.mFramesPerPacket == 1 else {
            return "Tap format framesPerPacket \(asbd.mFramesPerPacket) != 1"
        }
        guard asbd.mBytesPerPacket == asbd.mBytesPerFrame else {
            return "Tap format bytesPerPacket \(asbd.mBytesPerPacket) != bytesPerFrame \(asbd.mBytesPerFrame)"
        }
        return nil
    }

    /// Tears down the IO proc / aggregate / tap chain. Returns true when any
    /// previously installed IO proc is provably destroyed (or none existed) —
    /// i.e. the IO callback can no longer fire. When destroying the proc
    /// fails, the proc and device handles are KEPT so a later attempt can
    /// retry, and the caller must not touch IO-queue-confined state
    /// (extractor / viewScratch) because the old callback may still be live.
    @discardableResult
    private func teardown() -> Bool {
        let unknown = AudioObjectID(kAudioObjectUnknown)
        if aggregateID != unknown, let proc = ioProcID {
            let stopStatus = Self.timed("AudioDeviceStop") { AudioDeviceStop(aggregateID, proc) }
            if stopStatus != noErr {
                // Destroying the proc below still unregisters it; log only.
                Log.audioCapture.error("DeviceStop \(stopStatus, privacy: .public) during teardown")
            }
            let destroyStatus = Self.timed("AudioDeviceDestroyIOProcID") { AudioDeviceDestroyIOProcID(aggregateID, proc) }
            guard destroyStatus == noErr else {
                Log.audioCapture.error("DestroyIOProc \(destroyStatus, privacy: .public) during teardown; IO proc may still be live")
                return false
            }
        }
        ioProcID = nil
        if aggregateID != unknown {
            let aggStatus = Self.timed("AudioHardwareDestroyAggregateDevice") { AudioHardwareDestroyAggregateDevice(aggregateID) }
            if aggStatus != noErr {
                Log.audioCapture.error("DestroyAggregate \(aggStatus, privacy: .public) during teardown")
            }
            aggregateID = unknown
        }
        if tapID != unknown {
            let tapStatus = Self.timed("AudioHardwareDestroyProcessTap") { AudioHardwareDestroyProcessTap(tapID) }
            if tapStatus != noErr {
                Log.audioCapture.error("DestroyProcessTap \(tapStatus, privacy: .public) during teardown")
            }
            tapID = unknown
        }
        return true
    }

    deinit {
        Log.audioCapture.notice("Capture service deinit")
        // Never leave a live IO proc or aggregate device behind. Teardown must
        // run on the lifecycle queue; if deinit is already on it (last release
        // happened there) run inline, since queue.sync would deadlock.
        let work = {
            self.removeDefaultOutputDeviceListener()
            self.removeProcessListListener()
            self.teardown()
        }
        if DispatchQueue.getSpecific(key: Self.lifecycleKey) != nil {
            work()
        } else {
            lifecycleQueue.sync(execute: work)
        }
    }
}
