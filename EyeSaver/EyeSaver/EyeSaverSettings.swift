//
//  EyeSaverSettings.swift
//  EyeSaver
//
//  Created by Jason Woodland on 4/9/2025.
//

import SwiftUI
import Combine
import ServiceManagement
import os

private let log = Logger(subsystem: "com.jasonwoodland.EyeSaver", category: "settings")

class EyeSaverSettings: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "EyeSaver.enabled") }
    }

    @Published var intervalBetweenShows: TimeInterval {
        didSet {
            UserDefaults.standard.set(intervalBetweenShows, forKey: "EyeSaver.intervalBetweenShows")
            // Clamp idle timeout to not exceed interval
            if idleTimeout > intervalBetweenShows {
                idleTimeout = intervalBetweenShows
            }
        }
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

    #if ENABLE_SCREEN_SHARING
    @Published var disableWhileScreenSharing: Bool {
        didSet {
            UserDefaults.standard.set(disableWhileScreenSharing, forKey: "EyeSaver.disableWhileScreenSharing")
            updateScreenRecordingMonitoring()
        }
    }
    #endif

    @Published var disableWhileMediaPlaying: Bool {
        didSet {
            UserDefaults.standard.set(disableWhileMediaPlaying, forKey: "EyeSaver.disableWhileMediaPlaying")
            updateMediaPlaybackMonitoring()
        }
    }

    @Published var idleTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(idleTimeout, forKey: "EyeSaver.idleTimeout") }
    }

    @Published var showInMenubar: Bool {
        didSet { UserDefaults.standard.set(showInMenubar, forKey: "EyeSaver.showInMenubar") }
    }

    #if ENABLE_SCREEN_SHARING
    @Published private(set) var isScreenRecording = false
    #endif
    @Published private(set) var isMediaPlaying = false
    @Published private(set) var mediaPlaybackProcessName: String?

    weak var appDelegate: AppDelegate? {
        didSet {
            #if ENABLE_SCREEN_SHARING
            screenRecordingMonitor?.delegate = appDelegate
            #endif
            mediaPlaybackMonitor?.delegate = appDelegate
        }
    }
    #if ENABLE_SCREEN_SHARING
    private var screenRecordingMonitor: ScreenRecordingMonitor?
    private var screenRecordingCancellable: AnyCancellable?
    #endif
    private var mediaPlaybackMonitor: MediaPlaybackMonitor?
    private var mediaPlaybackCancellables = Set<AnyCancellable>()

    init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "EyeSaver.enabled") as? Bool ?? true

        let intervalValue = UserDefaults.standard.double(forKey: "EyeSaver.intervalBetweenShows")
        self.intervalBetweenShows = intervalValue > 0 ? intervalValue : 1200.0  // 20 minutes

        let durationValue = UserDefaults.standard.double(forKey: "EyeSaver.displayDuration")
        self.displayDuration = durationValue > 0 ? durationValue : 20.0  // 20 seconds

        let fadeValue = UserDefaults.standard.double(forKey: "EyeSaver.fadeDuration")
        self.fadeDuration = fadeValue > 0 ? fadeValue : 2.5  // 2.5 seconds

        let opacityValue = UserDefaults.standard.double(forKey: "EyeSaver.overlayOpacity")
        self.overlayOpacity = opacityValue > 0 ? opacityValue : 0.5  // 50% opacity

        self.launchAtLogin = UserDefaults.standard.object(forKey: "EyeSaver.launchAtLogin") as? Bool ?? false

        #if ENABLE_SCREEN_SHARING
        self.disableWhileScreenSharing = UserDefaults.standard.object(forKey: "EyeSaver.disableWhileScreenSharing") as? Bool ?? false
        #endif

        self.disableWhileMediaPlaying = UserDefaults.standard.object(forKey: "EyeSaver.disableWhileMediaPlaying") as? Bool ?? false

        let idleValue = UserDefaults.standard.object(forKey: "EyeSaver.idleTimeout") as? Double
        self.idleTimeout = idleValue ?? 60.0

        self.showInMenubar = UserDefaults.standard.object(forKey: "EyeSaver.showInMenubar") as? Bool ?? true

        #if ENABLE_SCREEN_SHARING
        setupScreenRecordingMonitoring()
        #endif
        setupMediaPlaybackMonitoring()
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
                log.error("Failed to enable launch at login: \(String(describing: error), privacy: .public)")
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                log.error("Failed to disable launch at login: \(String(describing: error), privacy: .public)")
            }
        }
    }

    #if ENABLE_SCREEN_SHARING
    func isScreenSharingActive() -> Bool {
        return isScreenRecording
    }

    private func setupScreenRecordingMonitoring() {
        guard disableWhileScreenSharing else { return }

        let monitor = ScreenRecordingMonitor()
        monitor.delegate = appDelegate
        screenRecordingMonitor = monitor

        screenRecordingCancellable = monitor.$isScreenRecording
            .assign(to: \.isScreenRecording, on: self)

        monitor.startMonitoring()
        isScreenRecording = monitor.isScreenRecording
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
        screenRecordingCancellable = nil
        isScreenRecording = false
    }
    #endif

    private func setupMediaPlaybackMonitoring() {
        guard disableWhileMediaPlaying else { return }

        let monitor = MediaPlaybackMonitor()
        monitor.delegate = appDelegate
        mediaPlaybackMonitor = monitor

        monitor.$isMediaPlaying
            .assign(to: \.isMediaPlaying, on: self)
            .store(in: &mediaPlaybackCancellables)

        monitor.$activeProcessName
            .assign(to: \.mediaPlaybackProcessName, on: self)
            .store(in: &mediaPlaybackCancellables)

        monitor.startMonitoring()
        isMediaPlaying = monitor.isMediaPlaying
        mediaPlaybackProcessName = monitor.activeProcessName
    }

    private func updateMediaPlaybackMonitoring() {
        if disableWhileMediaPlaying {
            setupMediaPlaybackMonitoring()
        } else {
            stopMediaPlaybackMonitoring()
        }
    }

    private func stopMediaPlaybackMonitoring() {
        mediaPlaybackMonitor?.stopMonitoring()
        mediaPlaybackMonitor = nil
        mediaPlaybackCancellables.removeAll()
        isMediaPlaying = false
        mediaPlaybackProcessName = nil
    }
}