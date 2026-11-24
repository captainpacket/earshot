// The driven adapter for CallAudioTap (ADR-2611240900): a Core Audio process tap (macOS 14.2+).
// Needs only the "System Audio Recording Only" permission (NSAudioCaptureUsageDescription), never Screen Recording.
// Audio is held in memory and handed back as one AudioSignal at stop; nothing is written to disk here.
import AppKit
import AVFoundation
import CoreAudio
import Foundation

final class CoreAudioTap: CallAudioTap, @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private let lock = NSLock()
    private var samples: [Float] = []
    private let queue = DispatchQueue(label: "earshot.call-audio-tap")

    static var isSupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0))
    }

    /// Running apps the user can choose from: bundle id and name, regular apps only.
    static func runningApps() -> [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func start(_ plan: TapPlan) throws {
        guard Self.isSupported, #available(macOS 14.2, *) else { throw AppError(message: "Call audio needs macOS 14.2 or later.") }
        let description: CATapDescription
        switch plan {
        case .none: return
        case .allSystem:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        case .app(let bundleID):
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                  let object = Self.processObject(pid: app.processIdentifier) else {
                throw AppError(message: "That app is not running.")
            }
            description = CATapDescription(stereoMixdownOfProcesses: [object])
        }
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else {
            throw AppError(message: "Call audio could not be started. Check System Settings → Privacy & Security.")
        }
        tapID = tap
        do { try buildAggregate(tapUID: description.uuid.uuidString); try startIO() }
        catch { teardown(); throw error }
    }

    private func buildAggregate(tapUID: String) throws {
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Earshot call audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggregateID) == noErr else {
            throw AppError(message: "Call audio could not be started.")
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr else {
            throw AppError(message: "Call audio could not be started.")
        }
    }

    private func startIO() throws {
        let channels = Int(max(1, format.mChannelsPerFrame))
        guard AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, { [weak self] _, input, _, _, _ in
            guard let self else { return }
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            for b in buffers where b.mData != nil && b.mDataByteSize > 0 {
                let count = Int(b.mDataByteSize) / MemoryLayout<Float>.size
                let chunk = Array(UnsafeBufferPointer(start: b.mData!.assumingMemoryBound(to: Float.self), count: count))
                if Int(b.mNumberChannels) == channels || buffers.count == 1 {
                    self.lock.lock(); self.samples += chunk; self.lock.unlock()
                }
            }
        }) == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else {
            throw AppError(message: "Call audio could not be started.")
        }
    }

    func stop() { teardown() }

    /// Stops the tap and returns what it heard as one signal; empty when nothing was captured.
    func finish() -> AudioSignal {
        teardown()
        lock.lock(); defer { lock.unlock() }
        let signal = AudioSignal(samples: samples, sampleRate: format.mSampleRate > 0 ? format.mSampleRate : 48_000,
                                 channels: Int(max(1, format.mChannelsPerFrame)))
        samples = []
        return signal
    }

    private func teardown() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }

    private static func processObject(pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid = pid, object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }
}

/// Mixes the tap's signal into the finished microphone WAV, in place (16 kHz mono, 16-bit), so one file results.
enum CallAudioWav {
    static func merge(_ tap: AudioSignal, into url: URL) throws {
        guard !tap.samples.isEmpty else { return }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: max(frames, 1)) else { return }
        try file.read(into: buffer)
        let mic = AudioSignal(samples: Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))),
                              sampleRate: file.processingFormat.sampleRate, channels: 1)
        let mixed = CallAudioMix.mix(mic: mic, tap: tap)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: CallAudioMix.outputRate,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".mixing-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            let out = try AVAudioFile(forWriting: tmp, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let ob = AVAudioPCMBuffer(pcmFormat: out.processingFormat, frameCapacity: AVAudioFrameCount(mixed.count)) else { return }
            ob.frameLength = AVAudioFrameCount(mixed.count)
            mixed.withUnsafeBufferPointer { ob.floatChannelData![0].update(from: $0.baseAddress!, count: mixed.count) }
            try out.write(from: ob)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}

/// Where the choice and the remembered permission state live. "" = None, "all", or "app:<bundle id>".
enum CallAudioPrefs {
    static let source = "callAudioSource"
    private static let permissionKey = "callAudioPermission"
    static var permission: CallAudioPermission {
        get { switch UserDefaults.standard.string(forKey: permissionKey) { case "granted": .granted; case "refused": .refused; default: .notAsked } }
        set { UserDefaults.standard.set("\(newValue)", forKey: permissionKey) }
    }
}
