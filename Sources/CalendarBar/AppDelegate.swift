import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
private final class CalendarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = CalendarService()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let reminderScheduler = ReminderScheduler()
    private let reminderIsland = ReminderIslandController()
    private let focusModeMonitor = FocusModeMonitor()
    private let popoverNavigation = PopoverNavigationModel()
    private let panel = CalendarPanel(
        contentRect: NSRect(x: 0, y: 0, width: AppLayout.popoverWidth, height: 360),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var cancellables = Set<AnyCancellable>()
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePanel()
        configureReminders()
        configureFocusMode()
        observeService()
        service.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopEventMonitoring()
        reminderScheduler.stop()
        focusModeMonitor.stop()
        reminderIsland.dismissImmediately()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.image = nil
        button.imagePosition = .noImage
        button.toolTip = "CalendarBar"
        updateStatusItem()
    }

    private func configurePanel() {
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        applyPanelAppearance(service.preferences.appearance)
        panel.contentViewController = NSHostingController(
            rootView: CalendarPopoverView(
                service: service,
                navigation: popoverNavigation,
                onPreferredHeightChange: { [weak self] height in
                    self?.resizePanel(to: height)
                },
                onTestReminder: { [weak self] in
                    self?.showTestReminder()
                },
                onOpenEvent: { [weak self] event in
                    self?.openEventInCalendar(event)
                }
            )
        )
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 18
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
    }

    private func resizePanel(to requestedHeight: CGFloat) {
        let screenHeight = statusItem.button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 900
        let height = min(requestedHeight, floor(screenHeight / 2))
        let newSize = NSSize(width: AppLayout.popoverWidth, height: height)
        guard panel.contentLayoutRect.size != newSize else { return }

        if panel.isVisible {
            // Keep the top and both side edges completely stationary while
            // only the bottom edge follows content-height changes.
            let currentFrame = panel.frame
            let targetFrame = NSRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - height,
                width: currentFrame.width,
                height: height
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.34
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.2,
                    0.8,
                    0.2,
                    1
                )
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setContentSize(newSize)
        }
    }

    private func observeService() {
        Publishers.CombineLatest3(service.$access, service.$menuEvents, service.$now)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        service.$weekEvents
            .sink { [weak self] events in
                self?.reminderScheduler.update(events: events)
            }
            .store(in: &cancellables)

        service.preferences.$appearance
            .removeDuplicates()
            .sink { [weak self] appearance in
                self?.applyPanelAppearance(appearance)
            }
            .store(in: &cancellables)

        service.preferences.$appLanguage
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.reminderIsland.dismissImmediately()
            }
            .store(in: &cancellables)
    }

    private func applyPanelAppearance(_ appearance: AppAppearance) {
        switch appearance {
        case .system:
            panel.appearance = nil
        case .light:
            panel.appearance = NSAppearance(named: .aqua)
        case .dark:
            panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func configureReminders() {
        reminderScheduler.onReminder = { [weak self] reminder in
            self?.focusModeMonitor.refresh()
            guard self?.focusModeMonitor.isFocusActive == false else { return }
            self?.reminderIsland.enqueue(reminder)
        }
    }

    private func configureFocusMode() {
        focusModeMonitor.onFocusChange = { [weak self] isActive in
            if isActive {
                self?.reminderIsland.dismissImmediately()
            }
        }
        focusModeMonitor.start()
    }

    private func showTestReminder() {
        focusModeMonitor.refresh()
        guard !focusModeMonitor.isFocusActive else {
            closePanel(animated: false)
            return
        }
        let now = Date()
        let nearestEvent = service.weekEvents
            .filter { $0.startDate > now }
            .min { $0.startDate < $1.startDate }
        let event = nearestEvent ?? CalendarEvent(
            id: "calendarbar-preview",
            title: L10n.text("preview.title"),
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(40 * 60),
            calendarID: "calendarbar-preview",
            calendarTitle: L10n.text("preview.calendar"),
            calendarColor: .systemBlue
        )

        closePanel(animated: false)
        reminderIsland.enqueue(ScheduledReminder(event: event, fireDate: now))
    }

    private func openEventInCalendar(_ event: CalendarEvent) {
        closePanel(animated: false)
        if let url = AppleCalendarLink.eventURL(for: event), NSWorkspace.shared.open(url) {
            return
        }
        if let fallbackURL = AppleCalendarLink.dayURL(for: event) {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let text = service.statusText
        button.title = text
        button.toolTip = service.menuEvents.isEmpty && service.access == .granted
            ? L10n.format(
                "status.free_tooltip",
                Int64(service.preferences.lookAheadHours)
            )
            : text
        statusItem.length = NSStatusItem.variableLength
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePanel(animated: false)
            showContextMenu(from: sender)
            return
        }

        if panel.isVisible {
            closePanel()
        } else {
            // A new presentation always starts on the calendar page. Reset
            // while hidden so there is no visible settings-to-calendar flash.
            popoverNavigation.resetToCalendar()
            service.refreshIfStale()
            DispatchQueue.main.async { [weak self] in
                self?.presentPanel()
            }
        }
    }

    private func presentPanel() {
        let finalFrame = targetPanelFrame(for: panel.frame.size)
        let startFrame = finalFrame.offsetBy(dx: 0, dy: 8)
        panel.setFrame(startFrame, display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)
        panel.makeKey()
        startEventMonitoring()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    private func closePanel(animated: Bool = true) {
        guard panel.isVisible else { return }
        stopEventMonitoring()

        guard animated else {
            finishHidingPanel()
            return
        }

        let endFrame = panel.frame.offsetBy(dx: 0, dy: 5)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.finishHidingPanel()
            }
        }
    }

    private func finishHidingPanel() {
        panel.orderOut(nil)
        panel.alphaValue = 1

        // Reset after the panel is fully hidden. SwiftUI then reports the
        // calendar page's shorter preferred height while NSPanel is offscreen,
        // so the next presentation starts at its final size.
        popoverNavigation.resetToCalendar()
    }

    private func targetPanelFrame(for size: NSSize) -> NSRect {
        guard let button = statusItem.button, let window = button.window else {
            return NSRect(origin: panel.frame.origin, size: size)
        }

        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let gap: CGFloat = 6
        let idealX = buttonRect.midX - size.width / 2
        let x = min(
            max(idealX, visibleFrame.minX + margin),
            visibleFrame.maxX - size.width - margin
        )
        let idealY = buttonRect.minY - size.height - gap
        let y = max(idealY, visibleFrame.minY + margin)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func startEventMonitoring() {
        stopEventMonitoring()
        let panelNumber = panel.windowNumber

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            if event.type == .keyDown, event.keyCode == 53 {
                Task { @MainActor in self?.closePanel() }
                return nil
            }
            if event.type != .keyDown, event.windowNumber != panelNumber {
                Task { @MainActor in self?.closePanel() }
            }
            return event
        }
    }

    private func stopEventMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let refresh = NSMenuItem(
            title: L10n.text("action.refresh_calendar"),
            action: #selector(refreshCalendar),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: L10n.text("action.quit"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshCalendar() {
        service.refresh()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
