// ScreenInteractionTracker.swift
// ShakeItOff
//
// Tracks continuous "active usage" sessions.
// A session begins on the first recordUserInteraction() call after 5+ s of quiet.
// It ends when no interaction is recorded for INACTIVITY_THRESHOLD seconds.

import Foundation
import UIKit
import Observation

@Observable
final class ScreenInteractionTracker {

    // MARK: - Public State

    private(set) var isActivelyUsing: Bool = false
    private(set) var activeUsageDuration: TimeInterval = 0

    // MARK: - Thresholds

    let activeUsageMax: TimeInterval = 60.0
    private let inactivityThreshold: TimeInterval = 5.0
    private let timerInterval: TimeInterval = 0.5

    // MARK: - Private State

    private var sessionStartTime: Date?
    private var lastInteractionTime: Date?
    private var trackingTimer: Timer?

    // MARK: - Init / Deinit

    init() {
        subscribeToAppLifecycle()
        startTimer()
    }

    deinit { stopTimer() }

    // MARK: - Public API

    func recordUserInteraction() {
        let now = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastInteractionTime = now
            if !self.isActivelyUsing || self.sessionStartTime == nil {
                self.sessionStartTime = now
                self.isActivelyUsing  = true
            }
        }
    }

    // MARK: - App Lifecycle

    private func subscribeToAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.startTimer() }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopTimer()
            self?.isActivelyUsing     = false
            self?.sessionStartTime    = nil
            self?.activeUsageDuration = 0
        }
    }

    // MARK: - Timer

    private func startTimer() {
        guard trackingTimer == nil else { return }
        trackingTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func tick() {
        guard let lastInteraction = lastInteractionTime else { return }
        let now = Date()
        let sinceLastInteraction = now.timeIntervalSince(lastInteraction)
        if sinceLastInteraction >= inactivityThreshold {
            isActivelyUsing     = false
            sessionStartTime    = nil
            activeUsageDuration = 0
        } else if let start = sessionStartTime {
            activeUsageDuration = now.timeIntervalSince(start)
        }
    }
}
