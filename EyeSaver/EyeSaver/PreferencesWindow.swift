//
//  PreferencesWindow.swift
//  EyeSaver
//
//  Created by Jason Woodland on 4/9/2025.
//

import SwiftUI
import Combine

enum PreferenceCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case schedule = "Schedule"
    case appearance = "Appearance"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .schedule: return "clock"
        case .appearance: return "paintbrush"
        case .about: return "info.circle"
        }
    }
}

struct PreferencesWindow: View {
    @ObservedObject var settings: EyeSaverSettings
    @State private var selectedCategory: PreferenceCategory = .general

    var body: some View {
        NavigationSplitView {
            // Sidebar - extends behind titlebar in Tahoe design
            VStack(spacing: 0) {
                // Sidebar content with proper safe area handling
                List(PreferenceCategory.allCases, selection: $selectedCategory) { category in
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        Text(category.rawValue)
                    }
                    .tag(category)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .top) {
                    // Spacer for titlebar area
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 0)
                }

            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            // Detail view
            Group {
                switch selectedCategory {
                case .general:
                    GeneralPreferencesView(settings: settings)
                case .schedule:
                    SchedulePreferencesView(settings: settings)
                case .appearance:
                    AppearancePreferencesView(settings: settings)
                case .about:
                    AboutPreferencesView()
                }
            }
            .navigationTitle("EyeSaver Preferences")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 700, height: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            // Handle window close cleanup if needed
        }
        .onAppear {
            // Set up window-specific keyboard shortcuts
            setupWindowCommands()
        }
        .background(
            Button("", action: { NSApp.terminate(nil) })
                .keyboardShortcut("q", modifiers: .command)
                .hidden()
        )
    }

    private func setupWindowCommands() {
        // Cmd+W will automatically work with the window's close button
        // No additional setup needed as NSWindow handles this by default
    }
}

// MARK: - General Preferences
struct GeneralPreferencesView: View {
    @ObservedObject var settings: EyeSaverSettings

    var body: some View {
        Form {
            Section {
                Toggle("Enable", isOn: $settings.isEnabled)
            } footer: {
                Text("Enable EyeSaver breaks.")
            }

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Show in Menubar", isOn: $settings.showInMenubar)
            } header: {
                Text("Preferences")
            }

            Section {
                Toggle("Disable While Screen Sharing", isOn: $settings.disableWhileScreenSharing)
            } header: {
                Text("Behaviour")
            } footer: {
                Text("Automatically pause breaks during presentations and video calls.")
            }

            Section {
                Button("Quit EyeSaver") {
                    NSApp.terminate(nil)
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Schedule Preferences
struct SchedulePreferencesView: View {
    @ObservedObject var settings: EyeSaverSettings

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Interval Between Breaks")
                    Spacer()
                    HStack {
                        Slider(
                            value: Binding(
                                get: { settings.intervalBetweenShows / 60 },
                                set: { settings.intervalBetweenShows = Double(Int($0.rounded())) * 60 }
                            ),
                            in: 5...60
                        )
                        .controlSize(.small)
                        Text("\(Int(settings.intervalBetweenShows / 60)) min")
                            .foregroundColor(.secondary)
                            .frame(minWidth: 50, alignment: .trailing)
                    }
                    .frame(width: 250)
                }

                HStack {
                    Text("Display Duration")
                    Spacer()
                    HStack {
                        Slider(
                            value: $settings.displayDuration,
                            in: 1...min(settings.intervalBetweenShows, 300)
                        )
                        .controlSize(.small)
                        Text("\(Int(settings.displayDuration)) sec")
                            .foregroundColor(.secondary)
                            .frame(minWidth: 50, alignment: .trailing)
                    }
                    .frame(width: 250)
                }
            } header: {
                Text("Timing")
            } footer: {
                Text("Control how often breaks start and how long they last.")
            }

            Section {
                HStack {
                    Text("Fade Duration")
                    Spacer()
                    HStack {
                        Slider(
                            value: $settings.fadeDuration,
                            in: 0...5
                        )
                        .controlSize(.small)
                        Text(String(format: "%.1f sec", settings.fadeDuration))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                    .frame(width: 250)
                }
            } header: {
                Text("Animation")
            } footer: {
                Text("Adjust the fade animation timing for overlay transitions.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Appearance Preferences
struct AppearancePreferencesView: View {
    @ObservedObject var settings: EyeSaverSettings
    @State private var isPreviewActive = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Dimming Amount")
                    Spacer()
                    HStack {
                        Slider(
                            value: $settings.overlayOpacity,
                            in: 0...1
                        ) { editing in
                            if editing {
                                if !isPreviewActive {
                                    isPreviewActive = true
                                    settings.startOpacityPreview()
                                }
                            } else {
                                if isPreviewActive {
                                    isPreviewActive = false
                                    settings.endOpacityPreview()
                                }
                            }
                        }
                        .controlSize(.small)
                        .onChange(of: settings.overlayOpacity) {
                            if !isPreviewActive {
                                isPreviewActive = true
                                settings.startOpacityPreview()
                            }
                        }
                        Text("\(Int(settings.overlayOpacity * 100))%")
                            .foregroundColor(.secondary)
                            .frame(minWidth: 50, alignment: .trailing)
                    }
                    .frame(width: 250)
                }
            } header: {
                Text("Screen Overlay")
            } footer: {
                Text("Adjust the amount of screen dimming while showing a reminder. Drag the slider to preview.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            if isPreviewActive {
                isPreviewActive = false
                settings.endOpacityPreview()
            }
        }
    }
}

// MARK: - About Preferences
struct AboutPreferencesView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                // App Icon and Name
                VStack(spacing: 12) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)

                    Text("EyeSaver")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }

                // Description
                Text("A lightweight utility that gently reminds you to rest your eyes following the 20-20-20 rule.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 400)

                // Developer Info
                VStack {
                    Text("By Jason Woodland")
                        .font(.headline)
                        .fontWeight(.medium)

                    Link("https://jasonwoodland.com/eyesaver", destination: URL(string: "https://jasonwoodland.com/eyesaver")!)
                        .font(.body)
                        .foregroundColor(.blue)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

#Preview {
    PreferencesWindow(settings: EyeSaverSettings())
}
