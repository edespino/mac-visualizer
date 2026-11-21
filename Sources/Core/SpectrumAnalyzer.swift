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
import Accelerate
import QuartzCore

/// Turns streamed PCM into `AudioFrame`s via the full DSP pipeline. Supports
/// per-channel (L+R) analysis: `bandsLeft` / `bandsRight` on the output frame.
/// Single-channel callers can use the legacy `append(_:)` overload, which
/// internally feeds the same buffer to both channels.
/// Not thread-safe; confine to a single analysis queue.
public final class SpectrumAnalyzer {
    /// How the spectrum folds into `frame.bands`: classic log-spaced bars, or
    /// one band per semitone for note-aligned displays (Musical Spectrum).
    /// `.logSpaced` uses the live `barCount`; `.notes` fixes the band count to
    /// its note count until switched back.
    public enum BandMapping: Equatable {
        case logSpaced
        case notes(minMidi: Int, count: Int)
    }

    private let fftSize: Int
    private let waveformPointCount = 256
    private var sampleRate: Float
    private var barCount: Int
    private var mapping: BandMapping = .logSpaced
    private var window: [Float]
    private var windowKind: FFTWindow
    private let fftL: FFTProcessor
    private let fftR: FFTProcessor
    private var mapper: BandMapper
    private var postL: BandPostProcessor
    private var postR: BandPostProcessor
    private var beatDetector = BeatDetector()

    private var ringL: [Float] = []
    private var ringR: [Float] = []

    public init(fftSize: Int = 2048, sampleRate: Float = 48000, settings: VisualizerSettings) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.barCount = settings.barCount
        self.windowKind = settings.fftWindow
        self.window = makeWindow(settings.fftWindow, count: fftSize)
        self.fftL = FFTProcessor(size: fftSize)
        self.fftR = FFTProcessor(size: fftSize)
        self.mapper = BandMapper(bandCount: settings.barCount, fftSize: fftSize, sampleRate: sampleRate)
        self.postL = BandPostProcessor(bandCount: settings.barCount,
                                        gain: settings.gain,
                                        smoothing: settings.smoothing,
                                        peakDecay: settings.peakHoldEnabled ? 0.95 : 0.0)
        self.postR = BandPostProcessor(bandCount: settings.barCount,
                                        gain: settings.gain,
                                        smoothing: settings.smoothing,
                                        peakDecay: settings.peakHoldEnabled ? 0.95 : 0.0)
        self.ringL.reserveCapacity(fftSize * 2)
        self.ringR.reserveCapacity(fftSize * 2)
    }

    /// Live-tune the parameters that can change without reallocating buffers.
    public func update(gain: Float, smoothing: Float, peakHoldEnabled: Bool) {
        postL.gain = gain
        postR.gain = gain
        postL.smoothing = smoothing
        postR.smoothing = smoothing
        let decay: Float = peakHoldEnabled ? 0.95 : 0.0
        postL.peakDecay = decay
        postR.peakDecay = decay
    }

    /// Live-tune the window function. Recomputes the window coefficients in
    /// place; the next `append(...)` picks them up. Call on the same queue as
    /// `append`.
    public func setWindow(_ kind: FFTWindow) {
        guard kind != windowKind else { return }
        windowKind = kind
        window = makeWindow(kind, count: fftSize)
    }

    /// Rebuild the band mapper / post-processors for a new sample rate and/or
    /// bar count. Preserves current gain/smoothing/peak-hold. The FFT and window
    /// are unaffected (they depend only on fftSize). Resets the beat detector
    /// only when the sample rate changes (barCount-only changes preserve the
    /// auto-tuned threshold). Call on the same queue as `append`.
    public func reconfigure(sampleRate newRate: Float? = nil, barCount newBarCount: Int? = nil) {
        if let r = newRate { sampleRate = r }
        if let b = newBarCount { barCount = b }
        rebuildMapper()
        if newRate != nil { beatDetector.reset() }
    }

    /// Switch how the spectrum folds into bands. A no-op when unchanged;
    /// otherwise rebuilds the mapper and resizes the post-processors to the
    /// mapping's band count (notes fix it; logSpaced follows barCount).
    /// Call on the same queue as `append`.
    public func setBandMapping(_ newMapping: BandMapping) {
        guard newMapping != mapping else { return }
        mapping = newMapping
        rebuildMapper()
    }

    private func rebuildMapper() {
        let bandCount: Int
        switch mapping {
        case .logSpaced:
            bandCount = barCount
            mapper = BandMapper(bandCount: barCount, fftSize: fftSize, sampleRate: sampleRate)
        case .notes(let minMidi, let count):
            bandCount = max(1, count)
            mapper = BandMapper(minMidiNote: minMidi, noteCount: bandCount,
                                fftSize: fftSize, sampleRate: sampleRate)
        }
        postL = BandPostProcessor(bandCount: bandCount, gain: postL.gain, smoothing: postL.smoothing, peakDecay: postL.peakDecay)
        postR = BandPostProcessor(bandCount: bandCount, gain: postR.gain, smoothing: postR.smoothing, peakDecay: postR.peakDecay)
    }

    /// Mono convenience: feed the same buffer to both channels. Returns
    /// `bandsLeft == bandsRight == bands` on the frame.
    @discardableResult
    public func append(_ samples: [Float]) -> AudioFrame? {
        return append(left: samples, right: samples)
    }

    /// Dual-channel append. Returns a frame when both rings have a full window.
    @discardableResult
    public func append(left: [Float], right: [Float]) -> AudioFrame? {
        ringL.append(contentsOf: left)
        ringR.append(contentsOf: right)
        if ringL.count > fftSize { ringL.removeFirst(ringL.count - fftSize) }
        if ringR.count > fftSize { ringR.removeFirst(ringR.count - fftSize) }
        guard ringL.count == fftSize && ringR.count == fftSize else { return nil }

        let l = ringL, r = ringR

        var rmsL: Float = 0, rmsR: Float = 0
        vDSP_rmsqv(l, 1, &rmsL, vDSP_Length(fftSize))
        vDSP_rmsqv(r, 1, &rmsR, vDSP_Length(fftSize))
        let rms = (rmsL + rmsR) / 2

        var minL: Float = 0, maxL: Float = 0, minR: Float = 0, maxR: Float = 0
        vDSP_minv(l, 1, &minL, vDSP_Length(fftSize))
        vDSP_maxv(l, 1, &maxL, vDSP_Length(fftSize))
        vDSP_minv(r, 1, &minR, vDSP_Length(fftSize))
        vDSP_maxv(r, 1, &maxR, vDSP_Length(fftSize))
        let peak = max(abs(minL), abs(maxL), abs(minR), abs(maxR))

        let wL = zip(l, window).map(*)
        let wR = zip(r, window).map(*)
        let magsL = fftL.magnitudes(of: wL)
        let magsR = fftR.magnitudes(of: wR)

        // Pre-gain bass energy for the lyric beat follower: mean raw FFT
        // magnitude over a fixed ~30–150 Hz window, averaged across channels.
        // Taken off the FFT magnitudes (not the band mapper), so it is
        // independent of barCount, band mapping, and gain. Bin 0 (DC) excluded.
        let bassLoBin = max(1, Int(30 * Float(fftSize) / sampleRate))
        let bassHiBin = min(magsL.count - 1, Int(150 * Float(fftSize) / sampleRate))
        var bassEnergy: Float = 0
        if bassHiBin >= bassLoBin {
            var sum: Float = 0
            for i in bassLoBin...bassHiBin { sum += magsL[i] + magsR[i] }
            bassEnergy = sum / Float((bassHiBin - bassLoBin + 1) * 2)
        }

        let rawL = mapper.bands(from: magsL)
        let rawR = mapper.bands(from: magsR)
        let procL = postL.process(rawL)
        let procR = postR.process(rawR)

        var bands = [Float](repeating: 0, count: procL.bands.count)
        var peaks = [Float](repeating: 0, count: procL.peaks.count)
        for i in 0..<bands.count {
            bands[i] = (procL.bands[i] + procR.bands[i]) / 2
            peaks[i] = max(procL.peaks[i], procR.peaks[i])
        }

        // Mono waveform from L channel (visually equivalent; cheaper than
        // averaging); per-channel waveforms sampled at the SAME indices so the
        // XY scope's (L[i], R[i]) pairs are time-aligned.
        let step = max(1, fftSize / waveformPointCount)
        var wave = [Float]()
        var waveR = [Float]()
        wave.reserveCapacity(waveformPointCount)
        waveR.reserveCapacity(waveformPointCount)
        var wi = 0
        while wi < l.count && wave.count < waveformPointCount {
            wave.append(l[wi]); waveR.append(r[wi]); wi += step
        }

        let now = CACurrentMediaTime()
        let beatResult = beatDetector.update(peak: peak, timestamp: now)

        return AudioFrame(
            bands: bands,
            bandsLeft: procL.bands,
            bandsRight: procR.bands,
            bandPeaks: peaks,
            waveform: wave,
            waveformLeft: wave,
            waveformRight: waveR,
            rms: rms,
            peak: peak,
            timestamp: now,
            beat: beatResult.beat,
            beatIntensity: beatResult.intensity,
            bassEnergy: bassEnergy
        )
    }
}