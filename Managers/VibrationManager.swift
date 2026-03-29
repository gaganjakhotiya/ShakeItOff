// VibrationManager.swift
// ShakeItOff
//
// Two vibration modes depending on app state:
//
//   FOREGROUND  → CHHapticEngine (.hapticContinuous) — true solid buzz, variable intensity.
//                 iOS disables this engine the moment the app leaves foreground.
//
//   BACKGROUND  → AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) on a repeating
//                 Timer. Works as long as the process is alive (kept alive by
//                 BackgroundAudioManager). Fires even on the lock screen when the
//                 screen is ON (raise-to-wake / lock screen visible).
//                 Intensity maps to pulse interval: low=2s, mid=1s, high=0.5s.
//
// Intensity (foreground):
//   low  → 0.3  (gentle hum)
//   mid  → 0.65 (firm buzz)
//   high → 1.0  (full throttle)

import Foundation
import CoreHaptics
import AudioToolbox
import UIKit
import Observation

@Observable
final class VibrationManager {

    // MARK: - Public State

    private(set) var isVibrationPausedForSafety = false
    private(set) var isContinuouslyVibrating    = false

    // MARK: - Constants

    private let activeUsageMax:    TimeInterval = 60.0
    private let hapticEventDuration: TimeInterval = 120.0

    // MARK: - Foreground: CHHapticEngine

    private var hapticEngine:      CHHapticEngine?
    private var continuousPlayer:  CHHapticAdvancedPatternPlayer?

    // MARK: - Background: AudioServices timer

    private var backgroundTimer:   Timer?

    // MARK: - Shared State

    private var currentStrength:   String = "mid"
    private var isInBackground:    Bool   = false

    // MARK: - Safety Monitor

    private weak var tracker: ScreenInteractionTracker?
    private var safetyTimer:  Timer?

    // MARK: - Init

    init(screenInteractionTracker: ScreenInteractionTracker) {
        self.tracker = screenInteractionTracker
        setupHapticEngine()
        subscribeToAppLifecycle()
    }

    // MARK: - Haptic Engine Setup

    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.resetHandler = { [weak engine] in
                try? engine?.start()
            }
            engine.stoppedHandler = { _ in }
            try engine.start()
            hapticEngine = engine
        } catch {
            print("[VibrationManager] Haptic engine init failed: \(error)")
        }
    }

    // MARK: - Public API

    func startContinuousVibration(strength: String) {
        currentStrength         = strength
        isContinuouslyVibrating = true

        if isInBackground {
            stopForegroundHaptic()
            startBackgroundPulse(strength: strength)
        } else {
            stopBackgroundPulse()
            startForegroundHaptic(strength: strength)
        }
        startSafetyMonitor()
    }

    func stopContinuousVibration() {
        stopForegroundHaptic()
        stopBackgroundPulse()
        isContinuouslyVibrating = false
        stopSafetyMonitor()
    }

    func updateStrength(_ strength: String) {
        guard isContinuouslyVibrating else { return }
        startContinuousVibration(strength: strength)
    }

    func resumeVibrationIfReady() {
        isVibrationPausedForSafety = false
    }

    // MARK: - Foreground: CHHapticEngine Continuous

    private func startForegroundHaptic(strength: String) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else {
            // Haptics not available — fall back to AudioServices even in foreground.
            startBackgroundPulse(strength: strength)
            return
        }
        stopForegroundHaptic()
        try? engine.start()

        let intensity: Float
        switch strength {
        case "low":  intensity = 0.3
        case "high": intensity = 1.0
        default:     intensity = 0.65
        }

        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: 0,
                duration: hapticEventDuration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player  = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            continuousPlayer = player
        } catch {
            print("[VibrationManager] Foreground haptic failed: \(error) — falling back to AudioServices")
            startBackgroundPulse(strength: strength)
        }
    }

    private func stopForegroundHaptic() {
        try? continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        continuousPlayer = nil
    }

    // MARK: - Background: AudioServices Repeating Pulse

    private func startBackgroundPulse(strength: String) {
        stopBackgroundPulse()

        // Pulse interval encodes intensity: shorter gap = stronger perceived feedback.
        let interval: TimeInterval
        switch strength {
        case "low":  interval = 2.0
        case "high": interval = 0.5
        default:     interval = 1.0
        }

        // Immediate first hit.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        // Use .common mode so the timer fires even when the run loop is processing
        // touch events or other input — critical for background reliability.
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer
    }

    private func stopBackgroundPulse() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    // MARK: - App Lifecycle

    private func subscribeToAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isInBackground = true
            if self.isContinuouslyVibrating {
                // CHHapticEngine is killed by iOS — switch to AudioServices immediately.
                self.stopForegroundHaptic()
                self.startBackgroundPulse(strength: self.currentStrength)
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isInBackground = false
            try? self.hapticEngine?.start()   // Restart engine after backgrounding.
            if self.isContinuouslyVibrating {
                // Switch back to smooth CHHapticEngine mode.
                self.stopBackgroundPulse()
                self.startForegroundHaptic(strength: self.currentStrength)
            }
        }
    }

    // MARK: - Safety Monitor (60 s cap)

    private func startSafetyMonitor() {
        safetyTimer?.invalidate()
        safetyTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let t = self.tracker, t.isActivelyUsing,
               t.activeUsageDuration >= self.activeUsageMax {
                if !self.isVibrationPausedForSafety {
                    self.isVibrationPausedForSafety = true
                    self.stopContinuousVibration()
                }
            } else if self.isVibrationPausedForSafety, self.tracker?.isActivelyUsing == false {
                self.isVibrationPausedForSafety = false
            }
        }
        RunLoop.main.add(safetyTimer!, forMode: .common)
    }

    private func stopSafetyMonitor() {
        safetyTimer?.invalidate()
        safetyTimer = nil
    }
}
