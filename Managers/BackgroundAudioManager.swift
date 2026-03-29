// BackgroundAudioManager.swift
// ShakeItOff
//
// Plays an inaudible (volume = 0) looping audio buffer using AVAudioEngine.
// This keeps the app's process alive in background indefinitely, which enables:
//   • CMMotionManager to keep delivering sensor callbacks
//   • Timers on the main run loop to keep firing
//   • AudioServicesPlaySystemSound to vibrate even on the lock screen
//     (as long as the screen is ON)
//
// Uses .mixWithOthers so it never interrupts music, podcasts, or calls.
// No audio is audible — the engine's output volume is set to 0.

import AVFoundation
import Observation

@Observable
final class BackgroundAudioManager {

    private(set) var isRunning = false
    private var audioEngine:  AVAudioEngine?
    private var playerNode:   AVAudioPlayerNode?

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else { return }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0   // Completely silent.

            // 1-second silence buffer, looped forever.
            let frameCount: AVAudioFrameCount = 44100
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            buffer.frameLength = frameCount   // Zero-filled = silence.

            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()

            audioEngine  = engine
            playerNode   = player
            isRunning    = true
        } catch {
            print("[BackgroundAudioManager] Failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode  = nil
        audioEngine = nil
        isRunning   = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
