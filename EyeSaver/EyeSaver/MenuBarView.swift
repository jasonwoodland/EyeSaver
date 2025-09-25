//
//  MenuBarView.swift
//  EyeSaver
//
//  Created by Jason Woodland on 4/9/2025.
//

import SwiftUI

struct SliderView: View {
    let title: String
    @State var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Spacer()
                Text(formatter(value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

            Slider(value: $value, in: range, step: step)
                .padding(.horizontal, 12)
                .onChange(of: value) { newValue in
                    onChange(newValue)
                }
        }
        .padding(.vertical, 8)
        .frame(width: 300, height: 60)
    }
}

struct OpacitySliderView: View {
    let title: String
    @State var value: Double
    let onChange: (Double) -> Void
    let onPreviewStart: () -> Void
    let onPreviewEnd: () -> Void
    @State private var isPreviewActive = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)

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
                .padding(.horizontal, 12)
                .onChange(of: value) { newValue in
                    onChange(newValue)
                    if !isPreviewActive {
                        isPreviewActive = true
                        onPreviewStart()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .menuDidClose)) { _ in
                    if isPreviewActive {
                        isPreviewActive = false
                        onPreviewEnd()
                    }
                }
        }
        .padding(.vertical, 8)
        .frame(width: 300, height: 60)
    }
}

extension Notification.Name {
    static let menuDidClose = Notification.Name("menuDidClose")
}
