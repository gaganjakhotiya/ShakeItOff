// MotionManager.swift
// ShakeItOff
//
// Wraps CMMotionManager to detect phone pickups.
// Polls at 50 Hz; fires haptics when userAcceleration magnitude >= 0.3 g.
//
// With SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, the motion callback
// (delivered on a background OperationQueue) uses Task { @MainActor in }
// to safely cross back to the main actor for all state mutations.

import Foundation
import CoreMotion
import UIKit
import Observation

@Observable
final class MotionManager {

    // MARK: - Constants

    private let updateInterval: TimeInterval = 1.0 / 50.0
    /// 0.3 g filters minor shifts while catching deliberate pickups.
    private let accelerationThreshold: Double = 0.3

    // MARK: - Dependencies (weak to avoid retain cycles)

    private weak var vibrationManager: VibrationManager?
    private weak var tracker: ScreenInteractionTracker?
    private weak var appState: AppState?

    // MARK: - Private State

    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.shakeitoff.motionQueue"
        q.qualityOfService = .userInteractive
        return q
    }()
    private var isRunning = false

    // MARK: - Init / Deinit

    init(
        vibrationManager: VibrationManager,
        screenInteractionTracker: ScreenInteractionTracker,
        appState: AppState
    ) {
        self.vibrationManager = vibrationManager
        self.tracker          = screenInteractionTracker
        self.appState         = appState
        subscribeToAppLifecycle()
    }

    deinit { stopMotionDetection() }

    // MARK: - Public API

    func startMotionDetection() {
        guard !isRunning, motionManager.isDeviceMotionAvailable else { return }
        isRunning = true
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            let a         = motion.userAcceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            guard magnitude >= self.accelerationThreshold else { return }
            // Hop to main actor for all @Observable / UIKit work.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tracker?.recordUserInteraction()
                if let strength = self.appState?.selectedStrength {
                    self.vibrationManager?.triggerVibrationIfAllowed(strength: strength)
                }
            }
        }
    }

    func stopMotionDetection() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - App Lifecycle

    private func subscribeToAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard self?.appState?.isActivated == true else { return }
            self?.startMotionDetection()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Best-effort background behavior: keep motion updates running while activated.
            guard self?.appState?.isActivated == true else {
                self?.stopMotionDetection()
                return
            }
            self?.startMotionDetection()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard self?.appState?.isActivated == true else {
                self?.stopMotionDetection()
                return
            }
            self?.startMotionDetection()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard self?.appState?.isActivated == true else { return }
            self?.startMotionDetection()
        }
    }
}
