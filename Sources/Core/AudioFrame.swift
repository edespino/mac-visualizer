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
import QuartzCore

public struct AudioFrame: Equatable {
    public var bands: [Float]
    public var bandsLeft: [Float]
    public var bandsRight: [Float]
    public var bandPeaks: [Float]
    public var waveform: [Float]
    /// Per-channel time-domain waveforms, mirroring the bands convention:
    /// for mono sources `waveformLeft == waveformRight == waveform`. Consumed
    /// by styles that plot the channels against each other (XY scope).
    public var waveformLeft: [Float]
    public var waveformRight: [Float]
    public var rms: Float
    public var peak: Float
    public var timestamp: CFTimeInterval
    public var beat: Bool
    public var beatIntensity: Float
    /// Pre-gain mean FFT magnitude over a fixed ~30–150 Hz window, independent
    /// of band mapping, barCount, and per-style gain. Feeds `LyricBeatFollower`
    /// so the active lyric line's shadow bounces to the bass/kick.
    public var bassEnergy: Float
    /// Session-only track identifier: "\(playerBundleID)|\(title)|\(artist)|\(album)".
    /// Nil when no track is playing. Used by VoronoiVisualizer(.perTrack) to detect
    /// track changes and trigger a fade-to-black / reseed transition.
    public var trackId: String?

    /// Mono-source convenience init: `bandsLeft = bandsRight = bands` and
    /// `waveformLeft = waveformRight = waveform`.
    public init(bands: [Float], bandPeaks: [Float], waveform: [Float],
                rms: Float, peak: Float, timestamp: CFTimeInterval,
                beat: Bool = false, beatIntensity: Float = 0,
                bassEnergy: Float = 0,
                trackId: String? = nil) {
        self.bands = bands
        self.bandsLeft = bands
        self.bandsRight = bands
        self.bandPeaks = bandPeaks
        self.waveform = waveform
        self.waveformLeft = waveform
        self.waveformRight = waveform
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
        self.beat = beat
        self.beatIntensity = beatIntensity
        self.bassEnergy = bassEnergy
        self.trackId = trackId
    }

    /// Stereo init. `bands` is provided explicitly (caller is responsible for
    /// honoring the mean invariant `bands[i] == (bandsLeft[i] + bandsRight[i]) / 2`).
    /// Channel waveforms default to the mono `waveform` when not supplied, so
    /// existing constructors keep their behavior.
    public init(bands: [Float], bandsLeft: [Float], bandsRight: [Float],
                bandPeaks: [Float], waveform: [Float],
                waveformLeft: [Float]? = nil, waveformRight: [Float]? = nil,
                rms: Float, peak: Float, timestamp: CFTimeInterval,
                beat: Bool = false, beatIntensity: Float = 0,
                bassEnergy: Float = 0,
                trackId: String? = nil) {
        self.bands = bands
        self.bandsLeft = bandsLeft
        self.bandsRight = bandsRight
        self.bandPeaks = bandPeaks
        self.waveform = waveform
        self.waveformLeft = waveformLeft ?? waveform
        self.waveformRight = waveformRight ?? waveform
        self.rms = rms
        self.peak = peak
        self.timestamp = timestamp
        self.beat = beat
        self.beatIntensity = beatIntensity
        self.bassEnergy = bassEnergy
        self.trackId = trackId
    }

    public static let silent = AudioFrame(bands: [], bandPeaks: [], waveform: [],
                                          rms: 0, peak: 0, timestamp: 0)
}