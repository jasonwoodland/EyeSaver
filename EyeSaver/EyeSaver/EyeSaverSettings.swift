//
//  EyeSaverSettings.swift
//  EyeSaver
//
//  Created by Jason Woodland on 4/9/2025.
//

import SwiftUI
import Combine
import ServiceManagement

class EyeSaverSettings: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "EyeSaver.enabled") }
    }

    @Published var intervalBetweenShows: TimeInterval {
        didSet { UserDefaults.standard.set(intervalBetweenShows, forKey: "EyeSaver.intervalBetweenShows") }
    }

    @Published var displayDuration: TimeInterval {
        didSet { UserDefaults.standard.set(displayDuration, forKey: "EyeSaver.displayDuration") }
    }

    @Published var fadeInDuration: TimeInterval {
        didSet { UserDefaults.standard.set(fadeInDuration, forKey: "EyeSaver.fadeInDuration") }
    }

    @Published var fadeOutDuration: TimeInterval {
        didSet { UserDefaults.standard.set(fadeOutDuration, forKey: "EyeSaver.fadeOutDuration") }
    }

    @Published var overlayOpacity: Double {
        didSet { UserDefaults.standard.set(overlayOpacity, forKey: "EyeSaver.overlayOpacity") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "EyeSaver.launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    @Published var disableWhileScreenSharing: Bool {
        didSet { UserDefaults.standard.set(disableWhileScreenSharing, forKey: "EyeSaver.disableWhileScreenSharing") }
    }

    @Published var showInMenubar: Bool {
        didSet { UserDefaults.standard.set(showInMenubar, forKey: "EyeSaver.showInMenubar") }
    }

    weak var appDelegate: AppDelegate?

    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "EyeSaver.enabled") as? Bool ?? true

        let intervalValue = UserDefaults.standard.double(forKey: "EyeSaver.intervalBetweenShows")
        self.intervalBetweenShows = intervalValue > 0 ? intervalValue : 300.0

        let durationValue = UserDefaults.standard.double(forKey: "EyeSaver.displayDuration")
        self.displayDuration = durationValue > 0 ? durationValue : 20.0

        let fadeInValue = UserDefaults.standard.double(forKey: "EyeSaver.fadeInDuration")
        self.fadeInDuration = fadeInValue > 0 ? fadeInValue : 2.0

        let fadeOutValue = UserDefaults.standard.double(forKey: "EyeSaver.fadeOutDuration")
        self.fadeOutDuration = fadeOutValue > 0 ? fadeOutValue : 2.0

        let opacityValue = UserDefaults.standard.double(forKey: "EyeSaver.overlayOpacity")
        self.overlayOpacity = opacityValue > 0 ? opacityValue : 0.66

        self.launchAtLogin = UserDefaults.standard.object(forKey: "EyeSaver.launchAtLogin") as? Bool ?? false

        self.disableWhileScreenSharing = UserDefaults.standard.object(forKey: "EyeSaver.disableWhileScreenSharing") as? Bool ?? false

        self.showInMenubar = UserDefaults.standard.object(forKey: "EyeSaver.showInMenubar") as? Bool ?? true
    }

    func startOpacityPreview() {
        appDelegate?.startOpacityPreview()
    }

    func endOpacityPreview() {
        appDelegate?.endOpacityPreview()
    }

    private func updateLaunchAtLogin() {
        if launchAtLogin {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("Failed to enable launch at login: \(error)")
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                print("Failed to disable launch at login: \(error)")
            }
        }
    }

    func isScreenSharingActive() -> Bool {
        let windowList = CGWindowListCopyWindowInfo(.excludeDesktopElements, kCGNullWindowID) as? [[String: Any]] ?? []

        for window in windowList {
            if let owner = window[kCGWindowOwnerName as String] as? String,
               let windowName = window[kCGWindowName as String] as? String {
                if owner.contains("ScreenSearch") || owner.contains("screensharing") ||
                   windowName.contains("Screen Sharing") || owner.contains("zoom") ||
                   owner.contains("Zoom") || owner.contains("Discord") ||
                   owner.contains("Skype") || owner.contains("Microsoft Teams") {
                    return true
                }
            }
        }
        return false
    }
}