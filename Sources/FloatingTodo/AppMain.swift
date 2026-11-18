import AppKit
import SwiftUI

@main
enum FloatingTodoApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let positionDefaultsKey = "FloatingTodo.panelOrigin"
    private let sizeDefaultsKey = "FloatingTodo.panelSize"
    private let store = TodoStore()
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    private var visibilityMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        installStatusItem()
        createPanel()
        showPanel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        guard let panel else { return }
        let frame = visibleFrame(near: panel.frame.origin, proposedSize: panel.frame.size)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        panel.updateResizeCorner()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: positionDefaultsKey)
        panel.updateResizeCorner()
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        let defaults = UserDefaults.standard
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: positionDefaultsKey)
        defaults.set(NSStringFromSize(panel.frame.size), forKey: sizeDefaultsKey)
        panel.updateResizeCorner()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        panel?.updateResizeCorner()
    }

    func menuWillOpen(_ menu: NSMenu) {
        visibilityMenuItem?.title = panel?.isVisible == true ? "隐藏待办" : "显示待办"
    }

    private func createPanel() {
        let defaults = UserDefaults.standard
        let savedOrigin = defaults.string(forKey: positionDefaultsKey).map(NSPointFromString)
        let savedSize = defaults.string(forKey: sizeDefaultsKey).map(NSSizeFromString).flatMap { size in
            size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0 ? size : nil
        }
        let frame = visibleFrame(near: savedOrigin, proposedSize: savedSize ?? FloatingPanel.initialSize)
        let panel = FloatingPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "悬浮待办"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isRestorable = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        if #available(macOS 13.0, *) {
            panel.collectionBehavior.insert(.canJoinAllApplications)
        }

        panel.updateResizeCorner()
        let controller = NSHostingController(rootView: TodoPanelView(
            store: store,
            resizeState: panel.resizeState,
            onHide: { [weak self] in self?.panel?.orderOut(nil) }
        ))
        if #available(macOS 13.0, *) {
            controller.sizingOptions = []
        }
        panel.contentViewController = controller
        panel.setFrame(frame, display: false)
        panel.updateResizeCorner()
        panel.delegate = self
        self.panel = panel
    }

    private func visibleFrame(near savedOrigin: NSPoint?, proposedSize: NSSize) -> NSRect {
        let savedFrame = savedOrigin.map { NSRect(origin: $0, size: proposedSize) }
        let matchingScreen = savedFrame.flatMap(FloatingPanel.screenAtTopLeft)
        guard let screen = matchingScreen ?? NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(origin: savedOrigin ?? .zero, size: proposedSize)
        }
        let bounds = screen.visibleFrame
        let size = FloatingPanel.fittingSize(proposedSize, within: bounds.size)
        let defaultTopLeft = NSPoint(x: bounds.maxX - size.width - 28, y: bounds.maxY - 28)
        let topLeft = matchingScreen.flatMap { _ in savedFrame.map { NSPoint(x: $0.minX, y: $0.maxY) } }
            ?? defaultTopLeft
        let origin = NSPoint(
            x: max(bounds.minX, min(topLeft.x, bounds.maxX - size.width)),
            y: max(bounds.minY, min(topLeft.y - size.height, bounds.maxY - size.height))
        )
        return NSRect(origin: origin, size: size)
    }

    private func showPanel() {
        panel?.orderFrontRegardless()
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "悬浮待办")
            button.image?.isTemplate = true
            button.toolTip = "悬浮待办"
            button.setAccessibilityLabel("悬浮待办")
        }
        let menu = NSMenu()
        menu.delegate = self
        let visibilityItem = menu.addItem(withTitle: "隐藏待办", action: #selector(togglePanel), keyEquivalent: "")
        visibilityItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "退出悬浮待办", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        item.menu = menu
        visibilityMenuItem = visibilityItem
        statusItem = item
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = mainMenu.addItem(withTitle: "悬浮待办", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "悬浮待办")
        appMenu.addItem(withTitle: "退出悬浮待办", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = mainMenu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApplication.shared.mainMenu = mainMenu
    }
}

enum WindowResizeCorner: Equatable {
    case bottomLeft, bottomRight
}

@MainActor
final class WindowResizeState: ObservableObject {
    @Published private(set) var corner: WindowResizeCorner = .bottomRight
    fileprivate var isDragging = false

    fileprivate func update(windowMidX: CGFloat, displayMidX: CGFloat) {
        guard !isDragging else { return }
        let newCorner: WindowResizeCorner = windowMidX >= displayMidX ? .bottomLeft : .bottomRight
        if corner != newCorner {
            corner = newCorner
        }
    }
}

private final class FloatingPanel: NSPanel {
    static let initialSize = NSSize(width: 420, height: 510)
    static let minimumSize = NSSize(width: 360, height: 330)

    let resizeState = WindowResizeState()

    override var canBecomeKey: Bool { true }

    var activeDisplay: NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? screen
    }

    func updateResizeCorner() {
        guard let display = activeDisplay else { return }
        resizeState.update(windowMidX: frame.midX, displayMidX: display.visibleFrame.midX)
    }

    static func fittingSize(_ proposed: NSSize, within limit: NSSize) -> NSSize {
        NSSize(
            width: min(max(proposed.width, minimumSize.width), limit.width),
            height: min(max(proposed.height, minimumSize.height), limit.height)
        )
    }

    static func screenAtTopLeft(of frame: NSRect) -> NSScreen? {
        let corner = NSPoint(x: frame.minX + 1, y: frame.maxY - 1)
        return NSScreen.screens.first { $0.frame.contains(corner) }
    }
}

struct WindowResizeRegion: NSViewRepresentable {
    let corner: WindowResizeCorner

    func makeNSView(context: Context) -> NSView {
        let view = ResizeView()
        view.corner = corner
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ResizeView)?.corner = corner
    }

    private final class ResizeView: NSView {
        private struct Drag {
            let corner: WindowResizeCorner
            let pointer: NSPoint
            let initialSize: NSSize
            let anchor: NSPoint
            let sizeLimit: NSSize
        }

        private var drag: Drag?
        var corner: WindowResizeCorner = .bottomRight {
            didSet {
                if oldValue != corner {
                    window?.invalidateCursorRects(for: self)
                }
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let panel = window as? FloatingPanel, let screen = panel.activeDisplay else { return }

            let bounds = screen.visibleFrame
            let minimum = FloatingPanel.fittingSize(FloatingPanel.minimumSize, within: bounds.size)
            let fixedX: CGFloat
            let maxWidth: CGFloat
            switch corner {
            case .bottomLeft:
                fixedX = max(bounds.minX + minimum.width, min(panel.frame.maxX, bounds.maxX))
                maxWidth = fixedX - bounds.minX
            case .bottomRight:
                fixedX = max(bounds.minX, min(panel.frame.minX, bounds.maxX - minimum.width))
                maxWidth = bounds.maxX - fixedX
            }
            let top = max(bounds.minY + minimum.height, min(panel.frame.maxY, bounds.maxY))
            panel.resizeState.isDragging = true
            drag = Drag(
                corner: corner,
                pointer: panel.convertPoint(toScreen: event.locationInWindow),
                initialSize: panel.frame.size,
                anchor: NSPoint(x: fixedX, y: top),
                sizeLimit: NSSize(width: maxWidth, height: top - bounds.minY)
            )
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let drag else { return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            let deltaX = pointer.x - drag.pointer.x
            let isLeftCorner = drag.corner == .bottomLeft
            let proposedSize = NSSize(
                width: drag.initialSize.width + (isLeftCorner ? -deltaX : deltaX),
                height: drag.initialSize.height + drag.pointer.y - pointer.y
            )
            let size = FloatingPanel.fittingSize(proposedSize, within: drag.sizeLimit)
            let origin = NSPoint(x: drag.anchor.x - (isLeftCorner ? size.width : 0), y: drag.anchor.y - size.height)
            let frame = NSRect(origin: origin, size: size)
            if window.frame != frame {
                window.setFrame(frame, display: true)
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard let panel = window as? FloatingPanel, drag != nil else { return }
            drag = nil
            panel.resizeState.isDragging = false
            panel.updateResizeCorner()
        }

        override func resetCursorRects() {
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition = corner == .bottomLeft ? .bottomLeft : .bottomRight
                addCursorRect(bounds, cursor: .frameResize(position: position, directions: .all))
            } else {
                addCursorRect(bounds, cursor: .openHand)
            }
        }
    }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
