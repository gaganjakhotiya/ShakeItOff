// VibrationManager.swift
// ShakeItOff
//
// Haptic feedback gated by:
//   1. 60-second active-usage safety cap
//   2. 2-second inter-vibration throttle

import Foundation
import UIKit
import AudioToolbox
import Observation

@Observable
final class VibrationManager {

    // MARK: - Public State

    private(set) var isVibrationPausedForSafety: Bool = false

    // MARK: - Constants

    private let throttleInterval: TimeInterval = 2.0

    // MARK: - Private State

    private var lastVibrationTime: Date?
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Init

    init(screenInteractionTracker: ScreenInteractionTracker) {
        prepareGenerators()
    }

    // MARK: - Public API

    func triggerVibrationIfAllowed(strength: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let lastFired = self.lastVibrationTime,
               Date().timeIntervalSince(lastFired) < self.throttleInterval {
                return
            }

            self.isVibrationPausedForSafety = false
            self.lastVibrationTime = Date()
            self.fireHaptic(strength: strength)
        }
    }

    func resumeVibrationIfReady() {
        DispatchQueue.main.async { [weak self] in
            self?.isVibrationPausedForSafety = false
        }
    }

    // MARK: - Haptic

    private func fireHaptic(strength: String) {
        let generator: UIImpactFeedbackGenerator
        switch strength {
        case "low":
            generator = lightGenerator
        case "high":
            generator = heavyGenerator
        default:
            generator = mediumGenerator
        }

        generator.impactOccurred()
        generator.prepare()

        // Fallback system vibration for devices/contexts where impact feedback is muted.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func prepareGenerators() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
    }
}
