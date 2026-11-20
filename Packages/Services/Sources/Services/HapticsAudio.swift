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

extension ProcessInfo {
    /// True when hosting XCTest or launched with smoke/skip flags that must not block on audio/GC.
    public var isTrashStackTestHost: Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if arguments.contains("-trashStackSkipAds") { return true }
        if UserDefaults.standard.bool(forKey: "trashStack.skipAds") { return true }
        return false
    }
}

@MainActor
public final class HapticsService {
    public static let shared = HapticsService()
#if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
#endif

    public func prepare() {
        // XCTest host + flaky simulators deadlock on CoreHaptics/Audio RPC init.
        guard !ProcessInfo.processInfo.isTrashStackTestHost else { return }
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
    /// Last requested loop — resume this when the player unmutes (playMusic no-ops while muted).
    private var desiredMusic: String?
    /// Reused SFX nodes — creating/attaching per sound caused 50–250 ms frame gaps.
    private var sfxPool: [AVAudioPlayerNode] = []
    private var sfxBusy: Set<ObjectIdentifier> = []
    private let sfxPoolSize = 8
#endif
    private var muted = false
    public var isMuted: Bool { muted }

    public func prepare() {
        // Avoid AVAudioEngine "Initialize: RPC timeout. Apparently deadlocked" under XCTest.
        guard !ProcessInfo.processInfo.isTrashStackTestHost else { return }
#if canImport(AVFoundation)
        guard engine == nil else { return }
        let eng = AVAudioEngine()
        _ = eng.mainMixerNode
        try? eng.start()
        engine = eng
        warmSFXPool(on: eng)
#endif
    }

    private func ensureEngine() {
#if canImport(AVFoundation)
        if engine == nil { prepare() }
#endif
    }

#if canImport(AVFoundation)
    private func warmSFXPool(on eng: AVAudioEngine) {
        guard sfxPool.isEmpty else { return }
        for _ in 0..<sfxPoolSize {
            let player = AVAudioPlayerNode()
            eng.attach(player)
            eng.connect(player, to: eng.mainMixerNode, format: nil)
            sfxPool.append(player)
        }
    }

    private func borrowSFXPlayer() -> AVAudioPlayerNode? {
        ensureEngine()
        guard let engine else { return nil }
        warmSFXPool(on: engine)
        if let free = sfxPool.first(where: { !sfxBusy.contains(ObjectIdentifier($0)) }) {
            sfxBusy.insert(ObjectIdentifier(free))
            return free
        }
        // All busy — recycle the oldest pool slot.
        if let player = sfxPool.first {
            player.stop()
            sfxBusy.insert(ObjectIdentifier(player))
            return player
        }
        return nil
    }

    private func releaseSFXPlayer(_ player: AVAudioPlayerNode) {
        sfxBusy.remove(ObjectIdentifier(player))
    }
#endif

    public func setMuted(_ on: Bool) {
        muted = on
        UserDefaults.standard.set(on, forKey: "trashStack.soundMuted")
#if canImport(AVFoundation)
        engine?.mainMixerNode.outputVolume = on ? 0 : 1
        if !on, let name = desiredMusic {
            playMusic(name)
        }
#endif
    }

    /// Apply persisted mute before any whoosh / music.
    public func applyPersistedMute() {
        let on = UserDefaults.standard.bool(forKey: "trashStack.soundMuted")
        muted = on
#if canImport(AVFoundation)
        engine?.mainMixerNode.outputVolume = on ? 0 : 1
#endif
    }

    public func preloadCommonSFX() {
        ensureEngine()
#if canImport(AVFoundation)
        for name in ["lock", "crush", "recycle", "combo", "levelup", "magnet", "ui", "ember_whoosh"] {
            if buffers[name] == nil, let buf = loadWav(named: name) {
                buffers[name] = buf
            }
        }
#endif
    }

    public func playSFX(_ name: String, pitch: Double = 1.0) {
        guard !muted else { return }
#if canImport(AVFoundation)
        ensureEngine()
        if buffers[name] == nil, let buf = loadWav(named: name) {
            buffers[name] = buf
        }
        guard let engine,
              let buffer = buffers[name],
              let player = borrowSFXPlayer() else {
            blip(frequency: 440 * pitch)
            return
        }
        player.stop()
        // Pool nodes are attached with a nil (mixer) format; WAVs are often mono.
        // Reconnect to the buffer's channel count before scheduleBuffer or AVFAudio asserts.
        let playBuffer: AVAudioPCMBuffer
        if abs(pitch - 1) > 0.01, let pitched = timePitchBuffer(buffer, pitch: pitch) {
            playBuffer = pitched
        } else {
            playBuffer = buffer
        }
        engine.connect(player, to: engine.mainMixerNode, format: playBuffer.format)
        player.scheduleBuffer(playBuffer) { [weak self] in
            Task { @MainActor in self?.releaseSFXPlayer(player) }
        }
        player.play()
#endif
    }

    public func playMusic(_ name: String) {
#if canImport(AVFoundation)
        desiredMusic = name
#endif
        guard !muted else { return }
#if canImport(AVFoundation)
        ensureEngine()
        if musicBuffers[name] == nil, let buf = loadWav(named: name) {
            musicBuffers[name] = buf
        }
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
        desiredMusic = nil
#endif
    }

    public func blip(frequency: Double = 440, duration: Double = 0.05) {
        guard !muted else { return }
#if canImport(AVFoundation)
        ensureEngine()
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
        guard let player = borrowSFXPlayer() else { return }
        player.stop()
        // Temporarily reconnect if format differs — pool nodes use nil format.
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in self?.releaseSFXPlayer(player) }
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
