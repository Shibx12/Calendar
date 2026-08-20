import AppKit
import QuartzCore
import SwiftUI

@MainActor
private final class ReminderIslandModel: ObservableObject {
    @Published var reminder: ScheduledReminder?
    @Published var topInset: CGFloat = 32
    @Published var seedCenterY: CGFloat = 16
    @Published var surfaceWidthProgress: CGFloat = 0
    @Published var surfaceHeightProgress: CGFloat = 0
    @Published var contentProgress: CGFloat = 0
}

@MainActor
private final class ReminderIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum ReminderIslandLayout {
    static let horizontalMargin: CGFloat = 25

    static func expandedWidth(
        contentWidth: CGFloat,
        minimumWidth: CGFloat,
        maximumWidth: CGFloat
    ) -> CGFloat {
        min(
            max(minimumWidth, ceil(contentWidth + 2 * horizontalMargin)),
            maximumWidth
        )
    }
}

/// A top-attached, continuous-corner surface that grows from the visual
/// center of the MacBook notch without resizing its host window.
private struct IslandSurfaceShape: Shape {
    var widthProgress: CGFloat
    var heightProgress: CGFloat
    var seedCenterY: CGFloat
    var expandedCornerRadius: CGFloat = 16

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(widthProgress, heightProgress) }
        set {
            widthProgress = newValue.first
            heightProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let horizontal = min(max(widthProgress, 0), 1)
        let vertical = min(max(heightProgress, 0), 1)
        let seedSize: CGFloat = 1

        let width = seedSize + (rect.width - seedSize) * horizontal
        // Extending the continuous rounded rectangle above the window leaves
        // its top edge flush with the display while retaining continuous
        // curvature on the two visible lower corners.
        let expandedTop = -expandedCornerRadius
        let expandedHeight = rect.height + expandedCornerRadius
        let height = seedSize + (expandedHeight - seedSize) * vertical
        let seedTop = seedCenterY - seedSize / 2
        let top = seedTop + (expandedTop - seedTop) * vertical
        let shapeRect = CGRect(
            x: rect.midX - width / 2,
            y: top,
            width: width,
            height: height
        )
        let cornerRadius = min(expandedCornerRadius, min(width, height) / 2)
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: shapeRect)
    }
}

private struct ReminderIslandView: View {
    @ObservedObject var model: ReminderIslandModel

    var body: some View {
        ZStack(alignment: .top) {
            IslandSurfaceShape(
                widthProgress: model.surfaceWidthProgress,
                heightProgress: model.surfaceHeightProgress,
                seedCenterY: model.seedCenterY
            )
            .fill(Color.black)

            if let reminder = model.reminder {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(nsColor: reminder.event.calendarColor))
                        .frame(width: 8, height: 8)

                    Text(reminder.event.title)
                        .lineLimit(1)

                    Text("•")

                    Text(reminderRelativeText(reminder))
                        .lineLimit(1)
                }
                .font(.body)
                .foregroundStyle(.white.opacity(0.68))
                .padding(.horizontal, ReminderIslandLayout.horizontalMargin)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, model.topInset + 2)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(Double(model.contentProgress))
                .scaleEffect(0.97 + 0.03 * model.contentProgress, anchor: .top)
                .offset(y: -4 * (1 - model.contentProgress))
            }
        }
        .background(Color.clear)
    }
}

private func reminderRelativeText(_ reminder: ScheduledReminder, now: Date = Date()) -> String {
    if reminder.event.startDate <= now, reminder.event.endDate > now {
        return L10n.format(
            "reminder.remaining_format",
            TimelineFormatter.menuBarDuration(
                reminder.event.endDate.timeIntervalSince(now),
                usesPlural: true
            )
        )
    }
    return TimelineFormatter.menuBarDuration(
        reminder.event.startDate.timeIntervalSince(now),
        usesPlural: false
    )
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
    private var transitionTask: Task<Void, Never>?
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
        transitionTask?.cancel()
        hideTask = nil
        transitionTask = nil
        queue.removeAll()
        current = nil
        isDismissing = false
        stopSwipeMonitoring()
        panel.orderOut(nil)
        resetPresentation()
    }

    private func configurePanel() {
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        // The panel is created while the app launches, usually on Desktop 1.
        // Move it to whichever Space is active when a reminder is presented
        // instead of relying on a window created on Desktop 1 to join Spaces.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentViewController = NSHostingController(rootView: ReminderIslandView(model: model))
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.borderWidth = 0
        panel.contentView?.layer?.shadowOpacity = 0
        panel.contentView?.layer?.masksToBounds = true
        panel.invalidateShadow()
    }

    private func present(_ reminder: ScheduledReminder) {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }

        hideTask?.cancel()
        transitionTask?.cancel()
        current = reminder
        isDismissing = false
        swipeDistance = 0
        model.reminder = reminder
        model.topInset = max(28, screen.safeAreaInsets.top)
        model.seedCenterY = notchFrame(on: screen).height / 2
        resetPresentation(keepingReminder: true)

        panel.setFrame(expandedFrame(on: screen), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startSwipeMonitoring()

        // Width leads height slightly, producing an organic stretch rather
        // than scaling the complete window as a single rigid rectangle.
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.50)) {
            model.surfaceWidthProgress = 1
        }

        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled, let self, self.current?.id == reminder.id else { return }
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.46)) {
                self.model.surfaceHeightProgress = 1
            }

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, self.current?.id == reminder.id else { return }
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)) {
                self.model.contentProgress = 1
            }
            self.transitionTask = nil
        }

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
        transitionTask?.cancel()
        hideTask = nil
        transitionTask = nil
        stopSwipeMonitoring()

        let remainingTravel = max(model.surfaceWidthProgress, model.surfaceHeightProgress)
        let widthDuration = max(0.18, 0.50 * Double(remainingTravel))
        let heightDuration = max(0.17, 0.46 * Double(remainingTravel))

        withAnimation(.easeOut(duration: 0.16)) {
            model.contentProgress = 0
        }

        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: heightDuration)) {
                self.model.surfaceHeightProgress = 0
            }

            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: widthDuration)) {
                self.model.surfaceWidthProgress = 0
            }

            try? await Task.sleep(for: .seconds(max(widthDuration, heightDuration) + 0.05))
            guard !Task.isCancelled else { return }
            self.finishDismissal()
        }
    }

    private func finishDismissal() {
        panel.orderOut(nil)
        current = nil
        isDismissing = false
        transitionTask = nil
        resetPresentation()

        if !queue.isEmpty {
            let next = queue.removeFirst()
            present(next)
        }
    }

    private func resetPresentation(keepingReminder: Bool = false) {
        model.surfaceWidthProgress = 0
        model.surfaceHeightProgress = 0
        model.contentProgress = 0
        if !keepingReminder {
            model.reminder = nil
        }
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let minimumWidth = notchFrame(on: screen).width
        let contentWidth = current.map(islandContentWidth(for:)) ?? minimumWidth
        let width = ReminderIslandLayout.expandedWidth(
            contentWidth: contentWidth,
            minimumWidth: minimumWidth,
            maximumWidth: screen.frame.width - 40
        )
        let font = preferredBodyFont()
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let height = max(62, model.topInset + lineHeight + 17)
        return topCenteredFrame(width: width, height: height, screen: screen)
    }

    private func islandContentWidth(for reminder: ScheduledReminder) -> CGFloat {
        let font = preferredBodyFont()
        let textWidths = textWidth(reminder.event.title, font: font)
            + textWidth("•", font: font)
            + textWidth(reminderRelativeText(reminder), font: font)
        // Dot + the three 8pt gaps between the four visible elements.
        return 8 + textWidths + 3 * 8
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func preferredBodyFont() -> NSFont {
        NSFont.preferredFont(forTextStyle: .body, options: [:])
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
            transitionTask?.cancel()
            transitionTask = nil
            swipeDistance = 0
        }

        let physicalDelta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
        swipeDistance = max(0, swipeDistance + physicalDelta)
        let progress = min(1, swipeDistance / 74)
        model.surfaceWidthProgress = 1 - progress
        model.surfaceHeightProgress = max(0, 1 - progress * 1.08)
        model.contentProgress = max(0, 1 - progress * 1.8)

        if progress >= 0.74 {
            dismiss()
            return
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if progress >= 0.34 {
                dismiss()
            } else {
                swipeDistance = 0
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.32)) {
                    model.surfaceWidthProgress = 1
                    model.surfaceHeightProgress = 1
                    model.contentProgress = 1
                }
            }
        }
    }
}
