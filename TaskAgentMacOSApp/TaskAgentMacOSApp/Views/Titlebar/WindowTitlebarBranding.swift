import AppKit
import SwiftUI

struct WindowTitlebarBrandInstaller: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView(frame: .zero)
        view.onWindowChange = { window in
            context.coordinator.installIfNeeded(in: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.installIfNeeded(in: nsView.window)
    }

    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private weak var accessory: ClickCherryTitlebarAccessoryController?

        func installIfNeeded(in window: NSWindow?) {
            guard let window else {
                return
            }

            // Always hide the native title and clear any debug/preview title text.
            // This keeps the top bar clean even when SwiftUI/Preview tooling mutates the window title.
            window.titleVisibility = .hidden
            window.title = ""

            if let existingAccessory = window.titlebarAccessoryViewControllers.first(where: { $0 is ClickCherryTitlebarAccessoryController }) as? ClickCherryTitlebarAccessoryController {
                accessory = existingAccessory
                existingAccessory.updateBrandView()
                self.window = window
                return
            }

            if self.window !== window || accessory == nil {
                let accessory = ClickCherryTitlebarAccessoryController()
                window.addTitlebarAccessoryViewController(accessory)
                self.accessory = accessory
                self.window = window
            }

            accessory?.updateBrandView()
        }
    }
}

private final class WindowObserverView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private final class ClickCherryTitlebarAccessoryController: NSTitlebarAccessoryViewController {
    private let hostingView = NSHostingView(rootView: AppToolbarBrandView())

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .left
        fullScreenMinHeight = 30
        let container = NSView(frame: .zero)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
        updateBrandView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateBrandView() {
        hostingView.rootView = AppToolbarBrandView()
        hostingView.invalidateIntrinsicContentSize()
        let fittingSize = hostingView.fittingSize
        preferredContentSize = NSSize(width: fittingSize.width, height: max(22, fittingSize.height))
    }
}

private struct AppToolbarBrandView: View {
    private var appIconImage: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: appIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 14, height: 14)
            Text("ClickCherry")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ClickCherry")
    }
}
