import SwiftUI

/// High-visibility animated progress canvas used while extraction runs.
/// The extraction backend is not percent-based, so the bar is intentionally indeterminate.
struct TaskExtractionProgressCanvasView: View {
    let title: String
    let detail: String?

    init(
        title: String = "Extracting task",
        detail: String? = nil
    ) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.95))
                }
                .frame(width: 28, height: 28)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Spacer(minLength: 0)

                ExtractionProgressDotsView()
            }

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ExtractionProgressBarView()
                .frame(height: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.18),
                            Color.accentColor.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: Color.accentColor.opacity(0.22), radius: 14, y: 6)
    }
}

private struct ExtractionProgressBarView: View {
    private let cycleSeconds: TimeInterval = 1.55

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let fullWidth = max(proxy.size.width, 1)
                let segmentWidth = min(max(fullWidth * 0.34, 140), fullWidth)
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let phase = (elapsed.truncatingRemainder(dividingBy: cycleSeconds)) / cycleSeconds
                let travel = fullWidth + segmentWidth
                let offset = phase * travel - segmentWidth

                ZStack {
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.26),
                                        Color.accentColor.opacity(0.96),
                                        Color.accentColor.opacity(0.26)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: segmentWidth)
                            .offset(x: offset)
                            .blendMode(.plusLighter)
                    }
                    .clipShape(Capsule(style: .continuous))

                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
                }
            }
        }
    }
}

private struct ExtractionProgressDotsView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { idx in
                    let local = (t * 1.9 - Double(idx) * 0.18).truncatingRemainder(dividingBy: 1.0)
                    let normalized = max(0, 1 - abs(local - 0.5) * 2)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .opacity(0.24 + normalized * 0.76)
                }
            }
        }
    }
}
