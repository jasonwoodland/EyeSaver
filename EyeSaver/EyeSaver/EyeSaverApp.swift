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

enum PauseReason: Hashable {
    case idle
    case screenSharing
    case mediaPlaying(processName: String)

    var displayText: String {
        switch self {
        case .idle: return "idle"
        case .screenSharing: return "Screen Sharing"
        case .mediaPlaying(let name): return name
        }
    }

    var sortOrder: Int {
        switch self {
        case .screenSharing: return 0
        case .mediaPlaying: return 1
        case .idle: return 2
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, MediaPlaybackMonitorDelegate {

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
    private var idleCheckTimer: Timer?
    private var pauseReasons: Set<PauseReason> = []
    private var remainingTimeWhenPaused: TimeInterval?
    private var isPaused: Bool { !pauseReasons.isEmpty }
    
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
            startIdleMonitoring()
        }
    }
    
    private func createOverlayWindows() {
        print("Creating overlay windows")
        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: .zero,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )

            // Explicitly set the frame to match the screen's frame
            window.setFrame(screen.frame, display: false)

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
            let iconName: String
            var opacity: CGFloat = 1.0

            if isBreakActive {
                // During break, show closed eye (rest your eyes)
                iconName = "EyeClosed"
            } else {
                // Always show open eye, but vary opacity
                iconName = "EyeOpen"

                if !settings.isEnabled {
                    opacity = 0.3
                } else if isPaused {
                    opacity = 0.3
                }
            }

            if let image = NSImage(named: iconName) {
                button.image = image
                button.image?.isTemplate = true
                button.alphaValue = opacity
            }
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
            .dropFirst() // Skip initial value - timer started explicitly in applicationDidFinishLaunching
            .sink { [weak self] isEnabled in
                if isEnabled {
                    self?.startIntervalTimer()
                    self?.startIdleMonitoring()
                } else {
                    self?.stopIntervalTimer()
                    self?.stopIdleMonitoring()
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
            .dropFirst() // Skip initial value to avoid duplicate timer at startup
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

        // All monitor state and toggle changes go through syncMonitorPauseState()
        #if ENABLE_SCREEN_SHARING
        settings.$isScreenRecording.dropFirst()
            .sink { [weak self] _ in self?.syncMonitorPauseState() }
            .store(in: &cancellables)
        #endif

        settings.$isMediaPlaying.dropFirst()
            .sink { [weak self] _ in self?.syncMonitorPauseState() }
            .store(in: &cancellables)

        #if ENABLE_SCREEN_SHARING
        settings.$disableWhileScreenSharing.dropFirst()
            .sink { [weak self] _ in self?.syncMonitorPauseState() }
            .store(in: &cancellables)
        #endif

        settings.$disableWhileMediaPlaying.dropFirst()
            .sink { [weak self] _ in self?.syncMonitorPauseState() }
            .store(in: &cancellables)

        settings.$idleTimeout
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self = self, self.settings.isEnabled else { return }
                if newValue == 0 {
                    self.pauseReasons.remove(.idle)
                    self.evaluatePauseState()
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

        // Ensure we have overlay windows for all current screens
        ensureOverlayWindowsForAllScreens()

        // Make sure windows are visible and on top
        for window in overlayWindows {
            window.orderFrontRegardless()
            // Start with alpha 0 for fade in effect
            window.alphaValue = 0.0
        }

        // Fade in the preview
        self.perform(#selector(performOpacityPreviewFadeIn), with: nil, afterDelay: 0, inModes: [.common])
    }

    private func ensureOverlayWindowsForAllScreens() {
        let currentScreenCount = NSScreen.screens.count
        if overlayWindows.count != currentScreenCount {
            print("EyeSaver: Screen count mismatch (windows: \(overlayWindows.count), screens: \(currentScreenCount)), recreating overlay windows")
            recreateOverlayWindows()
        }
    }

    @objc private func performOpacityPreviewFadeIn() {
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            guard let self = self else { return }
            context.duration = 0.3  // Slightly faster fade for preview
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            for window in self.overlayWindows {
                window.animator().alphaValue = 1.0
            }
        }, completionHandler: {
            print("EyeSaver: Preview fade in completed")
        })
    }

    func endOpacityPreview() {
        guard isPreviewingOpacity else {
            print("EyeSaver: endOpacityPreview called but not previewing")
            return
        }

        print("EyeSaver: Actually ending opacity preview")
        isPreviewingOpacity = false

        // Use perform selector to ensure animation runs even when menu is closing
        self.perform(#selector(performOpacityPreviewFadeOut), with: nil, afterDelay: 0, inModes: [.common])
    }

    @objc private func performOpacityPreviewFadeOut() {
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            guard let self = self else { return }
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            for window in self.overlayWindows {
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
        remainingTimeWhenPaused = nil
        pauseReasons.removeAll()
    }

    private func restartTimer() {
        // Only restart if we're enabled and not in the middle of a break
        if settings.isEnabled && !isBreakActive {
            stopIntervalTimer()
            startIntervalTimer()
        }
    }

    private func startIntervalTimer() {
        // Always invalidate existing timer first to prevent orphaned timers
        intervalTimer?.invalidate()
        intervalTimer = nil
        remainingTimeWhenPaused = nil

        let nextBreakTime = Date().addingTimeInterval(settings.intervalBetweenShows)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        print("EyeSaver: Starting interval timer - next break at \(formatter.string(from: nextBreakTime)) (\(Int(settings.intervalBetweenShows)) seconds)")

        intervalStartTime = Date()
        intervalTimer = Timer(timeInterval: settings.intervalBetweenShows, repeats: false) { [weak self] _ in
            self?.showOverlays()
        }
        // Add timer to run loop with .common mode so it fires even when menu is open
        RunLoop.main.add(intervalTimer!, forMode: .common)

        // Check if we should immediately pause (e.g. user is idle or media playing)
        evaluatePauseState()
    }

    private func showOverlays() {
        // Timer has fired, clear reference so wake/unlock handlers can detect a dead timer
        intervalTimer = nil
        remainingTimeWhenPaused = nil

        guard settings.isEnabled && !isPreviewingOpacity && !isPaused else { return }

        // Ensure we have overlay windows for all current screens
        ensureOverlayWindowsForAllScreens()

        print("EyeSaver: Showing overlays")
        isBreakActive = true
        breakStartTime = Date()
        fadeInOverlays()

        // Update menu to show Dismiss Break option
        refreshMenuItems()

        fadeOutTimer?.invalidate()
        fadeOutTimer = Timer(timeInterval: settings.displayDuration, repeats: false) { [weak self] _ in
            self?.fadeOutOverlays()
        }
        // Add timer to run loop with .common mode so it fires even when menu is open
        RunLoop.main.add(fadeOutTimer!, forMode: .common)

    }
    
    private func fadeInOverlays() {
        print("Starting fade in animation")

        for window in overlayWindows {
            window.orderFrontRegardless()
        }

        // Use perform selector to ensure animation runs even when menu is open
        self.perform(#selector(performFadeIn), with: nil, afterDelay: 0, inModes: [.common])
    }

    @objc private func performFadeIn() {
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            guard let self = self else { return }
            context.duration = self.settings.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            for window in self.overlayWindows {
                window.animator().alphaValue = 1.0
            }
        }) {
            print("Fade in complete")
        }
    }
    
    private func fadeOutOverlays() {
        print("Starting fade out animation")

        // Use perform selector to ensure animation runs even when menu is open
        self.perform(#selector(performFadeOut), with: nil, afterDelay: 0, inModes: [.common])
    }

    @objc private func performFadeOut() {
        NSAnimationContext.runAnimationGroup({ [weak self] context in
            guard let self = self else { return }
            context.duration = self.settings.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            for window in self.overlayWindows {
                window.animator().alphaValue = 0.0
            }
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            print("Fade out complete")
            self.fadeOutTimer = nil
            self.isBreakActive = false
            self.breakStartTime = nil
            // Update menu to hide Dismiss Break option
            self.refreshMenuItems()
            // Schedule next break after the interval
            if self.settings.isEnabled {
                self.startIntervalTimer()
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

        // Listen for display sleep/wake (covers closing lid, display timeout)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        // Listen for display configuration changes (connect/disconnect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenConfigurationDidChange() {
        print("EyeSaver: Screen configuration changed")
        // Dispatch async to let the system finish updating screen configuration
        DispatchQueue.main.async { [weak self] in
            self?.recreateOverlayWindows()
        }
    }

    private func recreateOverlayWindows() {
        // Determine visibility state based on app state, not window state
        // (windows may be invalid if their screen was disconnected)
        let wasVisible = isBreakActive || isPreviewingOpacity
        let targetAlpha: CGFloat = wasVisible ? 1.0 : 0.0

        print("EyeSaver: Recreating overlay windows (wasVisible: \(wasVisible), isBreakActive: \(isBreakActive), isPreviewingOpacity: \(isPreviewingOpacity))")

        // Capture the old windows array and clear it immediately
        let oldWindows = overlayWindows
        overlayWindows.removeAll()

        // Close old windows safely - they may be invalid if their screen was disconnected
        for window in oldWindows {
            // Use try/catch-like pattern by checking if window is still valid
            if window.screen != nil || NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
                window.orderOut(nil)
            }
            // Don't call close() on potentially invalid windows - just let them deallocate
        }

        // Create new overlay windows for all current screens
        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: .zero,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )

            // Explicitly set the frame to match the screen's frame
            window.setFrame(screen.frame, display: false)

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
            // Restore alpha value if break or preview was active
            window.alphaValue = targetAlpha
            window.orderFrontRegardless()

            overlayWindows.append(window)

            print("Created overlay window for screen: \(screen.localizedName)")
            print("  Screen frame: \(screen.frame)")
            print("  Window frame: \(window.frame)")
        }

        print("Total overlay windows recreated: \(overlayWindows.count)")
    }

    @objc private func systemDidWake() {
        print("EyeSaver: System woke from sleep")
        handleSystemResume()
    }

    @objc private func screenDidUnlock() {
        print("EyeSaver: Screen unlocked")
        handleSystemResume()
    }

    @objc private func screensDidWake() {
        print("EyeSaver: Screens woke")
        handleSystemResume()
    }

    private func handleSystemResume() {
        guard settings.isEnabled else { return }

        if isBreakActive {
            // Break was active during sleep/lock — if fadeOutTimer already fired
            // or is invalid, the animation completion handler likely didn't run,
            // so force-end the break and restart the cycle
            if fadeOutTimer == nil || !fadeOutTimer!.isValid || fadeOutTimer!.fireDate <= Date() {
                print("EyeSaver: Break was active but fadeOutTimer is invalid, ending break")
                fadeOutTimer = nil
                isBreakActive = false
                breakStartTime = nil
                for window in overlayWindows {
                    window.alphaValue = 0.0
                }
                refreshMenuItems()
                startIntervalTimer()
            }
            // If fadeOutTimer is still valid, it will fire naturally
            return
        }

        // Not in a break — if timer was paused, evaluatePauseState will handle resume.
        // If timer is dead or overdue, restart it.
        if remainingTimeWhenPaused != nil {
            // Timer was paused before sleep — evaluatePauseState will resume if appropriate
            evaluatePauseState()
        } else if intervalTimer == nil || !intervalTimer!.isValid || intervalTimer!.fireDate <= Date() {
            print("EyeSaver: Restarting timer after resume")
            startIntervalTimer()
        }
    }


    // MARK: - Idle Detection

    private func systemIdleTime() -> TimeInterval {
        let mouseMoved = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let keyDown = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let leftMouseDown = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        let rightMouseDown = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .rightMouseDown)
        let scrollWheel = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel)
        return min(mouseMoved, keyDown, leftMouseDown, rightMouseDown, scrollWheel)
    }

    private func startIdleMonitoring() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkIdleState()
        }
        RunLoop.main.add(idleCheckTimer!, forMode: .common)
    }

    private func stopIdleMonitoring() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
        if pauseReasons.contains(.idle) {
            pauseReasons.remove(.idle)
            evaluatePauseState()
        }
    }

    private func checkIdleState() {
        guard settings.idleTimeout > 0 else {
            if pauseReasons.contains(.idle) {
                pauseReasons.remove(.idle)
                evaluatePauseState()
            }
            return
        }

        let isCurrentlyIdle = systemIdleTime() > settings.idleTimeout

        if isCurrentlyIdle && !pauseReasons.contains(.idle) {
            print("EyeSaver: User is idle (\(Int(systemIdleTime()))s)")
            pauseReasons.insert(.idle)
            evaluatePauseState()
        } else if !isCurrentlyIdle && pauseReasons.contains(.idle) {
            print("EyeSaver: User returned from idle")
            pauseReasons.remove(.idle)
            evaluatePauseState()
        }
    }

    // MARK: - Pause/Resume

    private func evaluatePauseState() {
        if settings.isEnabled && !isBreakActive {
            let wasPaused = remainingTimeWhenPaused != nil
            let shouldBePaused = !pauseReasons.isEmpty

            if !wasPaused && shouldBePaused {
                pauseTimer()
            } else if wasPaused && !shouldBePaused {
                resumeTimer()
            }
        }

        refreshMenuItems()
    }

    private func pauseTimer() {
        guard let timer = intervalTimer, timer.isValid else { return }
        remainingTimeWhenPaused = max(0, timer.fireDate.timeIntervalSinceNow)
        intervalTimer?.invalidate()
        intervalTimer = nil
        let reason = pauseReasons.sorted(by: { $0.sortOrder < $1.sortOrder }).first
        print("EyeSaver: Timer paused with \(Int(remainingTimeWhenPaused!))s remaining (\(reason?.displayText ?? "unknown"))")
    }

    private func resumeTimer() {
        guard let remaining = remainingTimeWhenPaused else { return }
        remainingTimeWhenPaused = nil

        // Set intervalStartTime so countdown display calculates correctly
        let elapsed = settings.intervalBetweenShows - remaining
        intervalStartTime = Date().addingTimeInterval(-elapsed)

        intervalTimer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            self?.showOverlays()
        }
        RunLoop.main.add(intervalTimer!, forMode: .common)
        print("EyeSaver: Timer resumed with \(Int(remaining))s remaining")
    }

    private func updateCountdown() {
        guard settings.isEnabled else {
            updateCountdownTitle("Next break in: --:--")
            return
        }

        if isBreakActive, let breakStart = breakStartTime {
            let elapsed = Date().timeIntervalSince(breakStart)
            let remaining = max(0, settings.displayDuration - elapsed)
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            updateCountdownTitle(String(format: "Break ends in: %02d:%02d", minutes, seconds))
            return
        }

        // Calculate remaining time (frozen when paused, live when running)
        let remaining: TimeInterval
        if let paused = remainingTimeWhenPaused {
            remaining = paused
        } else if let startTime = intervalStartTime {
            remaining = max(0, settings.intervalBetweenShows - Date().timeIntervalSince(startTime))
        } else {
            updateCountdownTitle("Next break in: --:--")
            return
        }

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        let timeStr = String(format: "%02d:%02d", minutes, seconds)

        if let reason = pauseReasons.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
            updateCountdownTitle("Next break in: \(timeStr) (Paused, \(reason.displayText))")
        } else {
            updateCountdownTitle("Next break in: \(timeStr)")
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


    // MARK: - Monitor Pause State

    private func syncMonitorPauseState() {
        #if ENABLE_SCREEN_SHARING
        // Screen sharing
        if settings.disableWhileScreenSharing && settings.isScreenRecording {
            if !pauseReasons.contains(.screenSharing) {
                pauseReasons.insert(.screenSharing)
                if isBreakActive { dismissBreakEarly() }
            }
        } else {
            pauseReasons.remove(.screenSharing)
        }
        #endif

        // Media playback
        let hadMedia = pauseReasons.contains(where: { if case .mediaPlaying = $0 { return true }; return false })
        pauseReasons = pauseReasons.filter {
            if case .mediaPlaying = $0 { return false }
            return true
        }
        if settings.disableWhileMediaPlaying && settings.isMediaPlaying {
            let name = settings.mediaPlaybackProcessName ?? "Media"
            pauseReasons.insert(.mediaPlaying(processName: name))
            if !hadMedia && isBreakActive { dismissBreakEarly() }
        }

        evaluatePauseState()
    }

    // MARK: - MediaPlaybackMonitorDelegate

    func mediaPlaybackDidChange(isPlaying: Bool, processName: String?) {
        print("EyeSaver: Media playback: \(isPlaying) (\(processName ?? "none"))")
    }
}

#if ENABLE_SCREEN_SHARING
extension AppDelegate: ScreenRecordingMonitorDelegate {
    func screenRecordingDidStart() {
        print("EyeSaver: Screen recording started")
    }

    func screenRecordingDidStop() {
        print("EyeSaver: Screen recording stopped")
    }
}
#endif

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}


