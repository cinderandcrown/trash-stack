// Copyright © 2026 Cinder and Crown LLC. All rights reserved.

import Foundation
#if canImport(Combine)
import Combine
#endif

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

    public func tap() { play(intensity: 0.45, sharpness: 0.35, duration: 0.03) }
    public func lock() { play(intensity: 0.7, sharpness: 0.55, duration: 0.05) }
    public func clear() { play(intensity: 0.95, sharpness: 0.8, duration: 0.12) }
    public func recycle() { play(intensity: 0.65, sharpness: 0.9, duration: 0.08) }

    private func play(intensity: Float, sharpness: Float, duration: TimeInterval) {
#if canImport(CoreHaptics)
        guard let engine else { return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0,
            duration: duration
        )
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
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var musicPlayer: AVAudioPlayerNode?
    private var musicBuffers: [String: AVAudioPCMBuffer] = [:]
    private var currentMusic: String?
#endif
    private var muted = false

    public func prepare() {
#if canImport(AVFoundation)
        let eng = AVAudioEngine()
        _ = eng.mainMixerNode
        try? eng.start()
        engine = eng
        for name in ["lock", "crush", "recycle", "combo", "levelup", "magnet", "ui"] {
            if let buf = loadWav(named: name) {
                buffers[name] = buf
            }
        }
        for name in ["menu_loop", "game_loop"] {
            if let buf = loadWav(named: name) {
                musicBuffers[name] = buf
            }
        }
#endif
    }

    public func setMuted(_ on: Bool) {
        muted = on
#if canImport(AVFoundation)
        engine?.mainMixerNode.outputVolume = on ? 0 : 1
#endif
    }

    public func playSFX(_ name: String, pitch: Double = 1.0) {
        guard !muted else { return }
#if canImport(AVFoundation)
        guard let engine, let buffer = buffers[name] else {
            blip(frequency: 440 * pitch)
            return
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let format = buffer.format
        engine.connect(player, to: engine.mainMixerNode, format: format)
        if abs(pitch - 1) > 0.01, let pitched = timePitchBuffer(buffer, pitch: pitch) {
            player.scheduleBuffer(pitched, completionHandler: nil)
        } else {
            player.scheduleBuffer(buffer, completionHandler: nil)
        }
        player.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak engine] in
            engine?.detach(player)
        }
#endif
    }

    public func playMusic(_ name: String) {
        guard !muted else { return }
#if canImport(AVFoundation)
        guard let engine, let buffer = musicBuffers[name] else { return }
        if currentMusic == name, musicPlayer?.isPlaying == true { return }
        if let old = musicPlayer {
            old.stop()
            engine.detach(old)
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        player.volume = 0.35
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
        musicPlayer = player
        currentMusic = name
#endif
    }

    public func stopMusic() {
#if canImport(AVFoundation)
        if let engine, let player = musicPlayer {
            player.stop()
            engine.detach(player)
        }
        musicPlayer = nil
        currentMusic = nil
#endif
    }

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
                if let engine { engine.detach(player) }
            }
        }
        player.play()
#endif
    }

#if canImport(AVFoundation)
    private func loadWav(named name: String) -> AVAudioPCMBuffer? {
        let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
        guard let url else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let capacity = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        do {
            try file.read(into: buffer)
            return buffer
        } catch {
            return nil
        }
    }

    private func timePitchBuffer(_ buffer: AVAudioPCMBuffer, pitch: Double) -> AVAudioPCMBuffer? {
        // Simple resample-ish pitch: skip/dup frames for SFX juice.
        guard let src = buffer.floatChannelData?[0] else { return nil }
        let ratio = max(0.5, min(2.0, pitch))
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) / ratio)
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: outFrames) else { return nil }
        out.frameLength = outFrames
        let dst = out.floatChannelData![0]
        for i in 0..<Int(outFrames) {
            let srcIndex = min(Int(Double(i) * ratio), Int(buffer.frameLength) - 1)
            dst[i] = src[srcIndex]
        }
        return out
    }
#endif
}
