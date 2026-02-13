import SwiftUI

enum PermissionRowMetrics {
    static let rowPaddingX: CGFloat = 18
    static let rowPaddingY: CGFloat = 16
    static let buttonWidth: CGFloat = 130
    static let statusPillWidth: CGFloat = 112
}

struct PermissionRowView<ExtraContent: View>: View {
    let title: String
    let status: PermissionGrantStatus
    let footnote: String?
    let onOpenSettings: () -> Void
    @ViewBuilder let extraContent: () -> ExtraContent

    init(
        title: String,
        status: PermissionGrantStatus,
        footnote: String? = nil,
        onOpenSettings: @escaping () -> Void
    ) where ExtraContent == EmptyView {
        self.title = title
        self.status = status
        self.footnote = footnote
        self.onOpenSettings = onOpenSettings
        self.extraContent = { EmptyView() }
    }

    init(
        title: String,
        status: PermissionGrantStatus,
        footnote: String? = nil,
        onOpenSettings: @escaping () -> Void,
        @ViewBuilder extraContent: @escaping () -> ExtraContent
    ) {
        self.title = title
        self.status = status
        self.footnote = footnote
        self.onOpenSettings = onOpenSettings
        self.extraContent = extraContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(.bordered)
                    .frame(width: PermissionRowMetrics.buttonWidth)

                PermissionStatusPillView(status: status)
                    .frame(width: PermissionRowMetrics.statusPillWidth, alignment: .trailing)
            }

            if let footnote {
                Text(footnote)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }

            extraContent()
        }
        .padding(.horizontal, PermissionRowMetrics.rowPaddingX)
        .padding(.vertical, PermissionRowMetrics.rowPaddingY)
    }
}

struct PermissionStatusPillView: View {
    let status: PermissionGrantStatus

    private var backgroundColor: Color {
        switch status {
        case .granted:
            return Color.green.opacity(0.65)
        case .notGranted:
            return Color.orange.opacity(0.55)
        case .unknown:
            return Color.primary.opacity(0.12)
        }
    }

    private var foregroundStyle: some ShapeStyle {
        switch status {
        case .granted:
            return AnyShapeStyle(Color.black)
        case .notGranted:
            return AnyShapeStyle(Color.black)
        case .unknown:
            return AnyShapeStyle(Color.secondary)
        }
    }

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(backgroundColor))
            .foregroundStyle(foregroundStyle)
    }
}

