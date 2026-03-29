# ShakeItOff — Agent Context

This file provides full technical context for AI coding agents (GitHub Copilot, Claude, etc.) working on this project. Read this before making any changes.

---

## What This App Does

ShakeItOff is an iOS app that vibrates continuously when the user picks up their phone while the app is "activated". The goal is to discourage mindless phone checking. Core flow:

1. User opens app → sets intensity → toggles **Activate ON**
2. User locks phone
3. User (or anyone) picks up the phone → immediate haptic feedback
4. Vibration continues until: **(motion stops AND phone is locked again)** OR **Activate is toggled OFF**
5. Lock-screen notification fires when pickup is detected with screen off

---

## Target Platform

- **Device**: iPhone 11 or newer
- **iOS**: 26 or newer
- **Xcode**: 26+
- **Language**: Swift, SwiftUI
- **State management**: `@Observable` macro (NOT `ObservableObject` — see critical constraint below)

---

## Project Layout

```
shakeitoff/
├── README.md
├── draft.txt                              # Original feature spec
└── ShakeItOff/
    └── ShakeItOff/                        # Xcode workspace
        ├── ShakeItOff.xcodeproj/
        │   └── project.pbxproj            # Manually maintained — see notes below
        ├── Info.plist                     # Custom plist (NOT auto-generated)
        ├── Managers/
        │   ├── BackgroundAudioManager.swift
        │   ├── BackgroundTaskManager.swift
        │   ├── MotionManager.swift
        │   ├── ScreenInteractionTracker.swift
        │   └── VibrationManager.swift
        ├── Models/
        │   └── AppState.swift
        ├── Views/
        │   └── ContentView.swift
        └── ShakeItOff/                    # Xcode target folder (PBXFileSystemSynchronizedRootGroup)
            ├── ShakeItOffApp.swift        # App entry point
            ├── Assets.xcassets/
            │   ├── AppIcon.appiconset/
            │   │   ├── AppIcon.png        # 1024×1024 universal icon
            │   │   └── Contents.json      # 3 entries: default, dark, tinted
            │   └── Contents.json
            └── NotificationIcon.png       # Bundled for UNNotificationAttachment
```

---

## Critical Technical Constraints

### 1. `@Observable` NOT `ObservableObject`

**Xcode 26 sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` globally.**  
This breaks `ObservableObject` protocol synthesis — the compiler cannot initialize `objectWillChange` before `super.init()`.

**Rule**: All observable classes MUST use the `@Observable` macro.

| Old pattern (BROKEN) | New pattern (CORRECT) |
|---|---|
| `class Foo: ObservableObject` | `@Observable class Foo` |
| `@Published var x = 0` | `var x = 0` (auto-tracked) |
| `@EnvironmentObject var foo: Foo` | `@Environment(Foo.self) var foo` |
| `.environmentObject(foo)` | `.environment(foo)` |
| `@ObservedObject var foo: Foo` | `@State var foo = Foo()` or passed via `@Environment` |

### 2. No `NSObject` on Observable Classes

`NSObject` + `@Observable` (or `ObservableObject`) causes the same init ordering error.  
**Rule**: Never inherit from `NSObject` in manager classes.  
**Corollary**: Use closure-based `NotificationCenter.addObserver(forName:object:queue:)` — NOT `@objc` selector methods.

### 3. `project.pbxproj` — Manually Maintained

The Xcode target folder (`ShakeItOff/ShakeItOff/ShakeItOff/`) uses `PBXFileSystemSynchronizedRootGroup` — files dropped there are **auto-detected by Xcode** without pbxproj edits.

Files **outside** the target folder (`Managers/`, `Models/`, `Views/`, `Info.plist`) are **manually registered** in `project.pbxproj` with explicit `PBXFileReference` and `PBXBuildFile` entries.

**When adding new files**:
- Inside `ShakeItOff/ShakeItOff/ShakeItOff/` → no pbxproj change needed
- Outside (Managers, Models, Views) → add `PBXFileReference` + `PBXBuildFile` + reference in `Sources` build phase

### 4. Info.plist — Custom, Not Auto-Generated

Build setting: `INFOPLIST_FILE = Info.plist`, `GENERATE_INFOPLIST_FILE` is REMOVED.  
**Never re-add `GENERATE_INFOPLIST_FILE = YES`** — it will override the custom plist.

Required Info.plist keys:
```xml
UIBackgroundModes: [audio, fetch, processing]
NSMotionUsageDescription: "..."
BGTaskSchedulerPermittedIdentifiers: ["com.shakeitoff.refresh"]
UIApplicationSceneManifest: { UIApplicationSupportsMultipleScenes: false }
```

---

## Architecture Overview

### AppCoordinator (in ShakeItOffApp.swift)

Plain class (NOT `@Observable`) owned as `@State` in the `App` struct.  
Instantiates and wires all managers. Injects into SwiftUI environment via `.environment(obj)`.

```swift
@State private var coordinator = AppCoordinator()

var body: some Scene {
    WindowGroup {
        ContentView()
            .environment(coordinator.appState)
            .environment(coordinator.motionManager)
            .environment(coordinator.vibrationManager)
            .environment(coordinator.bgAudio)
            // ...
    }
}
```

### AppState (Models/AppState.swift)

`@Observable`. Single source of truth. Persists to `UserDefaults`.

Key properties:
- `isActivated: Bool` — main toggle
- `vibrationLevel: VibrationLevel` — `.low` / `.medium` / `.high`

### MotionManager (Managers/MotionManager.swift)

`@Observable`. Core pickup detection engine.

- **CMMotionManager** at 50Hz — reads accelerometer/gyroscope to detect lift motion
- **CMMotionActivityManager** — system-level activity recognition for background pickup proxy
- **Never stops CMMotion when backgrounded** — only ensures it's running
- `didBecomeActiveNotification` → treats every app foreground as immediate pickup
- `handlePickupDetected()` — calls `VibrationManager.startContinuousVibration()`
- `firePickupNotification()` — fires `UNUserNotificationCenter` with `NotificationIcon.png` attachment
- 2-second quiet timer: if motion settles, marks pickup as ended

### VibrationManager (Managers/VibrationManager.swift)

`@Observable`. Dual-mode haptics.

| Mode | Mechanism | When active |
|---|---|---|
| Foreground | `CHHapticEngine` with `hapticContinuous` event | App in foreground |
| Background | `AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)` on a repeating `Timer` | App backgrounded |

Intensities:
- Low: CHHaptic intensity 0.3 / AudioServices every 2.0s
- Medium: CHHaptic intensity 0.65 / AudioServices every 1.0s
- High: CHHaptic intensity 1.0 / AudioServices every 0.5s

60-second safety cap: a 0.5s monitor timer stops vibration at 60s; resumes after 5s inactivity (tracked by `ScreenInteractionTracker`).

### BackgroundAudioManager (Managers/BackgroundAudioManager.swift)

`@Observable`. Keeps the app process alive in background.

- Uses `AVAudioEngine` with a silent source node (volume = 0, `.mixWithOthers`)
- Started when user toggles **Activate ON**
- Stopped when **Activate OFF**
- Without this, iOS suspends the process → CMMotionManager stops → no background vibration

### BackgroundTaskManager (Managers/BackgroundTaskManager.swift)

`@Observable`. Registers and handles `BGAppRefreshTaskRequest` with identifier `com.shakeitoff.refresh`.

### ScreenInteractionTracker (Managers/ScreenInteractionTracker.swift)

`@Observable`. Tracks active screen use duration.

- `isActivelyUsing: Bool` — true when screen is on and user is interacting
- 60s active-use → sets `isVibrationPausedForSafety = true` in VibrationManager
- 5s inactivity → clears pause flag, next pickup restarts vibration

---

## Background Execution Architecture

The key challenge: **haptics and most audio APIs are disabled by iOS when the screen is off**.

Solution chain:
1. `BackgroundAudioManager` plays silent audio → keeps process alive → `audio` background mode
2. `CMMotionManager` continues receiving device motion data while process is alive
3. When motion threshold crossed → `VibrationManager.startBackgroundPulse()` fires `AudioServicesPlaySystemSound`
4. `AudioServicesPlaySystemSound` CAN fire with screen on (even in background) but NOT with screen fully off
5. For screen-off pickups: `CMMotionActivityManager` detects stationary→walking/running transition → fires `UNUserNotificationCenter` local notification with critical sound

**Hard iOS limit**: When screen is completely off, no haptic or vibration API works. Only local notifications (with sound) can alert the user.

---

## Notification Setup

- Permission requested on app launch (`.onAppear` in root view)
- `UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge])`
- Pickup notification: title "📵 Put it down.", sound `.defaultCritical` (bypasses silent switch)
- Attachment: `NotificationIcon.png` from bundle → copied to temp dir → `UNNotificationAttachment`
- Identifier: `"shakeitoff.pickup.<timestamp>"` (unique per notification, no deduplication)

---

## Frameworks Used

| Framework | Purpose |
|---|---|
| CoreMotion | CMMotionManager (accelerometer), CMMotionActivityManager (activity) |
| CoreHaptics | CHHapticEngine for foreground continuous vibration |
| AVFoundation | AVAudioEngine silent loop for background keepalive |
| BackgroundTasks | BGAppRefreshTask registration |
| UserNotifications | Local notifications for screen-off pickup alerts |
| AudioToolbox | AudioServicesPlaySystemSound for background vibration |

All are linked in `project.pbxproj`. CoreHaptics and AudioToolbox are system-linked; AVFoundation, CoreMotion, BackgroundTasks have explicit entries.

---

## Common Pitfalls to Avoid

1. **Do NOT use `ObservableObject`** — it breaks with Xcode 26's `MainActor` isolation
2. **Do NOT stop CMMotionManager on background entry** — it kills pickup detection
3. **Do NOT stop BackgroundAudioManager on background entry** — it lets the process die
4. **Do NOT use `Timer.scheduledTimer` without `.common` run loop mode** — timers won't fire in background
5. **Do NOT add `GENERATE_INFOPLIST_FILE = YES`** — it overrides the custom Info.plist
6. **Do NOT use `@objc` selectors in manager classes** — they inherit nothing from NSObject
7. **Do NOT expect CHHapticEngine to work in background** — iOS disables it; use AudioServices instead
8. **Do NOT expect AudioServices to fire with screen fully off** — use UNNotification instead

---

## Device Testing Notes

- Simulator does NOT support motion detection — always test on a physical device
- Enable Developer Mode: **Settings → Privacy & Security → Developer Mode**
- Trust certificate: **Settings → General → VPN & Device Management**
- Background vibration requires the app to have been opened at least once after activation
- Test sequence: activate → lock phone → set down for 5s → pick up → should buzz

---

## Distribution

- **TestFlight**: Product → Archive → Distribute → TestFlight Internal Testing
- **App Store**: Requires app metadata, screenshots, privacy details in App Store Connect
- **Ad Hoc**: Register device UDID in Developer account → build with provisioned profile
