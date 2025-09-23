//
//  EyeSaverApp.swift
//  EyeSaver
//
//  Created by Jason Woodland on 4/9/2025.
//

import Cocoa
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var overlayWindows: [NSWindow] = []
    private var fadeOutTimer: Timer?
    private var intervalTimer: Timer?
    private var statusItem: NSStatusItem?
    private var isPreviewingOpacity = false

    // References to value labels for real-time updates
    private weak var intervalValueLabel: NSTextField?
    private weak var durationValueLabel: NSTextField?
    private weak var fadeInValueLabel: NSTextField?
    private weak var fadeOutValueLabel: NSTextField?
    private weak var opacityValueLabel: NSTextField?

    // Configurable settings with default values
    private var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "EyeSaver.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "EyeSaver.enabled") }
    }

    private var intervalBetweenShows: TimeInterval {
        get {
            let value = UserDefaults.standard.double(forKey: "EyeSaver.intervalBetweenShows")
            return value > 0 ? value : 300.0 // Default: 5 minutes
        }
        set { UserDefaults.standard.set(newValue, forKey: "EyeSaver.intervalBetweenShows") }
    }

    private var displayDuration: TimeInterval {
        get {
            let value = UserDefaults.standard.double(forKey: "EyeSaver.displayDuration")
            return value > 0 ? value : 20.0 // Default: 20 seconds
        }
        set { UserDefaults.standard.set(newValue, forKey: "EyeSaver.displayDuration") }
    }

    private var fadeInDuration: TimeInterval {
        get {
            let value = UserDefaults.standard.double(forKey: "EyeSaver.fadeInDuration")
            return value > 0 ? value : 2.0 // Default: 2 seconds
        }
        set { UserDefaults.standard.set(newValue, forKey: "EyeSaver.fadeInDuration") }
    }

    private var fadeOutDuration: TimeInterval {
        get {
            let value = UserDefaults.standard.double(forKey: "EyeSaver.fadeOutDuration")
            return value > 0 ? value : 2.0 // Default: 2 seconds
        }
        set { UserDefaults.standard.set(newValue, forKey: "EyeSaver.fadeOutDuration") }
    }

    private var overlayOpacity: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: "EyeSaver.overlayOpacity")
            return value > 0 ? CGFloat(value) : 0.66 // Default: 66% opacity
        }
        set { UserDefaults.standard.set(newValue, forKey: "EyeSaver.overlayOpacity") }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        print("EyeSaver: Application launched")
        print("EyeSaver: Interval between shows: \(intervalBetweenShows) seconds")
        print("EyeSaver: Display duration: \(displayDuration) seconds")

        setupStatusItem()
        createOverlayWindows()

        if isEnabled {
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
            
            window.backgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: overlayOpacity)
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

        statusItem?.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Enable/Disable toggle
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())

        // Interval slider
        let intervalItem = NSMenuItem()
        let intervalSlider = NSSlider(value: intervalBetweenShows / 60, minValue: 5, maxValue: 60, target: self, action: #selector(intervalChanged(_:)))
        intervalSlider.numberOfTickMarks = 12 // 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60
        intervalSlider.allowsTickMarkValuesOnly = true
        intervalSlider.isContinuous = true
        intervalItem.view = createSliderView(
            slider: intervalSlider,
            label: "Interval",
            value: "\(Int(intervalBetweenShows / 60)) min"
        )
        menu.addItem(intervalItem)

        // Duration slider
        let durationItem = NSMenuItem()
        let maxDuration = min(intervalBetweenShows, 300) // Max 5 minutes or interval value
        let durationSlider = NSSlider(value: displayDuration, minValue: 1, maxValue: maxDuration, target: self, action: #selector(durationChanged(_:)))
        durationSlider.isContinuous = true
        durationItem.view = createSliderView(
            slider: durationSlider,
            label: "Duration",
            value: "\(Int(displayDuration))s"
        )
        menu.addItem(durationItem)

        // Fade in duration slider
        let fadeInItem = NSMenuItem()
        let fadeInSlider = NSSlider(value: fadeInDuration, minValue: 0, maxValue: 5, target: self, action: #selector(fadeInChanged(_:)))
        fadeInSlider.isContinuous = true
        fadeInItem.view = createSliderView(
            slider: fadeInSlider,
            label: "Fade In",
            value: "\(String(format: "%.1f", fadeInDuration))s"
        )
        menu.addItem(fadeInItem)

        // Fade out duration slider
        let fadeOutItem = NSMenuItem()
        let fadeOutSlider = NSSlider(value: fadeOutDuration, minValue: 0, maxValue: 5, target: self, action: #selector(fadeOutChanged(_:)))
        fadeOutSlider.isContinuous = true
        fadeOutItem.view = createSliderView(
            slider: fadeOutSlider,
            label: "Fade Out",
            value: "\(String(format: "%.1f", fadeOutDuration))s"
        )
        menu.addItem(fadeOutItem)

        // Opacity slider
        let opacityItem = NSMenuItem()
        let opacitySlider = OpacityPreviewSlider(value: Double(overlayOpacity), minValue: 0, maxValue: 1, target: self, action: #selector(opacityChanged(_:)))
        opacitySlider.isContinuous = true
        opacitySlider.appDelegate = self
        opacityItem.view = createSliderView(
            slider: opacitySlider,
            label: "Opacity",
            value: "\(Int(overlayOpacity * 100))%"
        )
        menu.addItem(opacityItem)

        menu.addItem(NSMenuItem.separator())

        // Quit option
        let quitItem = NSMenuItem(title: "Quit EyeSaver", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func createSliderView(slider: NSSlider, label: String, value: String) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 50))

        // Label on the left
        let labelField = NSTextField(labelWithString: label)
        labelField.frame = NSRect(x: 20, y: 28, width: 80, height: 16)
        labelField.font = NSFont.systemFont(ofSize: 12)
        labelField.alignment = .left
        labelField.textColor = NSColor.labelColor
        containerView.addSubview(labelField)

        // Value on the right
        let valueField = NSTextField(labelWithString: value)
        valueField.frame = NSRect(x: 220, y: 28, width: 60, height: 16)
        valueField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        valueField.alignment = .right
        valueField.textColor = NSColor.secondaryLabelColor
        containerView.addSubview(valueField)

        // Store references to value labels for real-time updates
        switch slider.action {
        case #selector(intervalChanged(_:)):
            intervalValueLabel = valueField
        case #selector(durationChanged(_:)):
            durationValueLabel = valueField
        case #selector(fadeInChanged(_:)):
            fadeInValueLabel = valueField
        case #selector(fadeOutChanged(_:)):
            fadeOutValueLabel = valueField
        case #selector(opacityChanged(_:)):
            opacityValueLabel = valueField
        default:
            break
        }

        // Full-width slider in the middle
        slider.frame = NSRect(x: 20, y: 8, width: 260, height: 20)

        containerView.addSubview(slider)

        return containerView
    }

    // Legacy method for backward compatibility
    private func createSliderView(slider: NSSlider, label: String) -> NSView {
        return createSliderView(slider: slider, label: label, value: "")
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        statusItem?.menu = createMenu() // Refresh menu

        if isEnabled {
            startIntervalTimer()
        } else {
            stopIntervalTimer()
        }
    }

    @objc private func intervalChanged(_ sender: NSSlider) {
        let newValue = round(sender.doubleValue / 5) * 5 // Round to nearest 5
        intervalBetweenShows = newValue * 60 // Convert to seconds
        intervalValueLabel?.stringValue = "\(Int(newValue)) min"
        restartTimer()
    }

    @objc private func durationChanged(_ sender: NSSlider) {
        displayDuration = round(sender.doubleValue)
        durationValueLabel?.stringValue = "\(Int(displayDuration))s"
    }

    @objc private func fadeInChanged(_ sender: NSSlider) {
        fadeInDuration = round(sender.doubleValue * 10) / 10 // Round to 0.1s
        fadeInValueLabel?.stringValue = "\(String(format: "%.1f", fadeInDuration))s"
    }

    @objc private func fadeOutChanged(_ sender: NSSlider) {
        fadeOutDuration = round(sender.doubleValue * 10) / 10 // Round to 0.1s
        fadeOutValueLabel?.stringValue = "\(String(format: "%.1f", fadeOutDuration))s"
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        overlayOpacity = CGFloat(sender.doubleValue)
        opacityValueLabel?.stringValue = "\(Int(overlayOpacity * 100))%"
        updateOverlayOpacity()

        // Start preview if not already showing
        if !isPreviewingOpacity {
            startOpacityPreview()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateOverlayOpacity() {
        for window in overlayWindows {
            window.backgroundColor = NSColor(red: 0, green: 0, blue: 0, alpha: overlayOpacity)
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
        if isEnabled {
            stopIntervalTimer()
            startIntervalTimer()
        }
    }

    private func startIntervalTimer() {
        print("EyeSaver: Starting interval timer")
        intervalTimer = Timer.scheduledTimer(withTimeInterval: intervalBetweenShows, repeats: true) { [weak self] _ in
            self?.showOverlays()
        }
    }

    private func showOverlays() {
        guard isEnabled && !isPreviewingOpacity else { return }

        print("EyeSaver: Showing overlays")
        fadeInOverlays()

        fadeOutTimer?.invalidate()
        fadeOutTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            self?.fadeOutOverlays()
        }
    }
    
    private func fadeInOverlays() {
        print("Starting fade in animation")
        
        for window in overlayWindows {
            window.orderFrontRegardless()
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeInDuration
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
            context.duration = fadeOutDuration
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

class OpacityPreviewSlider: NSSlider {
    weak var appDelegate: AppDelegate?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        print("EyeSaver: Mouse up on opacity slider")
        appDelegate?.endOpacityPreview()
    }
}

