import AppKit
import Carbon
import QuartzCore
import SwiftUI

struct TerminalConsoleView: View {
    let lines: [String]
    let active: Bool
    let paused: Bool

    var body: some View {
        let displayLines = lines.filter { $0 != "GALLAXY TTS CONSOLE" }

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            GallaxyBrand.panelSurface,
                            GallaxyBrand.brandMaroon.opacity(0.12),
                            GallaxyBrand.pageBackground.opacity(0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(foregroundColor(for: index))
                        .lineLimit(index == displayLines.count - 1 ? 3 : 1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var borderColor: Color {
        if paused {
            return GallaxyBrand.textMuted.opacity(0.28)
        }
        return active ? GallaxyBrand.brandMaroonReadable.opacity(0.42) : GallaxyBrand.borderSubtle
    }

    private func foregroundColor(for index: Int) -> Color {
        if paused {
            return GallaxyBrand.textMuted
        }
        return active ? GallaxyBrand.textMain.opacity(0.86) : GallaxyBrand.textMuted
    }
}
