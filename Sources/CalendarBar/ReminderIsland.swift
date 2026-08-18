import AppKit
import QuartzCore
import SwiftUI

@MainActor
private final class ReminderIslandModel: ObservableObject {
    @Published var reminder: ScheduledReminder?
    @Published var topInset: CGFloat = 32
    @Published var contentVisible = false
    @Published var swipeProgress: CGFloat = 0
    @Published var collapsedWidth: CGFloat = 1
    @Published var collapsedHeight: CGFloat = 1
    @Published var collapseCenterY: CGFloat = 16
}

@MainActor
private final class ReminderIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct TopAttachedIslandShape: Shape {
    var radius: CGFloat = 16
    var collapseProgress: CGFloat = 0
    var collapsedWidth: CGFloat = 1
    var collapsedHeight: CGFloat = 1
    var collapseCenterY: CGFloat = 16

    var animatableData: CGFloat {
        get { collapseProgress }
        set { collapseProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(collapseProgress, 0), 1)
        let targetWidth = min(collapsedWidth, rect.width)
        let targetHeight = min(collapsedHeight, rect.height)
        let width = rect.width + (targetWidth - rect.width) * progress
        let height = rect.height + (targetHeight - rect.height) * progress
        let targetY = min(max(0, collapseCenterY - targetHeight / 2), rect.maxY)
        let y = rect.minY + (targetY - rect.minY) * progress
        let shapeRect = CGRect(
            x: rect.midX - width / 2,
            y: y,
            width: width,
            height: height
        )
        let r = min(radius, min(shapeRect.width, shapeRect.height) / 2)
        let overdraw: CGFloat = 1
        var path = Path()
        path.move(to: CGPoint(x: shapeRect.minX - overdraw, y: shapeRect.minY - overdraw))
        path.addLine(to: CGPoint(x: shapeRect.maxX + overdraw, y: shapeRect.minY - overdraw))
        path.addLine(to: CGPoint(x: shapeRect.maxX + overdraw, y: shapeRect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: shapeRect.maxX - r, y: shapeRect.maxY),
            control: CGPoint(x: shapeRect.maxX + overdraw, y: shapeRect.maxY)
        )
        path.addLine(to: CGPoint(x: shapeRect.minX + r, y: shapeRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: shapeRect.minX - overdraw, y: shapeRect.maxY - r),
            control: CGPoint(x: shapeRect.minX - overdraw, y: shapeRect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct ReminderIslandView: View {
    @ObservedObject var model: ReminderIslandModel

    var body: some View {
        ZStack {
            TopAttachedIslandShape(
                radius: 16,
                collapseProgress: model.swipeProgress,
                collapsedWidth: model.collapsedWidth,
                collapsedHeight: model.collapsedHeight,
                collapseCenterY: model.collapseCenterY
            )
                .fill(Color.black)

            if let reminder = model.reminder {
                VStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(reminderRelativeText(reminder))
                            .foregroundStyle(.white.opacity(0.58))
                        Text("•")
                            .foregroundStyle(.white.opacity(0.32))
                        Text(reminder.event.startDate.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.white.opacity(0.58))
                        Text("•")
                            .foregroundStyle(.white.opacity(0.32))
                        Text(reminder.event.calendarTitle)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .regular))

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(nsColor: reminder.event.calendarColor))
                            .frame(width: 8, height: 8)

                        Text(reminder.event.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, model.topInset + 2)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(model.contentVisible ? max(0, 1 - model.swipeProgress * 1.8) : 0)
                .offset(y: model.contentVisible ? -6 * model.swipeProgress : -4)
                .animation(.easeOut(duration: 0.2), value: model.contentVisible)
            }
        }
        .background(Color.clear)
    }

}

private func reminderRelativeText(_ reminder: ScheduledReminder, now: Date = Date()) -> String {
    if reminder.event.startDate <= now, reminder.event.endDate > now {
        return "\(TimelineFormatter.menuBarDuration(reminder.event.endDate.timeIntervalSince(now), usesPlural: true)) left"
    }
    return "in \(TimelineFormatter.menuBarDuration(reminder.event.startDate.timeIntervalSince(now), usesPlural: false))"
}

@MainActor
final class ReminderIslandController {
    private let model = ReminderIslandModel()
    private let panel = ReminderIslandPanel(
        contentRect: NSRect(x: 0, y: 0, width: 180, height: 32),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var queue: [ScheduledReminder] = []
    private var current: ScheduledReminder?
    private var hideTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var collapsedFrame = NSRect.zero
    private var expandedFrame = NSRect.zero
    private var swipeMonitor: Any?
    private var swipeDistance: CGFloat = 0
    private var isDismissing = false

    init() {
        configurePanel()
    }

    func enqueue(_ reminder: ScheduledReminder) {
        guard reminder.id != current?.id, !queue.contains(where: { $0.id == reminder.id }) else { return }
        guard current == nil else {
            queue.append(reminder)
            return
        }
        present(reminder)
    }

    func dismissImmediately() {
        hideTask?.cancel()
        hideTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        queue.removeAll()
        current = nil
        isDismissing = false
        stopSwipeMonitoring()
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentViewController = NSHostingController(
            rootView: ReminderIslandView(model: model)
        )
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.borderWidth = 0
        panel.contentView?.layer?.shadowOpacity = 0
        panel.contentView?.layer?.masksToBounds = true
        panel.invalidateShadow()
    }

    private func present(_ reminder: ScheduledReminder) {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        current = reminder
        isDismissing = false
        dismissTask?.cancel()
        dismissTask = nil
        model.reminder = reminder
        model.topInset = max(28, screen.safeAreaInsets.top)
        model.contentVisible = false
        model.swipeProgress = 0
        swipeDistance = 0

        collapsedFrame = notchFrame(on: screen)
        // Opening still grows from the physical notch frame. Closing deliberately
        // ignores that frame and converges to one point at the notch's center.
        model.collapsedWidth = 1
        model.collapsedHeight = 1
        model.collapseCenterY = collapsedFrame.height / 2
        let finalFrame = expandedFrame(on: screen)
        expandedFrame = finalFrame
        panel.setFrame(collapsedFrame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startSwipeMonitoring()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.46
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.2,
                0.82,
                0.24,
                1
            )
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(finalFrame, display: true)
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(130))
            self?.model.contentVisible = true
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard current != nil, !isDismissing else { return }
        isDismissing = true
        hideTask?.cancel()
        hideTask = nil
        stopSwipeMonitoring()

        let remainingProgress = max(0, 1 - model.swipeProgress)
        let duration = max(0.14, 0.40 * Double(remainingProgress))
        withAnimation(.timingCurve(0.22, 0.78, 0.24, 1, duration: duration)) {
            model.swipeProgress = 1
        }

        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration + 0.04))
            guard !Task.isCancelled, let self else { return }
            self.panel.orderOut(nil)
            self.model.contentVisible = false
            self.model.swipeProgress = 0
            self.current = nil
            self.isDismissing = false
            self.dismissTask = nil
            if !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                self.present(next)
            }
        }
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let minimumWidth = notchFrame(on: screen).width
        let contentWidth = current.map(islandContentWidth(for:)) ?? minimumWidth
        // Fifteen percent of the widest row on each side gives the content
        // breathing room while allowing every reminder to size independently.
        let width = min(
            max(minimumWidth, ceil(contentWidth * 1.30)),
            screen.frame.width - 40
        )
        let height = max(88, model.topInset + 56)
        return topCenteredFrame(width: width, height: height, screen: screen)
    }

    private func islandContentWidth(for reminder: ScheduledReminder) -> CGFloat {
        let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let detailFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let titleTextWidth = textWidth(reminder.event.title, font: titleFont)
        let titleRowWidth = 8 + 8 + titleTextWidth

        let detailParts = [
            reminderRelativeText(reminder),
            "•",
            reminder.event.startDate.formatted(date: .omitted, time: .shortened),
            "•",
            reminder.event.calendarTitle
        ]
        let detailTextWidth = detailParts.reduce(CGFloat.zero) {
            $0 + textWidth($1, font: detailFont)
        }
        let detailRowWidth = detailTextWidth + 4 * 6

        return max(titleRowWidth, detailRowWidth)
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func notchFrame(on screen: NSScreen) -> NSRect {
        let detectedNotchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            detectedNotchWidth = max(0, right.minX - left.maxX)
        } else {
            detectedNotchWidth = 0
        }
        let width = max(170, detectedNotchWidth + 16)
        let height = max(30, screen.safeAreaInsets.top)
        return topCenteredFrame(width: width, height: height, screen: screen)
    }

    private func topCenteredFrame(width: CGFloat, height: CGFloat, screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func startSwipeMonitoring() {
        stopSwipeMonitoring()
        let panelNumber = panel.windowNumber
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard event.windowNumber == panelNumber else { return event }
            self?.handleDismissGesture(event)
            return nil
        }
    }

    private func stopSwipeMonitoring() {
        if let swipeMonitor {
            NSEvent.removeMonitor(swipeMonitor)
            self.swipeMonitor = nil
        }
        swipeDistance = 0
    }

    private func handleDismissGesture(_ event: NSEvent) {
        if event.type == .swipe {
            if event.deltaY > 0 { dismiss() }
            return
        }

        guard event.hasPreciseScrollingDeltas else { return }
        if event.phase.contains(.began) {
            swipeDistance = 0
        }

        let physicalDelta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
        swipeDistance = max(0, swipeDistance + physicalDelta)
        let progress = min(1, swipeDistance / 70)
        model.swipeProgress = progress

        if progress >= 0.72 {
            dismiss()
            return
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if progress >= 0.35 {
                dismiss()
            } else {
                swipeDistance = 0
                withAnimation(.easeOut(duration: 0.2)) {
                    model.swipeProgress = 0
                }
            }
        }
    }
}
