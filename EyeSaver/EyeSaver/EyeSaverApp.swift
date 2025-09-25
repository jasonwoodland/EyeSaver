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

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var overlayWindows: [NSWindow] = []
    private var fadeOutTimer: Timer?
    private var intervalTimer: Timer?
    private var statusItem: NSStatusItem?
    private var isPreviewingOpacity = false
    private var settings: EyeSaverSettings!
    private var cancellables = Set<AnyCancellable>()
    private var preferencesWindow: NSWindow?
    
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

            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "eyes", accessibilityDescription: "EyeSaver")
                button.image?.isTemplate = true
            }

            setupSwiftUIMenu()
        }
    }

    private func hideStatusItem() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func updateActivationPolicy() {
        if settings.showInMenubar {
            // Show in menubar: use accessory mode (doesn't appear in Cmd+Tab)
            NSApp.setActivationPolicy(.accessory)
        } else {
            // Hidden from menubar: use regular mode (appears in Cmd+Tab)
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func setupSwiftUIMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Enable/Disable toggle
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

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

        statusItem?.menu = menu
    }

    @objc private func showPreferences() {
        if let existingWindow = preferencesWindow, existingWindow.isVisible {
            // Window already exists and is visible, just bring it to front
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
            preferencesWindow?.styleMask = [.titled, .closable, .miniaturizable]
            preferencesWindow?.isReleasedWhenClosed = false
            preferencesWindow?.center()
            preferencesWindow?.setFrameAutosaveName("PreferencesWindow")
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        setupSwiftUIMenu() // Refresh menu
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

    func menuDidClose(_ menu: NSMenu) {
        print("EyeSaver: Menu closed, ending opacity preview")
        NotificationCenter.default.post(name: .menuDidClose, object: nil)
        if isPreviewingOpacity {
            endOpacityPreview()
        }
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
        intervalTimer = Timer.scheduledTimer(withTimeInterval: settings.intervalBetweenShows, repeats: true) { [weak self] _ in
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
        fadeInOverlays()

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
            context.duration = settings.fadeInDuration
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
            context.duration = settings.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            for window in overlayWindows {
                window.animator().alphaValue = 0.0
            }
        }, completionHandler: {
            print("Fade out complete")
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
}

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}


