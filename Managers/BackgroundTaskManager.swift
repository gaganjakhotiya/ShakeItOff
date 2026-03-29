// BackgroundTaskManager.swift
// ShakeItOff
//
// BGAppRefreshTask registration and scheduling.
// Task identifier must match BGTaskSchedulerPermittedIdentifiers in Info.plist.

import Foundation
import BackgroundTasks
import UIKit
import Observation

@Observable
final class BackgroundTaskManager {

    static let taskIdentifier = "com.shakeitoff.motion-refresh"
    private let refreshInterval: TimeInterval = 15 * 60

    private weak var appState:      AppState?
    private weak var motionManager: MotionManager?

    init(appState: AppState, motionManager: MotionManager) {
        self.appState      = appState
        self.motionManager = motionManager
        registerBackgroundTask()
        subscribeToAppLifecycle()
    }

    // MARK: - Registration

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleRefreshTask(refreshTask)
        }
    }

    // MARK: - Scheduling

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundTaskManager] Failed to schedule: \(error.localizedDescription)")
        }
    }

    // MARK: - Task Handling

    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()
        task.expirationHandler = { [weak self] in
            self?.motionManager?.stopMotionDetection()
            task.setTaskCompleted(success: false)
        }
        if appState?.isActivated == true {
            motionManager?.startMotionDetection()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.motionManager?.stopMotionDetection()
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - App Lifecycle

    private func subscribeToAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            if self?.appState?.isActivated == true {
                self?.scheduleAppRefresh()
            }
        }
    }
}
