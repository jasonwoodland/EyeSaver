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

    @Published var fadeDuration: TimeInterval {
        didSet { UserDefaults.standard.set(fadeDuration, forKey: "EyeSaver.fadeDuration") }
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
        didSet {
            UserDefaults.standard.set(disableWhileScreenSharing, forKey: "EyeSaver.disableWhileScreenSharing")
            updateScreenRecordingMonitoring()
        }
    }

    @Published var showInMenubar: Bool {
        didSet { UserDefaults.standard.set(showInMenubar, forKey: "EyeSaver.showInMenubar") }
    }

    @Published private(set) var isScreenRecording = false

    weak var appDelegate: AppDelegate?
    private var screenRecordingMonitor: ScreenRecordingMonitor?
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "EyeSaver.enabled") as? Bool ?? true

        let intervalValue = UserDefaults.standard.double(forKey: "EyeSaver.intervalBetweenShows")
        self.intervalBetweenShows = intervalValue > 0 ? intervalValue : 300.0

        let durationValue = UserDefaults.standard.double(forKey: "EyeSaver.displayDuration")
        self.displayDuration = durationValue > 0 ? durationValue : 20.0

        let fadeValue = UserDefaults.standard.double(forKey: "EyeSaver.fadeDuration")
        self.fadeDuration = fadeValue > 0 ? fadeValue : 2.0

        let opacityValue = UserDefaults.standard.double(forKey: "EyeSaver.overlayOpacity")
        self.overlayOpacity = opacityValue > 0 ? opacityValue : 0.66

        self.launchAtLogin = UserDefaults.standard.object(forKey: "EyeSaver.launchAtLogin") as? Bool ?? false

        self.disableWhileScreenSharing = UserDefaults.standard.object(forKey: "EyeSaver.disableWhileScreenSharing") as? Bool ?? false

        self.showInMenubar = UserDefaults.standard.object(forKey: "EyeSaver.showInMenubar") as? Bool ?? true

        setupScreenRecordingMonitoring()
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
        return isScreenRecording
    }

    private func setupScreenRecordingMonitoring() {
        guard disableWhileScreenSharing else { return }

        let monitor = ScreenRecordingMonitor()
        monitor.delegate = appDelegate
        screenRecordingMonitor = monitor

        // Subscribe to recording state changes
        monitor.$isScreenRecording
            .receive(on: DispatchQueue.main)
            .assign(to: \.isScreenRecording, on: self)
            .store(in: &cancellables)

        monitor.startMonitoring()
    }

    private func updateScreenRecordingMonitoring() {
        if disableWhileScreenSharing {
            setupScreenRecordingMonitoring()
        } else {
            stopScreenRecordingMonitoring()
        }
    }

    private func stopScreenRecordingMonitoring() {
        screenRecordingMonitor?.stopMonitoring()
        screenRecordingMonitor = nil
        cancellables.removeAll()
        isScreenRecording = false
    }
}