// ShakeItOffApp.swift
// ShakeItOff

import SwiftUI
import UserNotifications

// MARK: - AppCoordinator

final class AppCoordinator {

    let appState:              AppState
    let screenInteractionTracker: ScreenInteractionTracker
    let vibrationManager:      VibrationManager
    let motionManager:         MotionManager
    let backgroundTaskManager: BackgroundTaskManager
    let backgroundAudio:       BackgroundAudioManager

    init() {
        let state   = AppState()
        let tracker = ScreenInteractionTracker()
        let vibMgr  = VibrationManager(screenInteractionTracker: tracker)
        let motMgr  = MotionManager(
            vibrationManager:         vibMgr,
            screenInteractionTracker: tracker,
            appState:                 state
        )
        let bgMgr   = BackgroundTaskManager(appState: state, motionManager: motMgr)
        let bgAudio = BackgroundAudioManager()

        self.appState                 = state
        self.screenInteractionTracker = tracker
        self.vibrationManager         = vibMgr
        self.motionManager            = motMgr
        self.backgroundTaskManager    = bgMgr
        self.backgroundAudio          = bgAudio

        // If Activate was ON when the app was last killed, resume everything.
        if state.isActivated {
            bgAudio.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                motMgr.startMotionDetection()
            }
        }
    }
}

// MARK: - App Entry Point

@main
struct ShakeItOffApp: App {

    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(coordinator.appState)
                .environment(coordinator.screenInteractionTracker)
                .environment(coordinator.vibrationManager)
                .environment(coordinator.motionManager)
                .environment(coordinator.backgroundAudio)
                .preferredColorScheme(.dark)
                .onAppear {
                    UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
                }
        }
    }
}
