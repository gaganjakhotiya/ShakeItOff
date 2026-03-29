// VibrationManager.swift
// ShakeItOff
//
// Haptic feedback gated by:
//   1. 60-second active-usage safety cap
//   2. 2-second inter-vibration throttle

import Foundation
import UIKit
import Observation

@Observable
final class VibrationManager {

    // MARK: - Public State

    private(set) var isVibrationPausedForSafety: Bool = false

    // MARK: - Constants

    private let activeUsageMax: TimeInterval = 60.0
    private let throttleInterval: TimeInterval = 2.0

    // MARK: - Dependencies

    private weak var tracker: ScreenInteractionTracker?

    // MARK: - Private State

    private var lastVibrationTime: Date?

    // MARK: - Init

    init(screenInteractionTracker: ScreenInteractionTracker) {
        self.tracker = screenInteractionTracker
    }

    // MARK: - Public API

    func triggerVibrationIfAllowed(strength: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Auto-resume if the tracker has gone idle since the last pause.
            if self.isVibrationPausedForSafety, self.tracker?.isActivelyUsing == false {
                self.isVibrationPausedForSafety = false
            }

            // Gate 1: 60-second active-usage safety cap.
            if let t = self.tracker, t.isActivelyUsing,
               t.activeUsageDuration >= self.activeUsageMax {
                self.isVibrationPausedForSafety = true
                return
            }

            // Gate 2: 2-second inter-vibration throttle.
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
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch strength {
        case "low":  style = .light
        case "high": style = .heavy
        default:     style = .medium
        }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
