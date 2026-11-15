// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation

#if canImport(CoreHaptics)
import CoreHaptics
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
public final class HapticsService {
    public static let shared = HapticsService()
#if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
#endif

    public func prepare() {
#if canImport(CoreHaptics)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        try? engine?.start()
#endif
    }

    public func tap() {
#if canImport(CoreHaptics)
        guard let engine else { return }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
        ], relativeTime: 0)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
#endif
    }
}

@MainActor
public final class AudioService {
    public static let shared = AudioService()
#if canImport(AVFoundation)
    private var engine: AVAudioEngine?
#endif
    private var muted = false

    public func prepare() {
#if canImport(AVFoundation)
        let eng = AVAudioEngine()
        _ = eng.mainMixerNode
        try? eng.start()
        engine = eng
#endif
    }

    public func setMuted(_ on: Bool) { muted = on }

    public func blip(frequency: Double = 440, duration: Double = 0.05) {
        guard !muted else { return }
#if canImport(AVFoundation)
        guard let engine else { return }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            data[i] = Float(sin(2 * Double.pi * frequency * t) * 0.2 * (1 - t / duration))
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer) { [weak engine] in
            Task { @MainActor in
                if let engine {
                    engine.detach(player)
                }
            }
        }
        player.play()
#endif
    }
}
