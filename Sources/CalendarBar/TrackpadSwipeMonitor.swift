import AppKit
import SwiftUI

/// Observes precise trackpad scrolling for the hosting window without taking
/// hit testing away from controls or vertical ScrollViews.
struct TrackpadSwipeMonitor: NSViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class MonitorView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator: NSObject {
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        private weak var window: NSWindow?
        private var monitor: Any?
        private var horizontalDistance: CGFloat = 0
        private var didTrigger = false

        init(
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void
        ) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            detach()
            guard let window else { return }
            self.window = window
            let windowNumber = window.windowNumber
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                guard event.windowNumber == windowNumber else { return event }
                self?.handle(event)
                return event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            window = nil
            horizontalDistance = 0
            didTrigger = false
        }

        private func handle(_ event: NSEvent) {
            if event.type == .swipe {
                guard !didTrigger else { return }
                let horizontal = event.deltaX
                    * (event.isDirectionInvertedFromDevice ? -1 : 1)
                if abs(horizontal) > 0.1 {
                    trigger(horizontal > 0 ? .right : .left)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                        self?.horizontalDistance = 0
                        self?.didTrigger = false
                    }
                }
                return
            }

            guard event.hasPreciseScrollingDeltas else { return }
            if event.phase.contains(.began) {
                horizontalDistance = 0
                didTrigger = false
            }
            guard !didTrigger else { return }

            let horizontal = event.scrollingDeltaX
                * (event.isDirectionInvertedFromDevice ? -1 : 1)
            let vertical = event.scrollingDeltaY
            if abs(horizontal) > abs(vertical) * 1.15 {
                horizontalDistance += horizontal
            }

            if horizontalDistance >= 36 {
                trigger(.right)
            } else if horizontalDistance <= -36 {
                trigger(.left)
            } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                horizontalDistance = 0
            }
        }

        private func trigger(_ direction: HorizontalSwipeDirection) {
            didTrigger = true
            switch direction {
            case .left:
                onSwipeLeft()
            case .right:
                onSwipeRight()
            }
        }
    }
}

private enum HorizontalSwipeDirection {
    case left
    case right
}
