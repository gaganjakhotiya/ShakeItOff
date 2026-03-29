// AppState.swift
// ShakeItOff
//
// Central state model. Persisted to UserDefaults so Activate state
// survives force-quits and relaunches.

import Foundation
import Observation

@Observable
final class AppState {

    private enum Keys {
        static let isActivated      = "ShakeItOff.isActivated"
        static let selectedStrength = "ShakeItOff.selectedStrength"
    }

    var isActivated: Bool {
        didSet { UserDefaults.standard.set(isActivated, forKey: Keys.isActivated) }
    }

    /// Valid values: "low" | "mid" | "high"
    var selectedStrength: String {
        didSet {
            guard ["low", "mid", "high"].contains(selectedStrength) else {
                selectedStrength = "mid"
                return
            }
            UserDefaults.standard.set(selectedStrength, forKey: Keys.selectedStrength)
        }
    }

    init() {
        self.isActivated      = UserDefaults.standard.bool(forKey: Keys.isActivated)
        let stored            = UserDefaults.standard.string(forKey: Keys.selectedStrength) ?? "mid"
        self.selectedStrength = ["low", "mid", "high"].contains(stored) ? stored : "mid"
    }
}
