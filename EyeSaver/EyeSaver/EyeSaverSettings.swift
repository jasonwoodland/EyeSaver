//
//  EyeSaverSettings.swift
//  EyeSaver
//
//  Created by Jason Woodland on 4/9/2025.
//

import SwiftUI
import Combine

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
    }

    func startOpacityPreview() {
        appDelegate?.startOpacityPreview()
    }

    func endOpacityPreview() {
        appDelegate?.endOpacityPreview()
    }
}