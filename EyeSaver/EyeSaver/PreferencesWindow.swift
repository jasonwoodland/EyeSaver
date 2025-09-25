//
//  PreferencesWindow.swift
//  EyeSaver
//
//  Created by Jason Woodland on 4/9/2025.
//

import SwiftUI
import Combine

struct PreferencesWindow: View {
    @ObservedObject var settings: EyeSaverSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "eyes.inverse")
                    .foregroundColor(.blue)
                    .font(.title)
                Text("EyeSaver Preferences")
                    .font(.title2)
                    .fontWeight(.medium)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)

            ScrollView {
                VStack(spacing: 24) {
                    // General Settings
                    PreferencesSection(title: "General", icon: "gearshape") {
                        VStack(spacing: 16) {
                            PreferencesToggle(
                                title: "Enable EyeSaver",
                                subtitle: "Automatically show rest reminders",
                                isOn: $settings.isEnabled
                            )

                            PreferencesToggle(
                                title: "Launch at Login",
                                subtitle: "Start EyeSaver when you log in",
                                isOn: $settings.launchAtLogin
                            )

                            PreferencesToggle(
                                title: "Disable While Screen Sharing",
                                subtitle: "Pause reminders when sharing your screen",
                                isOn: $settings.disableWhileScreenSharing
                            )

                            PreferencesToggle(
                                title: "Show in Menubar",
                                subtitle: "Display EyeSaver icon in the menu bar",
                                isOn: $settings.showInMenubar
                            )
                        }
                    }

                    // Timing Settings
                    PreferencesSection(title: "Timing", icon: "clock") {
                        VStack(spacing: 16) {
                            PreferencesSlider(
                                title: "Interval Between Reminders",
                                subtitle: "How often to show rest reminders",
                                value: Binding(
                                    get: { settings.intervalBetweenShows / 60 },
                                    set: { settings.intervalBetweenShows = $0 * 60 }
                                ),
                                range: 5...60,
                                step: 5,
                                unit: "min"
                            )

                            PreferencesSlider(
                                title: "Display Duration",
                                subtitle: "How long to show each reminder",
                                value: $settings.displayDuration,
                                range: 1...min(settings.intervalBetweenShows, 300),
                                step: 1,
                                unit: "sec"
                            )
                        }
                    }

                    // Animation Settings
                    PreferencesSection(title: "Animation", icon: "wand.and.stars") {
                        VStack(spacing: 16) {
                            PreferencesSlider(
                                title: "Fade In Duration",
                                subtitle: "Time to fade in the overlay",
                                value: $settings.fadeInDuration,
                                range: 0...5,
                                step: 0.1,
                                unit: "sec",
                                precision: 1
                            )

                            PreferencesSlider(
                                title: "Fade Out Duration",
                                subtitle: "Time to fade out the overlay",
                                value: $settings.fadeOutDuration,
                                range: 0...5,
                                step: 0.1,
                                unit: "sec",
                                precision: 1
                            )
                        }
                    }

                    // Appearance Settings
                    PreferencesSection(title: "Appearance", icon: "paintbrush") {
                        PreferencesOpacitySlider(
                            title: "Overlay Opacity",
                            subtitle: "Darkness of the screen overlay",
                            value: $settings.overlayOpacity,
                            onPreviewStart: { settings.startOpacityPreview() },
                            onPreviewEnd: { settings.endOpacityPreview() }
                        )
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
        .background(.regularMaterial)
    }
}

struct PreferencesSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 16)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            VStack(spacing: 0) {
                content
            }
            .padding()
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct PreferencesToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
        }
    }
}

struct PreferencesSlider: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let precision: Int

    init(title: String, subtitle: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, precision: Int = 0) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.precision = precision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(formatValue(value))
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }

            Slider(value: $value, in: range, step: step)
                .tint(.blue)
        }
    }

    private func formatValue(_ value: Double) -> String {
        if precision > 0 {
            return String(format: "%.\(precision)f %@", value, unit)
        } else {
            return "\(Int(value)) \(unit)"
        }
    }
}

struct PreferencesOpacitySlider: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let onPreviewStart: () -> Void
    let onPreviewEnd: () -> Void
    @State private var isPreviewActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }

            Slider(value: $value, in: 0...1, step: 0.01) { editing in
                if editing {
                    if !isPreviewActive {
                        isPreviewActive = true
                        onPreviewStart()
                    }
                } else {
                    if isPreviewActive {
                        isPreviewActive = false
                        onPreviewEnd()
                    }
                }
            }
            .tint(.blue)
            .onChange(of: value) {
                if !isPreviewActive {
                    isPreviewActive = true
                    onPreviewStart()
                }
            }
        }
        .onDisappear {
            if isPreviewActive {
                isPreviewActive = false
                onPreviewEnd()
            }
        }
    }
}

#Preview {
    PreferencesWindow(settings: EyeSaverSettings())
}