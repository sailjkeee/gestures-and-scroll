import AppKit
import Combine
import SwiftUI

final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = InputController()
    private var item: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var languageSubscription: AnyCancellable?
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        languageSubscription = controller.$profile.map(\.language).removeDuplicates().sink { [weak self] language in
            self?.updateLanguage(language)
        }

        controller.start()
        if controller.defaults.string(forKey: "LastOpenedVersion") != version {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let profile = controller.profile
        let language = profile.language
        menu.removeAllItems()
        let scrolling = NSMenuItem(
            title: language.text("Control scrolling", "Управлять прокруткой"),
            action: #selector(toggleScrolling), keyEquivalent: "")
        scrolling.target = self
        scrolling.state = profile.scrollingEnabled ? .on : .off
        menu.addItem(scrolling)

        let gestures = NSMenuItem(
            title: language.text("Trackpad gestures", "Жесты трекпада"),
            action: #selector(toggleGestures), keyEquivalent: "")
        gestures.target = self
        gestures.state = profile.gesturesEnabled ? .on : .off
        menu.addItem(gestures)
        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: language.text("Settings…", "Настройки…"), action: #selector(showSettings),
            keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: language.text("Quit", "Выйти"), action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func updateLanguage(_ language: InterfaceLanguage) {
        settingsWindow?.title = language.appName
        if let button = item?.button {
            let icon = NSImage(systemSymbolName: "trackpad", accessibilityDescription: language.appName)
                ?? NSImage(systemSymbolName: "hand.tap", accessibilityDescription: language.appName)
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = language.appName
            button.setAccessibilityLabel(language.appName)
        }
    }

    @objc private func toggleScrolling() {
        controller.profile.scrollingEnabled.toggle()
    }

    @objc private func toggleGestures() {
        controller.profile.gesturesEnabled.toggle()
    }

    @objc private func showSettings() {
        let window = settingsWindow ?? makeWindow()
        controller.defaults.set(version, forKey: "LastOpenedVersion")
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 610, height: 570),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = controller.profile.language.appName
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
        window.contentMinSize = NSSize(width: 540, height: 430)
        window.center()
        settingsWindow = window
        return window
    }
}
