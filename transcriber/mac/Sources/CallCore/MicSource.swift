import AVFoundation
import Foundation

/// Your own voice. The other party's audio comes from `ProcessTapSource`
/// instead; keeping them apart is what labels the transcript.
public final class MicSource {
    private let engine = AVAudioEngine()
    private var running = false

    public init() {}

    public func start(_ sink: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        guard !running else { return }
        #if os(iOS)
        // Without this the engine gets a sample rate it cannot use, or no input
        // at all. `.measurement` keeps iOS from applying its own processing to
        // audio we are about to transcribe.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try audioSession.setActive(true)
        #endif
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            sink(buffer, time)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    public func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}
