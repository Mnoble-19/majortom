import AVFoundation
import AppKit
import CoreAudio
import Darwin
import Foundation

/// An app that Core Audio knows about, whether or not it is making noise.
public struct AudioProcess: Sendable, Identifiable, Hashable {
    public let id: AudioObjectID
    public let pid: pid_t
    public let name: String
    public let bundleID: String
    /// True while the process is actually playing audio. This is how a call app
    /// is found without asking anyone to pick from a list.
    public let isPlaying: Bool
}

public enum ProcessTapError: Error, CustomStringConvertible {
    case noSuchProcess(String)
    case tapFailed(OSStatus)
    case aggregateFailed(OSStatus)
    case noTapFormat
    case ioProcFailed(OSStatus)

    public var description: String {
        switch self {
        case .noSuchProcess(let q): return "no running audio process matching \"\(q)\""
        case .tapFailed(let s): return "could not create the process tap (\(s)) — check System Settings → Privacy & Security → Screen & System Audio Recording"
        case .aggregateFailed(let s): return "could not create the aggregate device (\(s))"
        case .noTapFormat: return "the tap reported no audio format"
        case .ioProcFailed(let s): return "could not start reading the tap (\(s))"
        }
    }
}

private let systemObject = AudioObjectID(kAudioObjectSystemObject)

private func address(
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default fallback: T) -> T {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<T>.size)
    var value = fallback
    let status = withUnsafeMutableBytes(of: &value) { raw in
        AudioObjectGetPropertyData(object, &addr, 0, nil, &size, raw.baseAddress!)
    }
    return status == noErr ? value : fallback
}

/// Core Audio hands back a +1 CFString for these properties, so ownership has
/// to be taken explicitly or the string leaks.
private func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    let status = withUnsafeMutableBytes(of: &value) { raw in
        AudioObjectGetPropertyData(object, &addr, 0, nil, &size, raw.baseAddress!)
    }
    guard status == noErr, let value else { return "" }
    return value.takeRetainedValue() as String
}

private func executableName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
    return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
}

public enum AudioProcesses {
    /// Every process Core Audio is tracking. Most are silent system services;
    /// `WhatsApp`, `Signal`, `zoom.us` and friends show up here by bundle id.
    public static func running() -> [AudioProcess] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            let pid = read(id, kAudioProcessPropertyPID, default: pid_t(-1))
            guard pid > 0 else { return nil }
            let bundleID = readString(id, kAudioProcessPropertyBundleID)
            // Command-line tools have no bundle and no NSRunningApplication, so
            // fall back to the executable name rather than dropping them.
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName
                ?? (bundleID.isEmpty ? executableName(pid) : bundleID)
            let playing = read(id, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0
            return AudioProcess(id: id, pid: pid, name: name, bundleID: bundleID, isPlaying: playing)
        }
    }

    /// Every process belonging to one app, matched loosely on name or bundle id.
    ///
    /// Returning a group rather than a single process is deliberate. Modern call
    /// apps are several processes, and the voice does not necessarily come out of
    /// the one you would name: WhatsApp exposes
    /// `net.whatsapp.WhatsApp.ServiceExtension` beside the main app. Tapping the
    /// whole group means never having to know which is which.
    public static func group(_ query: String) -> [AudioProcess] {
        let needle = query.lowercased()
        return running().filter {
            $0.bundleID.lowercased().contains(needle) || $0.name.lowercased().contains(needle)
        }
    }

    /// Apps currently playing audio, loudest candidate for "the call" first.
    ///
    /// System services are filtered out — they register as audio processes but
    /// are never what you are trying to transcribe.
    public static func playing() -> [AudioProcess] {
        running()
            .filter(\.isPlaying)
            .filter { !isSystemService($0) }
    }

    /// The app to tap, chosen without asking: whatever is playing audio. Returns
    /// every process of that app.
    public static func likelyCall() -> [AudioProcess] {
        guard let first = playing().first else { return [] }
        let siblings = running().filter { $0.bundleID == first.bundleID && $0.bundleID != "" }
        return siblings.isEmpty ? [first] : siblings
    }

    private static func isSystemService(_ process: AudioProcess) -> Bool {
        let id = process.bundleID.lowercased()
        if id.isEmpty { return false }
        // Apple's own audio plumbing, not a call app. Safari and Music are
        // deliberately not excluded — they are plausible sources of German.
        let noise = [
            "com.apple.controlcenter", "com.apple.loginwindow", "com.apple.powerchime",
            "com.apple.universalaccessd", "com.apple.audiomxd", "com.apple.corespeech",
            "com.apple.mediaanalysisd", "com.apple.mediaremoted", "com.apple.telephonyutilities",
            "com.apple.accessibility.heard", "systemsoundserverd",
            "com.apple.cmio.continuitycaptureagent", "com.apple.avconferenced"
        ]
        return noise.contains(id)
    }
}

/// The other party's voice: a tap on one app's audio output.
///
/// This taps the app rather than the whole system on purpose. Tapping
/// everything would also pick up a YouTube video in another window, and — worse
/// — the app's own playback of *your* mic if the call app monitors it, which
/// would put your words on their track.
///
/// The tap does not mute anything; you still hear the call normally.
public final class ProcessTapSource {
    public let format: AVAudioFormat

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var running = false

    public init(processes: [AudioProcess]) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes.map(\.id))
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr, tapID != kAudioObjectUnknown else {
            throw ProcessTapError.tapFailed(tapStatus)
        }

        var asbd = AudioStreamBasicDescription()
        var addr = address(kAudioTapPropertyFormat)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd) == noErr,
              let tapFormat = AVAudioFormat(streamDescription: &asbd) else {
            AudioHardwareDestroyProcessTap(tapID)
            throw ProcessTapError.noTapFormat
        }
        format = tapFormat

        // A tap is not a device, so it cannot be read directly — it has to be
        // wrapped in a private aggregate device built around the current output
        // device. Private means it never appears in Sound settings.
        let outputUID = Self.defaultOutputDeviceUID()
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MajorTom Call Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString
            ]]
        ]
        let aggregateStatus = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregateID)
        guard aggregateStatus == noErr, aggregateID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            throw ProcessTapError.aggregateFailed(aggregateStatus)
        }
    }

    deinit { stop(); teardown() }

    public func start(_ sink: @escaping (AVAudioPCMBuffer, AVAudioTime?) -> Void) throws {
        guard !running else { return }
        let format = self.format

        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, input, _, _, _ in
            // This buffer belongs to Core Audio and is valid only for the
            // duration of this callback, so it is copied before it escapes.
            guard let source = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input),
                  let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: source.frameLength) else { return }
            copy.frameLength = source.frameLength

            // Copy buffer by buffer rather than through `floatChannelData`: a
            // tap's format is interleaved, and an interleaved buffer exposes a
            // single channel pointer, so indexing per channel reads off the end.
            let from = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: source.audioBufferList))
            let to = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (source, destination) in zip(from, to) {
                guard let src = source.mData, let dst = destination.mData else { continue }
                memcpy(dst, src, Int(min(source.mDataByteSize, destination.mDataByteSize)))
            }
            sink(copy, nil)
        }
        guard status == noErr, let ioProc else { throw ProcessTapError.ioProcFailed(status) }

        let startStatus = AudioDeviceStart(aggregateID, ioProc)
        guard startStatus == noErr else { throw ProcessTapError.ioProcFailed(startStatus) }
        running = true
    }

    public func stop() {
        guard running, let ioProc else { return }
        AudioDeviceStop(aggregateID, ioProc)
        AudioDeviceDestroyIOProcID(aggregateID, ioProc)
        self.ioProc = nil
        running = false
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
    }

    private static func defaultOutputDeviceUID() -> String {
        let deviceID = read(systemObject, kAudioHardwarePropertyDefaultOutputDevice,
                            default: AudioObjectID(kAudioObjectUnknown))
        guard deviceID != kAudioObjectUnknown else { return "" }
        return readString(deviceID, kAudioDevicePropertyDeviceUID)
    }
}
