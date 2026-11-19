#if DEBUG
import AppKit
import CurtainKit

final class UIPreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [AnyObject] = []
    private var windows: [NSWindow] = []
    private var dashboard: DashboardViewController?
    private var statusItems: [NSStatusItem] = []
    private var previewSession: PresentationPreviewSession?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["CURTAIN_UI_PREVIEW_DARK"] == "1" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if ProcessInfo.processInfo.environment["CURTAIN_UI_PREVIEW_LIGHT"] == "1" {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        NSApp.activate(ignoringOtherApps: true)
        let mode = ProcessInfo.processInfo.environment["CURTAIN_UI_PREVIEW"] ?? "settings"
        switch mode {
        case "permission":
            showPermissionWindow()
        case "companion":
            showPermissionCompanion()
        case "onboarding":
            showOnboarding()
        case "dashboard":
            showDashboard()
        case "menubar":
            showMenuBarIcons()
        case "capture-probe":
            showCaptureProbe()
        case "presentation":
            showPresentation()
        case "preview-session":
            showPreviewSession()
        default:
            let page = Int(mode.split(separator: "-").last ?? "0") ?? 0
            showSettings(page: page)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showSettings(page: Int) {
        var config = CurtainConfig.default
        if let image = ProcessInfo.processInfo.environment[
            "CURTAIN_UI_PREVIEW_PRESENTATION_IMAGE"
        ] {
            config.presentationModeEnabled = true
            config.presentationImagePath = image
            config.presentationClockStyle = PresentationClockStyle.storedValue(
                ProcessInfo.processInfo.environment[
                    "CURTAIN_UI_PREVIEW_CLOCK_STYLE"
                ] ?? config.presentationClockStyle
            ).rawValue
            let environment = ProcessInfo.processInfo.environment
            if let raw = environment["CURTAIN_UI_PREVIEW_FOCUS_X"],
               let value = Double(raw) {
                config.presentationFocusX = value
            }
            if let raw = environment["CURTAIN_UI_PREVIEW_FOCUS_Y"],
               let value = Double(raw) {
                config.presentationFocusY = value
            }
            if let raw = environment["CURTAIN_UI_PREVIEW_ZOOM"],
               let value = Double(raw) {
                config.presentationZoom = value
            }
            if let raw = environment["CURTAIN_UI_PREVIEW_DIM"],
               let value = Double(raw) {
                config.presentationDim = value
            }
        }
        let controller = SettingsWindowController(config: config)
        controllers.append(controller)
        if let rawSize = ProcessInfo.processInfo.environment[
            "CURTAIN_UI_PREVIEW_SIZE"
        ] {
            let parts = rawSize.lowercased().split(separator: "x")
            if parts.count == 2,
               let width = Double(parts[0]),
               let height = Double(parts[1]) {
                controller.window?.setContentSize(
                    NSSize(width: width, height: height)
                )
            }
        }
        controller.show()
        controller.previewSelectPage(page)
        if let raw = ProcessInfo.processInfo.environment[
            "CURTAIN_UI_PREVIEW_SCENE"
        ], let scene = CurtainScene(rawValue: raw) {
            controller.previewSelectScene(scene)
        }
        if ProcessInfo.processInfo.environment[
            "CURTAIN_UI_PREVIEW_DIRTY"
        ] == "1" {
            controller.previewSetDirty()
        }
        report("settings-\(page)", window: controller.window)
    }

    private func showPermissionWindow() {
        showPermissionCompanion()
    }

    private func showPermissionCompanion() {
        let model = PermissionStatusModel()
        let controller = PermissionCompanionWindowController(
            model: model,
            onOpen: { _ in }
        )
        controllers.append(controller)
        controller.show()
        report("companion", window: controller.window)
    }

    private func showOnboarding() {
        let controller = OnboardingWindowController(hotkey: "⌃⌥⌘C")
        controllers.append(controller)
        controller.show()
        if let raw = ProcessInfo.processInfo.environment[
            "CURTAIN_UI_PREVIEW_STEP"
        ], let step = Int(raw) {
            controller.previewStep(step)
        }
        report("onboarding", window: controller.window)
    }

    private func showDashboard() {
        let missingPermissions = ProcessInfo.processInfo.environment[
            "CURTAIN_UI_PREVIEW_MISSING"
        ] == "1"
        let isIdle = ProcessInfo.processInfo.environment[
            "CURTAIN_UI_PREVIEW_STATE"
        ] == "idle"
        let snapshot = DashboardSnapshot(
            curtainState: isIdle ? .idle : .active,
            recording: false,
            hotkey: "⌃⌥⌘C",
            elapsed: isIdle ? "00:00" : "00:42:17",
            scene: isIdle ? nil : .away,
            sceneMinutes: Dictionary(
                uniqueKeysWithValues: CurtainScene.allCases.map {
                    ($0, $0.defaultProtectionMinutes)
                }
            ),
            scenePresentationLabels: Dictionary(
                uniqueKeysWithValues: CurtainScene.allCases.map { scene in
                    let profile = scene.defaultProfile
                    return (
                        scene,
                        profile.usesPresentation
                            ? (profile.message.isEmpty ? "展示" : profile.message)
                            : "黑幕"
                    )
                }
            ),
            sceneHotkeys: Dictionary(
                uniqueKeysWithValues: CurtainScene.allCases.map {
                    ($0, $0.defaultHotkey.displayString)
                }
            ),
            protectionRemaining: isIdle ? nil : "01:17:43",
            presentationLabel: "时钟",
            hasAccessibility: !missingPermissions,
            hasScreenRecording: !missingPermissions,
            version: "0.9.0"
        )
        let controller = DashboardViewController(
            provider: { snapshot },
            actions: DashboardActions(
                toggle: {},
                activateScene: { _ in },
                quickProtect: { _ in },
                stopRecording: {},
                permissions: {},
                settings: {},
                quit: {}
            )
        )
        dashboard = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentViewController = controller
        window.center()
        window.makeKeyAndOrderFront(nil)
        controller.start()
        window.setContentSize(controller.preferredPopoverSize)
        window.center()
        windows.append(window)
        report("dashboard", window: window)
    }

    private func showMenuBarIcons() {
        let variants: [(Bool, Bool, Bool, String)] = [
            (false, false, false, "Curtain：待命"),
            (true, false, false, "Curtain：幕帘已开启"),
            (true, true, false, "Curtain：等待 Touch ID"),
            (false, false, true, "Curtain：正在录制"),
        ]
        for (on, auth, recording, tooltip) in variants {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = CurtainGlyph.image(
                size: 18,
                curtainOn: on,
                authenticating: auth,
                recording: recording
            )
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = tooltip
            statusItems.append(item)
        }
        print("PREVIEW_MENUBAR \(statusItems.count)")
        fflush(stdout)
    }

    private func showCaptureProbe() {
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 180, height: 180)
        let origin = NSPoint(
            x: screen.frame.midX - size.width - 20,
            y: screen.frame.midY - size.height / 2
        )
        let excluded = makeProbeWindow(
            frame: NSRect(origin: origin, size: size),
            color: .systemPink,
            title: "NONE",
            sharingType: .none
        )
        let visible = makeProbeWindow(
            frame: NSRect(
                origin: NSPoint(x: origin.x + size.width + 40, y: origin.y),
                size: size
            ),
            color: .systemGreen,
            title: "READ",
            sharingType: .readOnly
        )
        windows.append(contentsOf: [excluded, visible])
        for window in [excluded, visible] {
            window.orderFrontRegardless()
        }
        print("CAPTURE_PROBE_READY \(excluded.windowNumber) \(visible.windowNumber)")
        fflush(stdout)
    }

    private func showPresentation() {
        let environment = ProcessInfo.processInfo.environment
        let style = PresentationClockStyle.storedValue(
            environment["CURTAIN_UI_PREVIEW_CLOCK_STYLE"] ?? "digital"
        )
        let imagePath = environment["CURTAIN_UI_PREVIEW_IMAGE"]
        let width = Double(environment["CURTAIN_UI_PREVIEW_WIDTH"] ?? "") ?? 1440
        let height = Double(environment["CURTAIN_UI_PREVIEW_HEIGHT"] ?? "") ?? 900
        let now = Date()
        let image = imagePath.flatMap {
            PresentationBackgroundLoader.load(path: $0, maxPixelSize: max(width, height) * 2)
        }
        let canvas = PresentationCanvasView(
            color: .black,
            image: image,
            clockStyle: style,
            status: PresentationClockFormatter.status(
                at: now,
                startedAt: now.addingTimeInterval(-42 * 60 - 17)
            )
        )
        if environment["CURTAIN_UI_PREVIEW_RETURN_HINT"] == "1" {
            canvas.showReturnHint("双击或长按 Esc，再用 Touch ID 解锁")
        }
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.contentView = canvas
        window.center()
        window.orderFrontRegardless()
        windows.append(window)
        report("presentation", window: window)
    }

    private func showPreviewSession() {
        let environment = ProcessInfo.processInfo.environment
        let style = PresentationClockStyle.storedValue(
            environment["CURTAIN_UI_PREVIEW_CLOCK_STYLE"] ?? "digital"
        )
        let imagePath = environment["CURTAIN_UI_PREVIEW_IMAGE"]
        let duration = Double(
            environment["CURTAIN_UI_PREVIEW_DURATION"] ?? ""
        ) ?? 4
        let screens = ScreenInventory.current()
        let session = PresentationPreviewSession()
        session.allowsScreenCapture =
            environment["CURTAIN_UI_PREVIEW_ALLOW_CAPTURE"] == "1"
        previewSession = session
        let error = session.start(
            screens: screens,
            configuration: PresentationPreviewConfiguration(
                color: .black,
                imagePath: imagePath,
                clockStyle: style,
                duration: duration
            ),
            completion: { result in
                switch result {
                case .success:
                    print("PREVIEW_SESSION_FINISHED")
                case .failure(let error):
                    print("PREVIEW_SESSION_FAILED \(error.message)")
                }
                fflush(stdout)
                NSApp.terminate(nil)
            }
        )
        if let error {
            print("PREVIEW_SESSION_START_FAILED \(error.message)")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        for screen in screens {
            print(
                "PREVIEW_SESSION_SCREEN \(screen.displayID) \(screen.frame) scale=\(screen.scale)"
            )
        }
        print("PREVIEW_SESSION_STARTED \(screens.count) screens")
        fflush(stdout)
    }

    private func makeProbeWindow(frame: NSRect,
                                 color: NSColor,
                                 title: String,
                                 sharingType: NSWindow.SharingType) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = color
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.sharingType = sharingType
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 30, weight: .bold)
        label.textColor = .black
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        window.contentView = content
        return window
    }

    private func report(_ name: String, window: NSWindow?) {
        guard let window else {
            print("PREVIEW_WINDOW \(name) 0")
            return
        }
        print("PREVIEW_WINDOW \(name) \(window.windowNumber)")
        print("PREVIEW_FRAME \(name) \(window.frame) \(window.minSize) \(window.contentView?.frame ?? .zero)")
        fflush(stdout)
        captureIfRequested(name: name, window: window)
    }

    private func captureIfRequested(name: String, window: NSWindow) {
        guard let path = ProcessInfo.processInfo.environment["CURTAIN_UI_PREVIEW_CAPTURE"] else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            window.contentView?.layoutSubtreeIfNeeded()
            guard let view = window.contentView, !view.bounds.isEmpty,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                print("PREVIEW_CAPTURE_FAILED \(name)")
                fflush(stdout)
                return
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                print("PREVIEW_CAPTURE_FAILED \(name)")
                fflush(stdout)
                return
            }
            do {
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                print("PREVIEW_CAPTURE \(name) \(path)")
                fflush(stdout)
            } catch {
                print("PREVIEW_CAPTURE_FAILED \(name) \(error)")
                fflush(stdout)
            }
            if ProcessInfo.processInfo.environment["CURTAIN_UI_PREVIEW_CAPTURE_EXIT"] == "1" {
                NSApp.terminate(nil)
            }
        }
    }
}
#endif
