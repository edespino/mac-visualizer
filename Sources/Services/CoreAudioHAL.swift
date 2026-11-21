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

    /// The default OUTPUT device's UID — the device the tapped app (Spotify/
    /// Music) actually renders to, used as the aggregate device's clock/main
    /// sub-device. This is `kAudioHardwarePropertyDefaultOutputDevice` (main
    /// output), NOT `DefaultSystemOutputDevice` (the system-alert output),
    /// which can be a different device entirely and leave the aggregate clocked
    /// to a device the music is not flowing through.
    static func defaultOutputDeviceUID() -> String? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr
        else { return nil }
        return string(deviceID, kAudioDevicePropertyDeviceUID)
    }
}