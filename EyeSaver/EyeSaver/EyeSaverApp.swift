//
//  EyeSaverApp.swift
//  EyeSaver
//
//  Created by Jason Woodland on 4/9/2025.
//

import Cocoa
import SwiftUI
import CoreGraphics
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ScreenRecordingMonitorDelegate {

    private var overlayWindows: [NSWindow] = []
    private var fadeOutTimer: Timer?
    private var intervalTimer: Timer?
    private var statusItem: NSStatusItem?
    private var isPreviewingOpacity = false
    private var settings: EyeSaverSettings!
    private var cancellables = Set<AnyCancellable>()
    private var preferencesWindow: NSWindow?
    private var intervalStartTime: Date?
    private var countdownUpdateTimer: Timer?
    private var countdownMenuItem: NSMenuItem?
    private var isBreakActive = false
    private var breakStartTime: Date?
    private var statusItemMenu: NSMenu?
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Activation policy will be set after settings are loaded
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = EyeSaverSettings()
        settings.appDelegate = self

        // Set activation policy based on menubar visibility
        updateActivationPolicy()

        print("EyeSaver: Application launched")
        print("EyeSaver: Interval between shows: \(settings.intervalBetweenShows) seconds")
        print("EyeSaver: Display duration: \(settings.displayDuration) seconds")

        setupStatusItem()
        createOverlayWindows()
        setupSettingsObservers()
        setupSystemEventObservers()

        if settings.isEnabled {
            startIntervalTimer()
        }
    }
    
    private func createOverlayWindows() {
        print("Creating overlay windows")
        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            
            window.backgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: settings.overlayOpacity)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .ignoresCycle
            ]
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.hasShadow = false
            window.alphaValue = 0.0
            window.orderFrontRegardless()
            
            overlayWindows.append(window)
            
            print("Created overlay window for screen: \(screen.localizedName)")
            print("  Screen frame: \(screen.frame)")
            print("  Window frame: \(window.frame)")
        }
        
        print("Total overlay windows created: \(overlayWindows.count)")
    }

    private func setupStatusItem() {
        if settings.showInMenubar {
            showStatusItem()
        } else {
            hideStatusItem()
        }
    }

    private func showStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            setupSwiftUIMenu()
        }
        updateStatusItemIcon()
    }

    private func updateStatusItemIcon() {
        if let button = statusItem?.button {
            let isEffectivelyEnabled = settings.isEnabled && !(settings.disableWhileScreenSharing && settings.isScreenSharingActive())
            let iconName = isEffectivelyEnabled ? "EyeOpen" : "EyeClosed"
            button.image = NSImage(named: iconName)
            button.image?.isTemplate = true
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown {
            // Right-click: toggle enabled
            settings.isEnabled.toggle()
        } else {
            // Left-click: show menu by temporarily attaching it to the status item
            statusItem?.menu = statusItemMenu
            statusItem?.button?.performClick(nil)
            // Menu will be detached in NSMenuDelegate's menuDidClose
        }
    }

    private func hideStatusItem() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func updateActivationPolicy() {
        let wasVisible = preferencesWindow?.isVisible ?? false

        if settings.showInMenubar {
            // Show in menubar: use accessory mode (doesn't appear in Cmd+Tab or Dock)
            NSApp.setActivationPolicy(.accessory)
        } else {
            // Hidden from menubar: use prohibited mode (appears in Cmd+Tab but not Dock)
            NSApp.setActivationPolicy(.prohibited)
        }

        // If preferences window was visible, ensure it stays accessible
        if wasVisible, let prefsWindow = preferencesWindow {
            DispatchQueue.main.async {
                prefsWindow.level = .floating // Temporarily raise window level
                prefsWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)

                // Reset to normal level after a moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    prefsWindow.level = .normal
                }
            }
        }
    }

    private func setupSwiftUIMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Enable/Disable toggle
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.tag = 1  // Tag for identifying this item
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        // Dismiss Break option (only visible during breaks)
        let dismissBreakItem = NSMenuItem(title: "Dismiss Break", action: #selector(dismissBreak), keyEquivalent: "d")
        dismissBreakItem.target = self
        dismissBreakItem.tag = 2  // Tag for identifying this item
        dismissBreakItem.isHidden = !isBreakActive
        menu.addItem(dismissBreakItem)

        // Countdown display with fixed-width font
        countdownMenuItem = NSMenuItem(title: "Next break in: --:--", action: nil, keyEquivalent: "")
        countdownMenuItem?.isEnabled = false

        // Use monospaced font for fixed width
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        let attributedTitle = NSAttributedString(string: "Next break in: --:--", attributes: attributes)
        countdownMenuItem?.attributedTitle = attributedTitle

        menu.addItem(countdownMenuItem!)

        menu.addItem(NSMenuItem.separator())

        // Preferences option
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        // Quit option
        let quitItem = NSMenuItem(title: "Quit EyeSaver", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Handle clicks manually instead of attaching menu
        if let button = statusItem?.button {
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }

        // Store menu for manual display
        self.statusItemMenu = menu
    }

    private func refreshMenuItems() {
        guard let menu = statusItemMenu else { return }

        // Update the enabled menu item state and dismiss break visibility
        for item in menu.items {
            if item.tag == 1 {  // Enabled item
                item.state = settings.isEnabled ? .on : .off
            } else if item.tag == 2 {  // Dismiss Break item
                item.isHidden = !isBreakActive
            }
        }

        // Update the icon
        updateStatusItemIcon()

        // Update countdown display
        updateCountdown()
    }

    @objc private func showPreferences() {
        if let existingWindow = preferencesWindow {
            // Window exists, always bring it to front and focus
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window or show existing hidden window
        if preferencesWindow == nil {
            let contentView = PreferencesWindow(settings: settings)
            let hostingController = NSHostingController(rootView: contentView)

            preferencesWindow = NSWindow(contentViewController: hostingController)
            preferencesWindow?.title = "EyeSaver Preferences"
            preferencesWindow?.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            preferencesWindow?.titlebarAppearsTransparent = true

            // Enable sidebar tracking separator for Tahoe design
            let toolbar = NSToolbar(identifier: "PreferencesToolbar")
            toolbar.displayMode = .iconOnly
            preferencesWindow?.toolbar = toolbar
            preferencesWindow?.toolbarStyle = .unified

            preferencesWindow?.isReleasedWhenClosed = false
            preferencesWindow?.center()
            preferencesWindow?.setFrameAutosaveName("PreferencesWindow")

            // Ensure standard window commands work (Cmd+W, etc.)
            preferencesWindow?.standardWindowButton(.closeButton)?.keyEquivalent = "w"
            preferencesWindow?.standardWindowButton(.closeButton)?.keyEquivalentModifierMask = .command
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        refreshMenuItems()
    }

    @objc private func dismissBreak() {
        dismissBreakEarly()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func setupSettingsObservers() {
        settings.$isEnabled
            .sink { [weak self] isEnabled in
                if isEnabled {
                    self?.startIntervalTimer()
                } else {
                    self?.stopIntervalTimer()
                    // End any active break immediately
                    if self?.isBreakActive == true {
                        self?.dismissBreakEarly()
                    }
                }

                // Update menubar item state and icon when setting changes
                DispatchQueue.main.async {
                    self?.refreshMenuItems()
                }
            }
            .store(in: &cancellables)

        settings.$overlayOpacity
            .sink { [weak self] _ in
                self?.updateOverlayOpacity()
            }
            .store(in: &cancellables)

        settings.$intervalBetweenShows
            .sink { [weak self] _ in
                self?.restartTimer()
            }
            .store(in: &cancellables)

        settings.$showInMenubar
            .sink { [weak self] showInMenubar in
                if showInMenubar {
                    self?.showStatusItem()
                } else {
                    self?.hideStatusItem()
                }
                self?.updateActivationPolicy()

            }
            .store(in: &cancellables)

        settings.$isScreenRecording
            .sink { [weak self] _ in
                // Update UI when screen recording state changes
                DispatchQueue.main.async {
                    self?.refreshMenuItems()
                }
            }
            .store(in: &cancellables)
    }


    private func updateOverlayOpacity() {
        for window in overlayWindows {
            window.backgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: settings.overlayOpacity)
        }
    }

    func startOpacityPreview() {
        isPreviewingOpacity = true
        print("EyeSaver: Starting opacity preview")

        // Make sure windows are visible and on top
        for window in overlayWindows {
            window.orderFrontRegardless()
            window.alphaValue = 1.0
        }
    }

    func endOpacityPreview() {
        guard isPreviewingOpacity else {
            print("EyeSaver: endOpacityPreview called but not previewing")
            return
        }

        print("EyeSaver: Actually ending opacity preview")
        isPreviewingOpacity = false

        // Fade out the preview
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            for window in overlayWindows {
                print("EyeSaver: Fading out window alpha from \(window.alphaValue) to 0.0")
                window.animator().alphaValue = 0.0
            }
        }, completionHandler: {
            print("EyeSaver: Fade out animation completed")
        })
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Start updating countdown while menu is open
        countdownUpdateTimer?.invalidate()
        countdownUpdateTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
        RunLoop.main.add(countdownUpdateTimer!, forMode: .common)
        updateCountdown() // Update immediately
    }

    func menuDidClose(_ menu: NSMenu) {
        print("EyeSaver: Menu closed, ending opacity preview")
        NotificationCenter.default.post(name: .menuDidClose, object: nil)
        if isPreviewingOpacity {
            endOpacityPreview()
        }

        // Stop countdown updates when menu closes
        countdownUpdateTimer?.invalidate()
        countdownUpdateTimer = nil

        // Detach menu from status item to restore custom click handling
        statusItem?.menu = nil
    }

    private func stopIntervalTimer() {
        intervalTimer?.invalidate()
        intervalTimer = nil
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        isPreviewingOpacity = false
    }

    private func restartTimer() {
        if settings.isEnabled {
            stopIntervalTimer()
            startIntervalTimer()
        }
    }

    private func startIntervalTimer() {
        print("EyeSaver: Starting interval timer")
        intervalStartTime = Date()
        intervalTimer = Timer.scheduledTimer(withTimeInterval: settings.intervalBetweenShows, repeats: false) { [weak self] _ in
            self?.showOverlays()
        }
    }

    private func showOverlays() {
        guard settings.isEnabled && !isPreviewingOpacity else { return }

        // Check if we should disable during screen sharing
        if settings.disableWhileScreenSharing && settings.isScreenSharingActive() {
            print("EyeSaver: Skipping overlay - screen sharing is active")
            return
        }

        print("EyeSaver: Showing overlays")
        isBreakActive = true
        breakStartTime = Date()
        fadeInOverlays()

        // Update menu to show Dismiss Break option
        refreshMenuItems()

        fadeOutTimer?.invalidate()
        fadeOutTimer = Timer.scheduledTimer(withTimeInterval: settings.displayDuration, repeats: false) { [weak self] _ in
            self?.fadeOutOverlays()
        }

    }
    
    private func fadeInOverlays() {
        print("Starting fade in animation")
        
        for window in overlayWindows {
            window.orderFrontRegardless()
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = settings.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            for window in overlayWindows {
                window.animator().alphaValue = 1.0
            }
        }) {
            print("Fade in complete")
        }
    }
    
    private func fadeOutOverlays() {
        print("Starting fade out animation")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = settings.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            for window in overlayWindows {
                window.animator().alphaValue = 0.0
            }
        }, completionHandler: { [weak self] in
            print("Fade out complete")
            self?.isBreakActive = false
            self?.breakStartTime = nil
            // Update menu to hide Dismiss Break option
            self?.refreshMenuItems()
            // Schedule next break after the interval
            if self?.settings.isEnabled == true {
                self?.startIntervalTimer()
            }
        })
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // If the menubar is hidden and the app is activated, show preferences
        if !settings.showInMenubar {
            showPreferences()
        }
    }

    private func setupSystemEventObservers() {
        // Listen for screen wake/unlock events
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func systemDidWake() {
        print("EyeSaver: System woke from sleep - resetting timer")
        restartTimer()
    }

    @objc private func screenDidUnlock() {
        print("EyeSaver: Screen unlocked - resetting timer")
        restartTimer()
    }


    private func updateCountdown() {
        let isEffectivelyEnabled = settings.isEnabled && !(settings.disableWhileScreenSharing && settings.isScreenSharingActive())

        guard isEffectivelyEnabled else {
            if settings.isEnabled && settings.disableWhileScreenSharing && settings.isScreenSharingActive() {
                updateCountdownTitle("Disabled while screen sharing")
            } else {
                updateCountdownTitle("Next break in: --:--")
            }
            return
        }

        if isBreakActive, let breakStart = breakStartTime {
            // Show break countdown
            let elapsed = Date().timeIntervalSince(breakStart)
            let remaining = max(0, settings.displayDuration - elapsed)
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            updateCountdownTitle(String(format: "Break ends in: %02d:%02d", minutes, seconds))
        } else if let startTime = intervalStartTime {
            // Show interval countdown
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(0, settings.intervalBetweenShows - elapsed)
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            updateCountdownTitle(String(format: "Next break in: %02d:%02d", minutes, seconds))
        } else {
            updateCountdownTitle("Next break in: --:--")
        }
    }

    private func updateCountdownTitle(_ title: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        countdownMenuItem?.attributedTitle = attributedTitle
    }

    private func dismissBreakEarly() {
        print("EyeSaver: Ending break via dismiss")
        // Cancel the scheduled fade out timer
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil

        // Fade out the overlays (this handles everything else)
        fadeOutOverlays()
    }


    // MARK: - ScreenRecordingMonitorDelegate

    func screenRecordingDidStart() {
        print("EyeSaver: Screen recording started")

        // Cancel current break if active
        if isBreakActive {
            print("EyeSaver: Canceling active break due to screen recording")
            dismissBreakEarly()
        }

        // Update UI to reflect screen recording state
        DispatchQueue.main.async {
            self.refreshMenuItems()
        }
    }

    func screenRecordingDidStop() {
        print("EyeSaver: Screen recording stopped")

        // Update UI to reflect screen recording state
        DispatchQueue.main.async {
            self.refreshMenuItems()
        }
    }
}

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}


