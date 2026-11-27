import AppKit

let application = NSApplication.shared
let delegate = ApplicationDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
withExtendedLifetime(delegate) {
    application.run()
}
