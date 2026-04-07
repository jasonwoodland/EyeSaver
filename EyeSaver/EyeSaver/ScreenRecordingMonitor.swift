//
//  ScreenRecordingMonitor.swift
//  EyeSaver
//
//  Created by Jason Woodland on 26/9/2025.
//

#if ENABLE_SCREEN_SHARING

import Cocoa
import Combine

// MARK: - Private API Bridge
// Using SkyLight/CGSInternal private API for screen recording detection
// This is the most reliable way to detect if the screen is being recorded
@_silgen_name("CGSIsScreenWatcherPresent")
func CGSIsScreenWatcherPresent() -> Bool

class ScreenRecordingMonitor: ObservableObject {
    @Published private(set) var isScreenRecording = false

    private var monitorTimer: Timer?
    weak var delegate: ScreenRecordingMonitorDelegate?

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        print("EyeSaver: Starting screen recording monitoring")

        // Check every second for screen recording state changes
        monitorTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkScreenRecordingState()
        }
        RunLoop.main.add(monitorTimer!, forMode: .common)

        // Initial check
        checkScreenRecordingState()
    }

    func stopMonitoring() {
        print("EyeSaver: Stopping screen recording monitoring")
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func checkScreenRecordingState() {
        let wasRecording = isScreenRecording

        // Use the SkyLight private API to detect if screen is being watched/recorded
        // This returns true when any app is recording or sharing the screen
        let isCurrentlyRecording = CGSIsScreenWatcherPresent()

        if isCurrentlyRecording != wasRecording {
            updateRecordingState(isRecording: isCurrentlyRecording)
        }
    }

    private func updateRecordingState(isRecording: Bool) {
        guard isRecording != self.isScreenRecording else { return }

        print("EyeSaver: Screen recording state changed to: \(isRecording)")

        self.isScreenRecording = isRecording

        if isRecording {
            delegate?.screenRecordingDidStart()
        } else {
            delegate?.screenRecordingDidStop()
        }
    }
}

// MARK: - Protocol for delegates
protocol ScreenRecordingMonitorDelegate: AnyObject {
    func screenRecordingDidStart()
    func screenRecordingDidStop()
}

// MARK: - Protocol conformance
extension ScreenRecordingMonitor {
    // Simplified interface - no need for factory pattern since we're using a single reliable API
}

#endif