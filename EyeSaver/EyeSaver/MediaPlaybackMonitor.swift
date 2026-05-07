//
//  MediaPlaybackMonitor.swift
//  EyeSaver
//
//  Created by Jason Woodland on 7/4/2026.
//

import Cocoa
import Combine
import IOKit.pwr_mgt
import os

private let log = Logger(subsystem: "com.jasonwoodland.EyeSaver", category: "media")

protocol MediaPlaybackMonitorDelegate: AnyObject {
    func mediaPlaybackDidChange(isPlaying: Bool, processName: String?)
}

class MediaPlaybackMonitor: ObservableObject {
    @Published private(set) var isMediaPlaying = false
    @Published private(set) var activeProcessName: String?

    private var monitorTimer: Timer?
    weak var delegate: MediaPlaybackMonitorDelegate?

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        log.notice("Starting media playback monitoring")
        monitorTimer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkMediaPlaybackState()
        }
        RunLoop.main.add(monitorTimer!, forMode: .common)
        checkMediaPlaybackState()
    }

    func stopMonitoring() {
        log.notice("Stopping media playback monitoring")
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func checkMediaPlaybackState() {
        var assertionsByProcess: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertionsByProcess)

        guard result == kIOReturnSuccess,
              let dict = assertionsByProcess?.takeRetainedValue() as NSDictionary? else {
            updateState(isPlaying: false, processName: nil)
            return
        }

        // Find processes holding PreventUserIdleDisplaySleep assertions
        var foundProcessName: String?

        for (pidKey, assertionsArray) in dict {
            guard let pid = pidKey as? Int,
                  let assertions = assertionsArray as? [[String: Any]] else { continue }

            for assertion in assertions {
                if let assertType = assertion["AssertType"] as? String,
                   assertType == "PreventUserIdleDisplaySleep" {
                    let processId = pid_t(pid)
                    if let app = NSRunningApplication(processIdentifier: processId) {
                        foundProcessName = app.localizedName ?? "Unknown"
                    }
                    break
                }
            }
            if foundProcessName != nil { break }
        }

        updateState(isPlaying: foundProcessName != nil, processName: foundProcessName)
    }

    private func updateState(isPlaying: Bool, processName: String?) {
        let wasPlaying = isMediaPlaying

        isMediaPlaying = isPlaying
        activeProcessName = processName

        if isPlaying != wasPlaying {
            log.notice("Media playback state changed: isPlaying=\(isPlaying, privacy: .public) process=\(processName ?? "none", privacy: .public)")
            delegate?.mediaPlaybackDidChange(isPlaying: isPlaying, processName: processName)
        }
    }
}
