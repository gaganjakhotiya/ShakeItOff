// ShakeItOffApp.swift
// ShakeItOff
//
// App entry point. AppCoordinator owns the full object graph and wires
// all dependencies before any view renders.
//
// All managers are injected via .environment() (the @Observable equivalent
// of .environmentObject()) so SwiftUI can observe @Observable-tracked reads
// anywhere in the view hierarchy.

import SwiftUI

// MARK: - AppCoordinator

/// Owns and wires the complete manager graph.
/// Does not need to be @Observable itself — views observe the individual managers.
final class AppCoordinator {

    let appState:              AppState
    let screenInteractionTracker: ScreenInteractionTracker
    let vibrationManager:      VibrationManager
    let motionManager:         MotionManager
    let backgroundTaskManager: BackgroundTaskManager

    init() {
        let state   = AppState()
        let tracker = ScreenInteractionTracker()
        let vibMgr  = VibrationManager(screenInteractionTracker: tracker)
        let motMgr  = MotionManager(
            vibrationManager:         vibMgr,
            screenInteractionTracker: tracker,
            appState:                 state
        )
        let bgMgr = BackgroundTaskManager(appState: state, motionManager: motMgr)

        self.appState                 = state
        self.screenInteractionTracker = tracker
        self.vibrationManager         = vibMgr
        self.motionManager            = motMgr
        self.backgroundTaskManager    = bgMgr

        // Auto-resume if the app was force-quit with Activate ON.
        if state.isActivated {
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
                .preferredColorScheme(.dark)
        }
    }
}
