# ShakeItOff 📵

**Put your phone down.** ShakeItOff vibrates every time you pick up your phone while it's activated — a simple, physical reminder to break the mindless-scrolling habit.

---

## Screenshot

<img width="450" height="1050" alt="image" src="https://github.com/user-attachments/assets/7a95a80b-3840-4e41-bc37-15599963fd66" />


---

## Features

- **Activation toggle** — arm the app, lock your phone, walk away
- **Pickup detection** — detects when you lift the phone using the accelerometer
- **Continuous haptic feedback** — vibrates the moment pickup is detected, stops when you put it back down and lock again
- **Three intensity levels** — Low / Medium / High haptic strength
- **Works in background** — keeps running while you use other apps or the screen is locked
- **Lock-screen notification** — fires a "Put it down." alert when pickup is detected while screen is off
- **60-second safety cap** — pauses vibration after 60s of active screen use to avoid annoyance; resumes automatically after 5s of inactivity

---

## Requirements

| Requirement | Version |
|---|---|
| iPhone | 11 or newer |
| iOS | 26 or newer |
| Xcode | 26+ (for building from source) |
| Apple Developer account | Required for device installation |

---

## Building & Installing

### First-time setup

1. **Clone the repo**
   ```
   git clone <your-repo-url>
   cd shakeitoff
   ```

2. **Open the project in Xcode**
   ```
   open ./ShakeItOff.xcodeproj
   ```

3. **Set your Team**
   - Select the `ShakeItOff` target → **Signing & Capabilities**
   - Set **Team** to your Apple Developer account

4. **Connect your iPhone** and select it as the build destination

5. **Build & Run** — `⌘R`

### First install on device

- Go to **Settings → Privacy & Security → Developer Mode** → enable it
- After install, go to **Settings → General → VPN & Device Management** → trust your developer certificate

### Granting permissions

On first launch, allow:
- **Motion & Fitness** — required for pickup detection
- **Notifications** — required for lock-screen pickup alerts

---

## How to Use

1. Open ShakeItOff
2. Select your vibration intensity (Low / Medium / High)
3. Toggle **Activate** to ON
4. Lock your phone and set it down
5. When you (or anyone else) picks it up — it buzzes

To stop: open the app and toggle **Activate** to OFF.

---

## Distribution

### Share via TestFlight (recommended)
1. In Xcode: **Product → Archive**
2. **Distribute App → TestFlight Internal Testing**
3. Invite testers by email in [App Store Connect](https://appstoreconnect.apple.com)

### Publish to App Store
1. **Product → Archive → Distribute App → App Store Connect**
2. Complete metadata and screenshots in App Store Connect
3. Submit for App Review (~24–48 hours)

---

## Project Structure

```
├── ShakeItOff/                        # Xcode workspace root
│   ├── ShakeItOff.xcodeproj
│   ├── Info.plist
│   ├── Managers/
│   │   ├── MotionManager.swift        # Pickup detection (CMMotionManager + CMMotionActivityManager)
│   │   ├── VibrationManager.swift     # Haptics (CHHapticEngine foreground / AudioServices background)
│   │   ├── BackgroundAudioManager.swift  # Silent audio keeps process alive in background
│   │   ├── BackgroundTaskManager.swift   # BGAppRefreshTask registration
│   │   └── ScreenInteractionTracker.swift  # 60s cap / 5s resume logic
│   ├── Models/
│   │   └── AppState.swift             # @Observable shared state, UserDefaults persistence
│   ├── Views/
│   │   └── ContentView.swift          # Main SwiftUI UI
│   └── ShakeItOff/                    # Xcode target folder (auto-synced)
│       ├── ShakeItOffApp.swift        # App entry point, environment wiring
│       ├── Assets.xcassets/
│       │   └── AppIcon.appiconset/    # 1024×1024 app icon
│       └── NotificationIcon.png       # Icon shown in pickup notifications
```

---

## Known iOS Limitations

- **Screen fully off + silent**: haptics cannot fire (iOS restriction). A lock-screen notification is sent instead.
- **App terminated by user**: background detection stops. Re-open the app and re-activate.
- **Background task timing**: iOS schedules background refresh at its discretion; not guaranteed to be instant.

---

## License

Private / personal use. Not yet published on the App Store.
