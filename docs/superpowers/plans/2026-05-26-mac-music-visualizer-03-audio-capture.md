# Mac Music Visualizer — Plan 3: Real Audio Capture (Core Audio Process Tap)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the synthetic frame source with real audio captured from Spotify / Apple Music via a Core Audio process tap, so the spectrum bars react to the actual music playing.

**Architecture:** Testable DSP/glue logic stays pure in `MacVisualizerCore` (a sliding/overlapping sample ring that no longer drops audio — resolving a Plan 1 carry-forward — and a stereo→mono downmix). The irreducible Core Audio integration (`ProcessLocator`, `AudioCaptureService`) lives in the app target behind a small `AudioCaptureSource` protocol. Because the tap is hardware/permission-bound and cannot be unit-tested, it is verified by a headless `MacVisualizer --audio-probe` CLI mode that prints captured RMS, and by running the app with music playing.

**Tech Stack:** Swift 5.10, AudioToolbox / CoreAudio HAL (process tap: `CATapDescription`, `AudioHardwareCreateProcessTap`, aggregate device, `AudioDeviceIOProcID`), AVFoundation (`AudioStreamBasicDescription`), Accelerate (existing), XCTest.

**Builds on Plans 1–2 (merged):** `AudioFrame` (+`bandPeaks`), `SpectrumAnalyzer`, `SpectrumBarsVisualizer`, `MetalRenderer`/`MetalView`, `RenderModel` (currently driven by `SyntheticFrameSource`).

**Verified API basis:** The Core Audio symbols and sequence below were confirmed against Apple's "Capturing system audio with Core Audio taps" sample, the `CATapDescription` / `AudioHardwareCreateProcessTap` docs, and the `insidegui/AudioCap` source. Key confirmed facts: tap stream format is Float32 (read it at runtime from `kAudioTapPropertyFormat`, do not hardcode sample rate/interleaving); the permission is TCC `kTCCServiceAudioCapture` declared via the **`NSAudioCaptureUsageDescription`** Info.plist key; **no entitlement** is needed for a non-sandboxed app; the consent prompt fires on the **first `AudioDeviceStart`** of an aggregate device containing a tap; there is **no public API to pre-check** the permission. Minimum OS 14.4.

**Scope boundary — NOT in this plan:** track metadata overlay and settings UI (Plan 4). The visualizer keeps falling back to the synthetic source when no target app is playing or the tap can't start, so the app is never blank.

---

## File Structure

```
mac-visualizer/
  project.yml                                   # MODIFY: add NSAudioCaptureUsageDescription to the app target info
  Sources/
    Core/
      AudioDownmix.swift                        # CREATE: pure interleaved -> mono downmix
      SpectrumAnalyzer.swift                    # MODIFY: sliding/overlapping ring (no tail drop); accept sample stream
      AudioCaptureSource.swift                  # CREATE: protocol + CaptureState enum (the seam the app depends on)
    App/
      RenderModel.swift                         # MODIFY: hold latest real AudioFrame; fall back to synthetic
      LatestFrameBox.swift                      # CREATE: tiny lock-guarded single-slot frame handoff
      MacVisualizerApp.swift                    # MODIFY: route --audio-probe and --list-audio-processes CLI modes
    Services/                                   # CREATE dir (app target)
      CoreAudioHAL.swift                        # CREATE: thin typed wrappers over AudioObjectGetPropertyData
      ProcessLocator.swift                      # CREATE: find Spotify/Music AudioObjectID by bundle id
      AudioCaptureService.swift                 # CREATE: process tap + aggregate device + IO proc -> mono Float32
      AudioProbe.swift                          # CREATE: CLI verification (start capture, print RMS, exit)
  Tests/
    CoreTests/
      AudioDownmixTests.swift                   # CREATE
      SpectrumAnalyzerSlidingTests.swift        # CREATE (new ring behavior)
```

**Decomposition rationale:** `AudioDownmix` and the analyzer ring change are pure and unit-tested. `AudioCaptureSource` is a protocol so `RenderModel` depends on an abstraction, not on Core Audio. `CoreAudioHAL`/`ProcessLocator`/`AudioCaptureService` are the untestable HAL layer, isolated in `Sources/Services` and verified via the `--audio-probe` CLI and live runs. Order is spike-first: prove capture prints RMS (Tasks 4–6) before wiring it to the renderer (Task 7).

---

## Task 1: `AudioDownmix` — pure interleaved → mono

**Files:**
- Create: `Sources/Core/AudioDownmix.swift`
- Test: `Tests/CoreTests/AudioDownmixTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/AudioDownmixTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class AudioDownmixTests: XCTestCase {
    func testMonoInputIsReturnedUnchanged() {
        let input: [Float] = [0.1, -0.2, 0.3]
        XCTAssertEqual(downmixToMono(interleaved: input, channelCount: 1), input)
    }

    func testStereoIsAveragedPerFrame() {
        // L,R interleaved: (0.0,1.0) -> 0.5 ; (0.2,0.4) -> 0.3 ; (-1.0,1.0) -> 0.0
        let input: [Float] = [0.0, 1.0, 0.2, 0.4, -1.0, 1.0]
        let mono = downmixToMono(interleaved: input, channelCount: 2)
        XCTAssertEqual(mono.count, 3)
        XCTAssertEqual(mono[0], 0.5, accuracy: 1e-6)
        XCTAssertEqual(mono[1], 0.3, accuracy: 1e-6)
        XCTAssertEqual(mono[2], 0.0, accuracy: 1e-6)
    }

    func testEmptyInputYieldsEmpty() {
        XCTAssertTrue(downmixToMono(interleaved: [], channelCount: 2).isEmpty)
    }

    func testIgnoresTrailingPartialFrame() {
        // 5 samples, 2 channels -> 2 complete frames, last lone sample dropped
        let input: [Float] = [1.0, 1.0, 0.5, 0.5, 0.9]
        let mono = downmixToMono(interleaved: input, channelCount: 2)
        XCTAssertEqual(mono, [1.0, 0.5])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `cannot find 'downmixToMono' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Core/AudioDownmix.swift`:

```swift
import Foundation

/// Averages `channelCount` interleaved channels into a mono signal.
/// A trailing partial frame (fewer than `channelCount` samples) is ignored.
public func downmixToMono(interleaved: [Float], channelCount: Int) -> [Float] {
    precondition(channelCount >= 1, "channelCount must be >= 1")
    if channelCount == 1 { return interleaved }
    let frames = interleaved.count / channelCount
    guard frames > 0 else { return [] }
    var mono = [Float](repeating: 0, count: frames)
    let inv = 1 / Float(channelCount)
    for f in 0..<frames {
        var sum: Float = 0
        let base = f * channelCount
        for c in 0..<channelCount { sum += interleaved[base + c] }
        mono[f] = sum * inv
    }
    return mono
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, all four `AudioDownmixTests` pass (total 50).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/AudioDownmix.swift Tests/CoreTests/AudioDownmixTests.swift
git commit -m "Add pure interleaved-to-mono downmix"
```

---

## Task 2: `SpectrumAnalyzer` sliding/overlapping ring (resolve Plan 1 carry-forward)

**Files:**
- Modify: `Sources/Core/SpectrumAnalyzer.swift`
- Test: `Tests/CoreTests/SpectrumAnalyzerSlidingTests.swift`

Background: Plan 1's `append` did `ring.suffix(fftSize)` then `ring.removeAll()`, discarding any samples beyond the last window and emitting at most one frame per call regardless of input size. Replace the ring with a **sliding window that keeps the most recent `fftSize` samples** across calls (so windows overlap and no recent audio is dropped between calls). Behavior contract: `append` returns a frame whenever at least `fftSize` samples have been accumulated, computed from the most-recent `fftSize` samples; the ring then retains those `fftSize` samples (trimmed to `fftSize`) for overlap with the next call.

- [ ] **Step 1: Write the failing test**

`Tests/CoreTests/SpectrumAnalyzerSlidingTests.swift`:

```swift
import XCTest
@testable import MacVisualizerCore

final class SpectrumAnalyzerSlidingTests: XCTestCase {
    private func analyzer(bands: Int = 24) -> SpectrumAnalyzer {
        var s = VisualizerSettings.defaults
        s.barCount = bands
        s.gain = 1
        s.smoothing = 0
        return SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: s)
    }

    func testRetainsWindowForOverlapAcrossCalls() {
        let a = analyzer()
        // Fill exactly one window -> emits a frame.
        XCTAssertNotNil(a.append(SignalGenerators.silence(count: 2048)))
        // A SMALL subsequent append (less than fftSize) should still emit, because the
        // ring retained the previous window (sliding), rather than starting from empty.
        XCTAssertNotNil(a.append(SignalGenerators.silence(count: 256)))
    }

    func testDoesNotEmitBeforeFirstFullWindow() {
        let a = analyzer()
        XCTAssertNil(a.append(SignalGenerators.silence(count: 1000)))
        XCTAssertNil(a.append(SignalGenerators.silence(count: 1000))) // 2000 < 2048
        XCTAssertNotNil(a.append(SignalGenerators.silence(count: 100))) // now 2100 >= 2048
    }

    func testTonePlacementStillCorrectAfterSliding() {
        let a = analyzer(bands: 24)
        let tone = SignalGenerators.sine(frequency: 1000, sampleRate: 48000, count: 2048)
        _ = a.append(tone)                  // first window
        let frame = a.append(tone)!         // overlapped window, still a 1kHz tone
        let loudest = SignalGenerators.argmax(frame.bands)
        XCTAssertGreaterThan(loudest, 0)
        XCTAssertLessThan(loudest, frame.bands.count - 1)
        XCTAssertGreaterThan(frame.bands[loudest], 0.1)
    }

    func testRingDoesNotGrowUnbounded() {
        let a = analyzer()
        // Feed many windows; the internal ring must stay bounded (~fftSize), proven
        // indirectly: feeding 100 * 2048 samples still returns promptly and emits frames.
        var lastFrameNonNil = false
        for _ in 0..<100 { lastFrameNonNil = (a.append(SignalGenerators.silence(count: 2048)) != nil) }
        XCTAssertTrue(lastFrameNonNil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `testRetainsWindowForOverlapAcrossCalls` fails (the old `removeAll()` ring returns nil on the small 256-sample follow-up because it discarded the previous window).

- [ ] **Step 3: Update the ring logic**

In `Sources/Core/SpectrumAnalyzer.swift`, replace the body of `append(_:)` from the `ring.append(...)` line through the `ring.removeAll(...)` line. Find this block:

```swift
        ring.append(contentsOf: samples)
        guard ring.count >= fftSize else { return nil }

        // Take the most recent full window; drop everything older.
        let frameSamples = Array(ring.suffix(fftSize))
        ring.removeAll(keepingCapacity: true)
```

Replace it with:

```swift
        ring.append(contentsOf: samples)
        // Keep only the most recent fftSize samples (sliding window with overlap);
        // never drop the tail by clearing the ring.
        if ring.count > fftSize {
            ring.removeFirst(ring.count - fftSize)
        }
        guard ring.count == fftSize else { return nil }

        let frameSamples = ring   // the current full window (retained for overlap)
```

Leave the rest of `append` (rms/peak via vDSP, window, FFT, mapper, post, return) unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `** TEST SUCCEEDED **`. All four `SpectrumAnalyzerSlidingTests` pass, AND the existing `SpectrumAnalyzerTests` still pass (the original tests feed full 2048 windows, which still emit). Total 54.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SpectrumAnalyzer.swift Tests/CoreTests/SpectrumAnalyzerSlidingTests.swift
git commit -m "Make SpectrumAnalyzer ring a sliding overlapping window (no tail drop)"
```

---

## Task 3: `AudioCaptureSource` protocol + `CaptureState`

**Files:**
- Create: `Sources/Core/AudioCaptureSource.swift`

This is the seam the app depends on, so `RenderModel` never imports Core Audio directly. No unit test (it is just declarations); it is exercised by Task 7's wiring and verified at build time.

- [ ] **Step 1: Write the protocol and state**

`Sources/Core/AudioCaptureSource.swift`:

```swift
import Foundation

/// Coarse capture status for UI/diagnostics.
public enum CaptureState: Equatable {
    case stopped
    case running
    case noTargetProcess      // Spotify/Music not running or not producing audio
    case failed(String)       // tap/aggregate creation or start failed (message for logging)
}

/// A source of mono Float32 audio samples plus the sample rate they arrive at.
/// Implemented by the real Core Audio capture service (app target) and by fakes in tests.
public protocol AudioCaptureSource: AnyObject {
    var state: CaptureState { get }
    /// Called on a background queue with a chunk of mono samples and their sample rate.
    var onSamples: (([Float], Double) -> Void)? { get set }
    func start()
    func stop()
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run tests (unchanged count)**

Run: `make test`
Expected: `** TEST SUCCEEDED **`, total 54 (no new tests; this is a protocol).

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/AudioCaptureSource.swift
git commit -m "Add AudioCaptureSource protocol and CaptureState"
```

---

## Task 4: `CoreAudioHAL` + `ProcessLocator` (find Spotify/Music by bundle id)

**Files:**
- Modify: `project.yml` (add `Sources/Services` to the app target sources)
- Create: `Sources/Services/CoreAudioHAL.swift`
- Create: `Sources/Services/ProcessLocator.swift`
- Modify: `Sources/App/MacVisualizerApp.swift` (add `--list-audio-processes` CLI mode)

No unit tests (depends on live processes); verified by the `--list-audio-processes` CLI listing running audio processes including Music/Spotify when they play.

- [ ] **Step 1: Add `Sources/Services` to the app target in `project.yml`**

Change the `MacVisualizer` target `sources` list from:
```yaml
    sources:
      - Sources/App
      - Sources/Rendering
```
to:
```yaml
    sources:
      - Sources/App
      - Sources/Rendering
      - Sources/Services
```

- [ ] **Step 2: Write `Sources/Services/CoreAudioHAL.swift`**

```swift
import AudioToolbox

/// Thin typed helpers over the Core Audio HAL property API. App-target only.
enum CoreAudioHAL {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Read an `AudioObjectID` array property (e.g. the process object list).
    static func objectIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var out = [AudioObjectID](repeating: 0, count: count)
        var sz = size
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &sz, &out)
        return status == noErr ? out : []
    }

    /// Read a CFString property (e.g. a process object's bundle id), or nil.
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
        guard status == noErr, let s = value else { return nil }
        return s as String
    }

    /// The default system output device's UID (for the aggregate device main sub-device).
    static func defaultOutputDeviceUID() -> String? {
        var addr = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr
        else { return nil }
        return string(deviceID, kAudioDevicePropertyDeviceUID)
    }
}
```

- [ ] **Step 3: Write `Sources/Services/ProcessLocator.swift`**

```swift
import AudioToolbox

/// Finds the Core Audio process-object IDs for target apps (by bundle id).
struct ProcessLocator {
    /// Bundle ids we care about, in priority order.
    static let defaultTargets = ["com.spotify.client", "com.apple.Music"]

    /// All current audio process objects paired with their bundle id (when available).
    static func runningAudioProcesses() -> [(id: AudioObjectID, bundleID: String)] {
        let ids = CoreAudioHAL.objectIDs(AudioObjectID(kAudioObjectSystemObject),
                                         kAudioHardwarePropertyProcessObjectList)
        return ids.compactMap { id in
            guard let bundle = CoreAudioHAL.string(id, kAudioProcessPropertyBundleID) else { return nil }
            return (id, bundle)
        }
    }

    /// The first running target process object id, preferring the order in `targets`.
    static func firstTarget(_ targets: [String] = defaultTargets) -> (id: AudioObjectID, bundleID: String)? {
        let running = runningAudioProcesses()
        for wanted in targets {
            if let match = running.first(where: { $0.bundleID == wanted }) { return match }
        }
        return nil
    }
}
```

- [ ] **Step 4: Add the `--list-audio-processes` CLI mode**

In `Sources/App/MacVisualizerApp.swift`, inside `AppEntry.main()`, add a branch BEFORE the `--render-probe` check (so both are handled). Replace the body of `static func main()` with:

```swift
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--list-audio-processes") {
            for p in ProcessLocator.runningAudioProcesses() {
                print("\(p.bundleID)\t[\(p.id)]")
            }
            exit(0)
        }
        if let idx = args.firstIndex(of: "--render-probe"), idx + 1 < args.count {
            let ok = RenderProbe.run(outputPath: args[idx + 1])
            exit(ok ? 0 : 1)
        }
        MacVisualizerMain.main()
    }
```

- [ ] **Step 5: Build and run the process lister**

Run: `make build` → expect `** BUILD SUCCEEDED **`.

Start Apple Music or Spotify and PLAY a track, then run:
```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --list-audio-processes
```
Expected: a tab-separated list of bundle ids of processes currently producing audio, which should include `com.apple.Music` or `com.spotify.client` while a track plays. (Processes only appear once they have an audio object — i.e. when playing.) If neither appears while music is audibly playing, report what the list DID contain (DONE_WITH_CONCERNS) — do not fake it.

- [ ] **Step 6: Run tests (unchanged)**

Run: `make test` → expect `** TEST SUCCEEDED **`, total 54.

- [ ] **Step 7: Commit**

```bash
git add project.yml Sources/Services/CoreAudioHAL.swift Sources/Services/ProcessLocator.swift Sources/App/MacVisualizerApp.swift
git commit -m "Add Core Audio HAL helpers, ProcessLocator, and --list-audio-processes CLI"
```

---

## Task 5: `AudioCaptureService` (process tap → mono Float32) + `--audio-probe`

**Files:**
- Create: `Sources/Services/AudioCaptureService.swift`
- Create: `Sources/Services/AudioProbe.swift`
- Modify: `Sources/App/MacVisualizerApp.swift` (add `--audio-probe` CLI mode)

This is the irreducible Core Audio integration. Verified by `--audio-probe`, which starts capture for a few seconds and prints per-100ms RMS — non-zero RMS while music plays proves capture works (and triggers the one-time TCC prompt on first run).

- [ ] **Step 1: Write `Sources/Services/AudioCaptureService.swift`**

```swift
import AudioToolbox
import CoreAudio
import AVFoundation
import MacVisualizerCore

/// Captures the audio of a target process (Spotify/Music) via a Core Audio process tap,
/// delivering mono Float32 samples. Not sandboxed; first start triggers the system-audio
/// TCC prompt (declared by NSAudioCaptureUsageDescription). macOS 14.4+.
final class AudioCaptureService: AudioCaptureSource {
    private(set) var state: CaptureState = .stopped
    var onSamples: (([Float], Double) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRate: Double = 48000
    private let ioQueue = DispatchQueue(label: "visualizer.audio.io")

    func start() {
        stop() // idempotent

        guard let target = ProcessLocator.firstTarget() else {
            state = .noTargetProcess
            return
        }

        // 1) Create the tap (stereo mixdown of the target process), unmuted so audio still plays.
        let desc = CATapDescription(stereoMixdownOfProcesses: [target.id])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        var newTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(desc, &newTap)
        guard tapStatus == noErr else { state = .failed("CreateProcessTap \(tapStatus)"); return }
        tapID = newTap

        // 2) Read the tap's stream format (Float32; do not hardcode rate/channels).
        var fmtAddr = CoreAudioHAL.address(kAudioTapPropertyFormat)
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &asbdSize, &asbd) == noErr {
            sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000
        }

        // 3) Create a private aggregate device whose tap list contains our tap.
        let outUID = CoreAudioHAL.defaultOutputDeviceUID() ?? ""
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
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAgg)
        guard aggStatus == noErr else { state = .failed("CreateAggregate \(aggStatus)"); teardown(); return }
        aggregateID = newAgg

        // 4) Install an IO proc that downmixes to mono and forwards samples.
        // Handle BOTH buffer layouts the tap may use: a single interleaved buffer
        // (mNumberChannels > 1) or one buffer per channel (non-interleaved).
        let rate = sampleRate
        let handler = self.onSamples
        var newProc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&newProc, aggregateID, ioQueue) {
            _, inInputData, _, _, _ in
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            guard abl.count > 0 else { return }

            if abl.count == 1 {
                // Interleaved (or already mono): one buffer with mNumberChannels channels.
                let buf = abl[0]
                guard let data = buf.mData else { return }
                let n = Int(buf.mDataByteSize) / MemoryLayout<Float32>.size
                guard n > 0 else { return }
                let ptr = data.bindMemory(to: Float32.self, capacity: n)
                let interleaved = Array(UnsafeBufferPointer(start: ptr, count: n))
                let ch = max(1, Int(buf.mNumberChannels))
                let mono = downmixToMono(interleaved: interleaved, channelCount: ch)
                if !mono.isEmpty { handler?(mono, rate) }
            } else {
                // Non-interleaved: one buffer per channel; average sample-wise.
                var channelPtrs: [UnsafeBufferPointer<Float32>] = []
                var frames = Int.max
                for b in abl {
                    guard let data = b.mData else { continue }
                    let n = Int(b.mDataByteSize) / MemoryLayout<Float32>.size
                    frames = min(frames, n)
                    channelPtrs.append(UnsafeBufferPointer(start: data.bindMemory(to: Float32.self, capacity: n), count: n))
                }
                guard !channelPtrs.isEmpty, frames != Int.max, frames > 0 else { return }
                var mono = [Float](repeating: 0, count: frames)
                let inv = 1 / Float(channelPtrs.count)
                for f in 0..<frames {
                    var s: Float = 0
                    for ch in channelPtrs { s += ch[f] }
                    mono[f] = s * inv
                }
                handler?(mono, rate)
            }
        }
        guard procStatus == noErr, let proc = newProc else {
            state = .failed("CreateIOProc \(procStatus)"); teardown(); return
        }
        ioProcID = proc

        // 5) Start. First time, the system shows the audio-recording permission prompt.
        let startStatus = AudioDeviceStart(aggregateID, proc)
        guard startStatus == noErr else { state = .failed("DeviceStart \(startStatus)"); teardown(); return }
        state = .running
    }

    func stop() {
        teardown()
        state = .stopped
    }

    private func teardown() {
        let unknown = AudioObjectID(kAudioObjectUnknown)
        if aggregateID != unknown, let proc = ioProcID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        if aggregateID != unknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = unknown
        }
        if tapID != unknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = unknown
        }
    }

    deinit { teardown() }
}
```

- [ ] **Step 2: Write `Sources/Services/AudioProbe.swift`**

```swift
import Foundation
import MacVisualizerCore

/// CLI verification: start capture, print RMS of incoming mono samples for `seconds`, then exit.
/// Run with music playing. First run triggers the system-audio permission prompt.
enum AudioProbe {
    static func run(seconds: Double = 5) {
        let service = AudioCaptureService()
        let lock = NSLock()
        var window: [Float] = []

        service.onSamples = { samples, _ in
            lock.lock(); window.append(contentsOf: samples); lock.unlock()
        }
        service.start()
        FileHandle.standardError.write(Data("audio-probe state: \(service.state)\n".utf8))

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            lock.lock(); let chunk = window; window.removeAll(); lock.unlock()
            if chunk.isEmpty { print("rms: --- (no samples)"); continue }
            let rms = sqrtf(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            print(String(format: "rms: %.5f  (samples: %d)", rms, chunk.count))
        }
        service.stop()
    }
}
```

- [ ] **Step 3: Add the `--audio-probe` CLI mode**

In `Sources/App/MacVisualizerApp.swift`, in `AppEntry.main()`, add this branch (after `--list-audio-processes`, before `--render-probe`):

```swift
        if args.contains("--audio-probe") {
            AudioProbe.run()
            exit(0)
        }
```

- [ ] **Step 4: Add the Info.plist usage-description key in `project.yml`**

In `project.yml`, the `MacVisualizer` target's `info.properties` currently has `CFBundleDisplayName`, `LSMinimumSystemVersion`, `NSHighResolutionCapable`. Add one key:

```yaml
        NSAudioCaptureUsageDescription: "Mac Visualizer reads the audio from Spotify or Apple Music to draw the spectrum visualizer."
```

(This declares the system-audio-recording permission; it does not appear in Xcode's dropdown but is required for the tap. No entitlement is needed for this non-sandboxed app.)

- [ ] **Step 5: Build and run the audio probe (with music playing)**

Run: `make build` → expect `** BUILD SUCCEEDED **`.

Start Apple Music or Spotify and PLAY a track at audible volume. Then run:
```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --audio-probe
```
On FIRST run, macOS shows a "MacVisualizer wants to record this computer's audio" prompt — grant it (then re-run if the first run captured nothing because the prompt was open). Expected output: `audio-probe state: running` on stderr, then several lines like `rms: 0.04213 (samples: 4800)` with NON-ZERO rms while music plays. Pausing the music should drop rms toward 0.

If `state` is `noTargetProcess`: Music/Spotify isn't registered as playing — start playback first. If `state` is `failed(...)`: report the exact OSStatus. If rms stays exactly 0.0 across all lines while music is audibly playing AND permission was granted, report that (DONE_WITH_CONCERNS) with the full output — do not fake non-zero numbers.

**This step requires a human with audio playing and permission granted. If you (the agent) cannot play audio or interact with the TCC prompt, build successfully, run the probe once to capture whatever state/output it prints, and report it verbatim with status DONE_WITH_CONCERNS noting that live audio confirmation is pending the user.**

- [ ] **Step 6: Run unit tests (unchanged)**

Run: `make test` → expect `** TEST SUCCEEDED **`, total 54.

- [ ] **Step 7: Commit**

```bash
git add Sources/Services/AudioCaptureService.swift Sources/Services/AudioProbe.swift Sources/App/MacVisualizerApp.swift project.yml
git commit -m "Add Core Audio process-tap capture service and --audio-probe CLI"
```

---

## Task 6: `LatestFrameBox` (thread-safe single-slot frame handoff)

**Files:**
- Create: `Sources/App/LatestFrameBox.swift`

The capture IO callback runs on a background queue; the Metal render loop reads on the main/display thread. A lock-guarded single slot hands the newest `AudioFrame` across without blocking the audio thread on the renderer.

- [ ] **Step 1: Write `Sources/App/LatestFrameBox.swift`**

```swift
import os
import QuartzCore
import MacVisualizerCore

/// Thread-safe holder for the most recent AudioFrame and when it was stored.
/// Writer (DSP queue) calls `store`; reader (render loop) calls `recent`. Last write wins.
final class LatestFrameBox {
    private var lock = os_unfair_lock_s()
    private var frame: AudioFrame = .silent
    private var storedAt: CFTimeInterval = 0

    func store(_ f: AudioFrame, at time: CFTimeInterval) {
        os_unfair_lock_lock(&lock)
        frame = f
        storedAt = time
        os_unfair_lock_unlock(&lock)
    }

    /// The latest frame if stored within `maxAge` of `now`, else nil (caller falls back).
    func recent(now: CFTimeInterval, maxAge: CFTimeInterval) -> AudioFrame? {
        os_unfair_lock_lock(&lock)
        let f = frame
        let t = storedAt
        os_unfair_lock_unlock(&lock)
        return (now - t) < maxAge ? f : nil
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `make build` → expect `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/App/LatestFrameBox.swift
git commit -m "Add thread-safe LatestFrameBox for audio->render frame handoff"
```

---

## Task 7: Wire capture → analyzer → renderer (replace synthetic with real audio)

**Files:**
- Modify: `Sources/App/RenderModel.swift`

`RenderModel` now owns: an `AudioCaptureService`, a `SpectrumAnalyzer`, a `LatestFrameBox`, and the `SyntheticFrameSource` as a fallback. The capture callback downmixed-mono samples → `analyzer.append` → store emitted frames in the box. `currentFrame()` returns the real frame when capture is `.running` and recent; otherwise the synthetic frame (so the window is never blank when nothing is playing).

- [ ] **Step 1: Rewrite `Sources/App/RenderModel.swift`**

Replace the ENTIRE contents with:

```swift
import SwiftUI
import QuartzCore
import MacVisualizerCore

/// Drives rendering from real captured audio, falling back to the synthetic animation
/// when nothing is playing or capture can't start.
final class RenderModel: ObservableObject {
    @Published var settings: VisualizerSettings
    @Published var captureState: CaptureState = .stopped

    private let synthetic: SyntheticFrameSource
    private let analyzer: SpectrumAnalyzer
    private let box = LatestFrameBox()
    private let capture: AudioCaptureSource
    private let dsp = DispatchQueue(label: "visualizer.dsp")

    init(capture: AudioCaptureSource = AudioCaptureService()) {
        let loaded = VisualizerSettings.load(from: VisualizerSettings.defaultFileURL())
        self.settings = loaded
        self.synthetic = SyntheticFrameSource(bandCount: loaded.barCount)
        self.analyzer = SpectrumAnalyzer(fftSize: 2048, sampleRate: 48000, settings: loaded)
        self.capture = capture

        capture.onSamples = { [weak self] samples, _ in
            guard let self else { return }
            self.dsp.async {
                if let frame = self.analyzer.append(samples) {
                    self.box.store(frame, at: CACurrentMediaTime())
                }
            }
        }
        capture.start()
        publishState()
    }

    private func publishState() {
        let s = capture.state
        DispatchQueue.main.async { self.captureState = s }
    }

    /// The frame to render right now: real audio if flowing recently, else synthetic.
    func currentFrame() -> AudioFrame {
        let now = CACurrentMediaTime()
        if capture.state == .running, let frame = box.recent(now: now, maxAge: 0.5) {
            return frame
        }
        return synthetic.frame(at: now)
    }

    deinit { capture.stop() }
}
```

- [ ] **Step 2: Build**

Run: `make build` → expect `** BUILD SUCCEEDED **`. (No `MetalView`/`ContentView` change needed: they already call `model.currentFrame()` and `model.settings` each draw.)

- [ ] **Step 3: Run unit tests**

Run: `make test` → expect `** TEST SUCCEEDED **`, total 54.

- [ ] **Step 4: Verify regression of the render probe (no audio needed)**

```bash
./DerivedData/Build/Products/Debug/MacVisualizer.app/Contents/MacOS/MacVisualizer --render-probe /tmp/probe_p3.png && echo "exit=$?"
```
Read `/tmp/probe_p3.png`: still the green→red staircase (the probe path doesn't use capture, so it must be unchanged).

- [ ] **Step 5: Live verification (requires the user)**

Run `make run` with Apple Music/Spotify playing. Expected: the bars react to the actual music — bass beats drive the low (left) bands, etc. With music paused or stopped, the bars fall back to the synthetic sweeping animation (never blank). On first launch the system-audio permission prompt appears; grant it.

This step is confirmed by the user. The agent should: build successfully, run the render probe (Step 4), and then report that live music-reactive behavior needs user confirmation (status DONE if build+probe+tests pass; note the pending live check).

- [ ] **Step 6: Commit**

```bash
git add Sources/App/RenderModel.swift
git commit -m "Drive visualizer from real captured audio with synthetic fallback"
```

---

## Definition of Done (Plan 3)

- `make test` → `** TEST SUCCEEDED **`, 54 Core tests (downmix + sliding-ring added).
- `make build` → `** BUILD SUCCEEDED **`.
- `MacVisualizer --list-audio-processes` lists Music/Spotify while they play.
- `MacVisualizer --audio-probe` prints non-zero RMS while music plays (permission granted) — confirmed by the user.
- `make run` with music playing: the spectrum bars react to the real audio; with nothing playing they fall back to the synthetic animation. Confirmed by the user.
- Plan 1 ring-buffer carry-forward resolved (sliding overlapping window).

## Handoff to Plan 4 (Metadata overlay & Settings UI)

Plan 4 adds: a `NowPlayingService` (ScriptingBridge to Music/Spotify for title/artist/artwork) and a `TrackOverlay`; and the SwiftUI Settings window bound to `VisualizerSettings` (palette, sensitivity/gain/barCount/smoothing/peak-hold, overlay, window/display), applying changes live — including calling `SpectrumAnalyzer.update(...)` and reconfiguring `barCount`. Also revisit: per-draw `MTLBuffer` allocation in `MetalRenderer.encode` (pool it) now that real-time audio runs the render loop continuously; and surfacing `captureState` (e.g. a hint to grant permission in System Settings when the tap can't start).

### Carry-forward findings from the Plan 3 final code review (APPROVED)

- **Analyzer sample rate is hardcoded to 48000; the captured rate is read but unused (Plan 4 — most important).** `AudioCaptureService` reads the real rate from `kAudioTapPropertyFormat` and passes it as the 2nd arg of `onSamples`, but `RenderModel` discards it (the `_`) and builds `SpectrumAnalyzer(sampleRate: 48000)`. If the tap delivers 44.1 kHz, `BandMapper`'s Hz→bin mapping is off ~8.5% (bands shift slightly; aesthetic, not breaking). Fix: give `SpectrumAnalyzer` a way to reconfigure for a new sample rate (rebuild its `BandMapper`) and have `RenderModel` recreate/reconfigure the analyzer when the delivered rate differs from the one it was built with. Also reconfigure when `barCount` changes (Settings UI). Both naturally fit the Plan 4 live-settings work.
- **`onSamples` is snapshotted at `start()` (minor).** The IO block captures `self.onSamples` once; reassigning it after `start()` would keep calling the stale closure. Current callers set it before `start()`. Add a one-line doc comment on the `AudioCaptureSource` protocol: "set `onSamples` before calling `start()`."
- **Real-time IO thread allocates Arrays (accepted; optimize later).** The IO block allocates Swift `Array`s per callback on the audio queue. Fine at this scale; if profiling shows pressure, use a preallocated scratch buffer.

## Notes on verification honesty (Core Audio)

The process tap cannot be unit-tested (hardware + TCC permission + live playback). Confidence comes from: (1) the pure pieces (`downmixToMono`, sliding ring) are unit-tested; (2) `--list-audio-processes` proves process discovery; (3) `--audio-probe` proves PCM actually flows (non-zero RMS); (4) the user confirms music-reactive bars. Do not claim capture works from build success alone — RMS evidence or user confirmation is required.
