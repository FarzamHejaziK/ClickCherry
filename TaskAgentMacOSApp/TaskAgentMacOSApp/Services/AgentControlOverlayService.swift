import AppKit

protocol AgentControlOverlayService {
    func showAgentInControl()
    func hideAgentInControl()
}

final class HUDWindowAgentControlOverlayService: AgentControlOverlayService {
    private var overlayWindow: NSWindow?

    func showAgentInControl() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showAgentInControl()
            }
            return
        }

        hideAgentInControl()

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let size = NSSize(width: 420, height: 92)
        let frame = centeredFrame(size: size, on: screen.visibleFrame)

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.92
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        window.contentView = makeContentView(size: size)
        window.orderFrontRegardless()

        overlayWindow = window
    }

    func hideAgentInControl() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.hideAgentInControl()
            }
            return
        }

        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    private func centeredFrame(size: NSSize, on container: NSRect) -> NSRect {
        NSRect(
            x: container.midX - size.width / 2.0,
            y: container.midY - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private func makeContentView(size: NSSize) -> NSView {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.alphaValue = 0.78
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let title = NSTextField(labelWithString: "Agent is running")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Press Escape to stop")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        let header = NSStackView(views: [spinner, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let stack = NSStackView(views: [header, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])

        return root
    }
}
