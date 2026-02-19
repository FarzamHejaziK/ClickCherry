import AppKit
import SwiftUI

struct WindowTitlebarBrandInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView(frame: .zero)
        view.onWindowChange = { window in
            applyBranding(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyBranding(to: nsView.window)
    }

    private func applyBranding(to window: NSWindow?) {
        guard let window else {
            return
        }
        window.title = "ClickCherry"
        window.titleVisibility = .visible
    }
}

private final class WindowObserverView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
