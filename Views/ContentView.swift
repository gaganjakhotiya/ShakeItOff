// ContentView.swift
// ShakeItOff
//
// Main screen. Uses @Environment (the @Observable equivalent of @EnvironmentObject).
// Touch events are forwarded to screenInteractionTracker via simultaneousGesture.

import SwiftUI

struct ContentView: View {

    // MARK: - Environment

    @Environment(AppState.self)                 private var appState
    @Environment(ScreenInteractionTracker.self) private var tracker
    @Environment(VibrationManager.self)         private var vibManager
    @Environment(MotionManager.self)            private var motionMgr
    @Environment(BackgroundAudioManager.self)   private var bgAudio

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    appTitle

                    if vibManager.isVibrationPausedForSafety {
                        pauseBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    activateCard
                    strengthCard

                    Spacer(minLength: 32)
                    howItWorksCaption
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 40)
            }
            .animation(.easeInOut(duration: 0.3), value: vibManager.isVibrationPausedForSafety)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in tracker.recordUserInteraction() }
        )
    }

    // MARK: - Subviews

    private var appTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ShakeItOff")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Break the mindless pickup habit")
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.45))
        }
    }

    private var pauseBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Vibration paused")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("60 s of active use detected. Put the phone down for 5 s to resume.")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.yellow.opacity(0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
    }

    private var activateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activate")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text(appState.isActivated ? "Vibrating on pickup" : "Tap to enable")
                        .font(.caption)
                        .foregroundColor(appState.isActivated
                                         ? Color.green.opacity(0.85)
                                         : Color.white.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: activateBinding)
                    .labelsHidden()
                    .tint(.green)
            }
        }
        .padding(18)
        .background(cardBackground)
        .cornerRadius(14)
    }

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vibration Strength")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(appState.isActivated ? .white : Color.white.opacity(0.35))

            HStack(spacing: 10) {
                ForEach(["Low", "Mid", "High"], id: \.self) { label in
                    StrengthButton(
                        label:      label,
                        isSelected: appState.selectedStrength == label.lowercased(),
                        isEnabled:  appState.isActivated
                    ) {
                        appState.selectedStrength = label.lowercased()
                        tracker.recordUserInteraction()
                    }
                }
            }
        }
        .padding(18)
        .background(cardBackground)
        .cornerRadius(14)
    }

    private var howItWorksCaption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How it works")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(Color.white.opacity(0.4))
            Text(
                "When Activate is ON, picking up or moving the phone starts continuous vibrations. " +
                "They stop when the phone is still for 2+ seconds or the screen locks. " +
                "After 60 seconds of non-stop use, vibrations pause — put the phone down for 5 s to resume."
            )
            .font(.caption2)
            .foregroundColor(Color.white.opacity(0.3))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        Color.white.opacity(0.06)
    }

    /// Binding that wires the toggle to motion detection + background audio.
    private var activateBinding: Binding<Bool> {
        Binding(
            get: { appState.isActivated },
            set: { newValue in
                appState.isActivated = newValue
                if newValue {
                    bgAudio.start()                    // Keep process alive in background.
                    motionMgr.startMotionDetection()   // Start sensors + activity monitor.
                } else {
                    motionMgr.stopMotionDetection()    // Stops sensors + vibration.
                    vibManager.stopContinuousVibration()
                    vibManager.resumeVibrationIfReady()
                    bgAudio.stop()                     // Release audio session.
                }
            }
        )
    }
}

// MARK: - StrengthButton

private struct StrengthButton: View {
    let label:      String
    let isSelected: Bool
    let isEnabled:  Bool
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(background)
                .foregroundColor(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(borderColor, lineWidth: 1.5)
                )
        }
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
    }

    private var background: Color {
        isSelected && isEnabled ? .white : .clear
    }

    private var foregroundColor: Color {
        if !isEnabled { return Color.white.opacity(0.25) }
        return isSelected ? .black : .white
    }

    private var borderColor: Color {
        isEnabled ? .white : Color.white.opacity(0.2)
    }
}

// MARK: - Preview

#Preview {
    let appState  = AppState()
    let tracker   = ScreenInteractionTracker()
    let vibMgr    = VibrationManager(screenInteractionTracker: tracker)
    let motionMgr = MotionManager(
        vibrationManager:         vibMgr,
        screenInteractionTracker: tracker,
        appState:                 appState
    )
    ContentView()
        .environment(appState)
        .environment(tracker)
        .environment(vibMgr)
        .environment(motionMgr)
        .environment(BackgroundAudioManager())
}
