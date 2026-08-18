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
        observeService()
        service.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopEventMonitoring()
        reminderScheduler.stop()
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
        panel.contentViewController = NSHostingController(
            rootView: CalendarPopoverView(
                service: service,
                onPreferredHeightChange: { [weak self] height in
                    self?.resizePanel(to: height)
                },
                onTestReminder: { [weak self] in
                    self?.showTestReminder()
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
        panel.setContentSize(newSize)
        if panel.isVisible {
            panel.setFrame(targetPanelFrame(for: panel.frame.size), display: true)
        }
    }

    private func observeService() {
        service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)

        service.$weekEvents
            .sink { [weak self] events in
                self?.reminderScheduler.update(events: events)
            }
            .store(in: &cancellables)
    }

    private func configureReminders() {
        reminderScheduler.onReminder = { [weak self] reminder in
            self?.reminderIsland.enqueue(reminder)
        }
    }

    private func showTestReminder() {
        let now = Date()
        let nearestEvent = service.weekEvents
            .filter { $0.startDate > now }
            .min { $0.startDate < $1.startDate }
        let event = nearestEvent ?? CalendarEvent(
            id: "calendarbar-preview",
            title: "CalendarBar 提醒测试",
            startDate: now.addingTimeInterval(10 * 60),
            endDate: now.addingTimeInterval(40 * 60),
            calendarID: "calendarbar-preview",
            calendarTitle: "测试",
            calendarColor: .systemBlue
        )

        closePanel(animated: false)
        reminderIsland.enqueue(ScheduledReminder(event: event, fireDate: now))
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let text = service.statusText
        button.title = text
        button.toolTip = text == "Free" ? "未来 \(service.preferences.lookAheadHours) 小时没有日程" : text
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
            service.refresh()
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
            panel.orderOut(nil)
            panel.alphaValue = 1
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
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
            }
        }
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
        let refresh = NSMenuItem(title: "刷新日历", action: #selector(refreshCalendar), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 CalendarBar", action: #selector(quitApp), keyEquivalent: "q")
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
