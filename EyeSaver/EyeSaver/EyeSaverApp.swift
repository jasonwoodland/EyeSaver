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
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        settings = EyeSaverSettings()
        settings.appDelegate = self

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eyes", accessibilityDescription: "EyeSaver")
            button.image?.isTemplate = true
        }

        setupSwiftUIMenu()
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

        // Add SwiftUI sliders as hosting views
        addSliderMenuItem(to: menu, title: "Interval",
            value: settings.intervalBetweenShows / 60,
            range: 5...60,
            step: 5,
            formatter: { "\(Int($0)) min" },
            onChange: { [weak self] value in
                self?.settings.intervalBetweenShows = value * 60
            })

        addSliderMenuItem(to: menu, title: "Duration",
            value: settings.displayDuration,
            range: 1...min(settings.intervalBetweenShows, 300),
            step: 1,
            formatter: { "\(Int($0))s" },
            onChange: { [weak self] value in
                self?.settings.displayDuration = value
            })

        addSliderMenuItem(to: menu, title: "Fade In",
            value: settings.fadeInDuration,
            range: 0...5,
            step: 0.1,
            formatter: { String(format: "%.1fs", $0) },
            onChange: { [weak self] value in
                self?.settings.fadeInDuration = value
            })

        addSliderMenuItem(to: menu, title: "Fade Out",
            value: settings.fadeOutDuration,
            range: 0...5,
            step: 0.1,
            formatter: { String(format: "%.1fs", $0) },
            onChange: { [weak self] value in
                self?.settings.fadeOutDuration = value
            })

        addOpacitySliderMenuItem(to: menu)

        menu.addItem(NSMenuItem.separator())

        // Quit option
        let quitItem = NSMenuItem(title: "Quit EyeSaver", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func addSliderMenuItem(to menu: NSMenu, title: String, value: Double, range: ClosedRange<Double>, step: Double, formatter: @escaping (Double) -> String, onChange: @escaping (Double) -> Void) {
        let sliderView = SliderView(title: title, value: value, range: range, step: step, formatter: formatter, onChange: onChange)
        let hostingView = NSHostingView(rootView: sliderView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 60)

        let menuItem = NSMenuItem()
        menuItem.view = hostingView
        menu.addItem(menuItem)
    }

    private func addOpacitySliderMenuItem(to menu: NSMenu) {
        let sliderView = OpacitySliderView(
            title: "Opacity",
            value: settings.overlayOpacity,
            onChange: { [weak self] value in
                self?.settings.overlayOpacity = value
            },
            onPreviewStart: { [weak self] in
                self?.startOpacityPreview()
            },
            onPreviewEnd: { [weak self] in
                self?.endOpacityPreview()
            }
        )
        let hostingView = NSHostingView(rootView: sliderView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 60)

        let menuItem = NSMenuItem()
        menuItem.view = hostingView
        menu.addItem(menuItem)
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
}

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}


