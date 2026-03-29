// MotionManager.swift
// ShakeItOff
//
// Motion detection runs in THREE layers:
//
//   1. CMMotionManager @ 50 Hz  (foreground + background while process is alive)
//      Pickup threshold: 0.3 g userAcceleration magnitude.
//      Process stays alive because BackgroundAudioManager plays silent audio.
//      → Calls VibrationManager.startContinuousVibration() on first pickup.
//      → 2-second quiet timer stops vibration when motion ceases.
//
//   2. CMMotionActivityManager  (always-on, even if process is suspended)
//      Detects stationary → active transitions (phone picked up).
//      → Fires a local notification that buzzes the lock screen.
//      → Cooldown: 8 s between notifications to avoid spam.
//
//   3. didBecomeActiveNotification
//      Fires the instant the user unlocks the phone.
//      → Treats unlock as a pickup and starts vibration immediately,
//         before the user has finished swiping.
//
// KEY DESIGN: we NEVER stop CMMotionManager or VibrationManager when
// the app enters the background. VibrationManager handles the mode switch
// (CHHapticEngine → AudioServicesPlaySystemSound) internally.

import Foundation
import CoreMotion
import UserNotifications
import UIKit
import Observation

@Observable
final class MotionManager {

    // MARK: - Constants

    private let cmUpdateInterval: TimeInterval   = 1.0 / 50.0
    private let accelerationThreshold: Double    = 0.3
    private let motionQuietTimeout: TimeInterval = 2.0
    private let notificationCooldown: TimeInterval = 8.0

    // MARK: - Dependencies

    private weak var vibrationManager: VibrationManager?
    private weak var tracker:          ScreenInteractionTracker?
    private weak var appState:         AppState?

    // MARK: - CMMotionManager

    private let cmMotion = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.shakeitoff.motionQueue"
        q.qualityOfService = .userInteractive
        return q
    }()
    private var cmRunning  = false
    private var isInMotion = false
    private var quietTimer: Timer?

    // MARK: - CMMotionActivityManager

    private let activityManager    = CMMotionActivityManager()
    private var lastNotificationTime: Date?

    // MARK: - Init / Deinit

    init(
        vibrationManager: VibrationManager,
        screenInteractionTracker: ScreenInteractionTracker,
        appState: AppState
    ) {
        self.vibrationManager = vibrationManager
        self.tracker          = screenInteractionTracker
        self.appState         = appState
        requestNotificationPermission()
        subscribeToAppLifecycle()
    }

    deinit {
        cmMotion.stopDeviceMotionUpdates()
        activityManager.stopActivityUpdates()
        quietTimer?.invalidate()
    }

    // MARK: - Public API

    /// Call once when Activate is toggled ON (or on app launch if already ON).
    func startMotionDetection() {
        startCMMotion()
        startActivityMonitoring()
    }

    /// Call when Activate is toggled OFF.
    func stopMotionDetection() {
        stopCMMotion()
        activityManager.stopActivityUpdates()
        Task { @MainActor [weak self] in
            self?.isInMotion = false
            self?.vibrationManager?.stopContinuousVibration()
        }
    }

    // MARK: - CMMotionManager (foreground + background)

    private func startCMMotion() {
        guard !cmRunning, cmMotion.isDeviceMotionAvailable else { return }
        cmRunning = true
        cmMotion.deviceMotionUpdateInterval = cmUpdateInterval
        cmMotion.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            let a         = motion.userAcceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            guard magnitude >= self.accelerationThreshold else { return }
            Task { @MainActor [weak self] in self?.handlePickupDetected() }
        }
    }

    private func stopCMMotion() {
        guard cmRunning else { return }
        cmRunning = false
        cmMotion.stopDeviceMotionUpdates()
        cancelQuietTimer()
    }

    @MainActor
    private func handlePickupDetected() {
        tracker?.recordUserInteraction()
        cancelQuietTimer()
        scheduleQuietTimer()

        guard let strength = appState?.selectedStrength else { return }
        if !isInMotion {
            isInMotion = true
            vibrationManager?.startContinuousVibration(strength: strength)
        } else {
            vibrationManager?.updateStrength(strength)
        }
    }

    private func scheduleQuietTimer() {
        let t = Timer(timeInterval: motionQuietTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isInMotion = false
                self?.vibrationManager?.stopContinuousVibration()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        quietTimer = t
    }

    private func cancelQuietTimer() {
        quietTimer?.invalidate()
        quietTimer = nil
    }

    // MARK: - CMMotionActivityManager (lock-screen notifications)

    private func startActivityMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: OperationQueue()) { [weak self] activity in
            guard let activity, let self else { return }
            guard !activity.stationary else { return }
            guard self.appState?.isActivated == true else { return }

            let now = Date()
            let gap = self.lastNotificationTime.map { now.timeIntervalSince($0) } ?? .infinity
            guard gap >= self.notificationCooldown else { return }

            self.lastNotificationTime = now
            self.firePickupNotification()
        }
    }

    // MARK: - Lock-Screen Notification

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func firePickupNotification() {
        let content = UNMutableNotificationContent()
        content.title = "📵 Put it down."
        content.body  = "You just picked up your phone."
        content.sound = .defaultCritical   // Bypasses silent switch.

        let request = UNNotificationRequest(
            identifier: "shakeitoff.pickup.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - App Lifecycle

    private func subscribeToAppLifecycle() {
        // ── Unlock / app foregrounded ────────────────────────────────────────
        // Treat every unlock as an immediate pickup.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.appState?.isActivated == true else { return }
            self.startCMMotion()   // Restart sensor if it stopped.
            // Treat unlock as a pickup — start vibrating before user does anything.
            Task { @MainActor [weak self] in self?.handlePickupDetected() }
        }

        // ── Backgrounded ─────────────────────────────────────────────────────
        // DO NOT stop CMMotionManager or vibration here.
        // VibrationManager switches internally from CHHapticEngine to AudioServices.
        // BackgroundAudioManager keeps the process alive so CMMotionManager callbacks
        // and timers continue to fire.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Re-ensure CMMotion is running — it may have been stopped by a prior
            // willResignActive during a phone-call interruption.
            guard self?.appState?.isActivated == true else { return }
            self?.startCMMotion()
        }
    }
}
