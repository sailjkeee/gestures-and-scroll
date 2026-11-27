import AppKit
import ApplicationServices
import Carbon
import Combine

private final class TrackpadReader {
    private static weak var active: TrackpadReader?
    private static var nextGeneration: UInt64 = 0
    private static let receiveFrame: GSTouchObserver = { sample in
        DispatchQueue.main.async {
            TrackpadReader.active?.process(sample)
        }
    }

    var onGesture: ((TrackpadGesture) -> Void)?
    var onFrame: ((ContactFrame) -> Void)?
    private var generation: UInt64 = 0
    private var recognizers: [UInt64: TrackpadRecognizer] = [:]

    func start() -> Bool {
        if Self.active === self { return true }
        Self.nextGeneration &+= 1
        generation = Self.nextGeneration
        guard GSStartTrackpadFeed(Self.receiveFrame, generation) > 0 else { return false }
        Self.active = self
        return true
    }

    func stop() {
        guard Self.active === self else { return }
        Self.active = nil
        GSStopTrackpadFeed()
        recognizers.removeAll()
    }

    private func process(_ sample: GSTouchSample) {
        guard sample.generation == generation else { return }
        let frame = ContactFrame(
            count: Int(sample.count), timestamp: sample.timestamp,
            x: sample.x, y: sample.y, span: sample.span)
        onFrame?(frame)
        if let gesture = recognizers[sample.deviceID, default: TrackpadRecognizer()].ingest(frame) {
            onGesture?(gesture)
        }
    }
}

enum DrawingDraft: Equatable {
    case idle, capturing, ready(TrackpadDrawing), tryAgain
}

enum FeatureStatus: Equatable {
    case enabled, paused, permissionRequired, alreadyManaged(String), unavailable

    func label(_ language: InterfaceLanguage) -> String {
        switch self {
        case .enabled: return language.text("Active", "Активно")
        case .paused: return language.text("Off", "Выключено")
        case .permissionRequired: return language.text("Permission required", "Нужно разрешение")
        case .alreadyManaged(let app):
            return language.text("Quit \(app) to use these controls.", "Закрой \(app), чтобы применить эти настройки.")
        case .unavailable: return language.text("Unavailable", "Недоступно")
        }
    }
}

final class InputController: ObservableObject {
    let defaults: UserDefaults
    @Published var profile: InputProfile {
        didSet {
            guard oldValue != profile else { return }
            if live { profile.store(in: defaults) }
            scroll.profile = profile
            if oldValue.scrollingEnabled != profile.scrollingEnabled ||
               oldValue.gesturesEnabled != profile.gesturesEnabled {
                refresh()
            }
            if oldValue.drawing.enabled != profile.drawing.enabled ||
                oldValue.drawing.activation != profile.drawing.activation {
                resetDrawingCapture()
            }
        }
    }
    @Published private(set) var authorized = false
    @Published private(set) var scrollStatus: FeatureStatus = .permissionRequired
    @Published private(set) var gestureStatus: FeatureStatus = .permissionRequired
    @Published private(set) var lastGesture: TrackpadGesture?
    @Published private(set) var lastDrawing: DrawingMatch?
    @Published private(set) var drawingDraft: DrawingDraft = .idle
    @Published private(set) var applicationLaunchFailure: String?

    private let live: Bool
    private let scroll = ScrollEngine()
    private let trackpad = TrackpadReader()
    private var poll: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var drawingCapture = TrackpadDrawingCapture()
    private var drawingTimer: Timer?
    private var drawingTarget: pid_t?

    init(defaults: UserDefaults = .standard, live: Bool = true) {
        self.defaults = defaults
        self.live = live
        profile = live ? InputProfile.load(from: defaults) : InputProfile()
        scroll.profile = profile
        trackpad.onGesture = { [weak self] in self?.handle($0) }
        trackpad.onFrame = { [weak self] in self?.handleDrawingFrame($0) }
    }

    func start() {
        guard live, poll == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        poll = timer
        RunLoop.main.add(timer, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scroll.stop()
            self?.trackpad.stop()
            self?.refresh()
        }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        scroll.stop()
        trackpad.stop()
        resetDrawingCapture()
    }

    func requestPermission() {
        guard live else { return }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([key: true] as CFDictionary) {
            refresh()
        } else if let page = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(page)
        }
    }

    private func refresh() {
        guard live else { return }
        let trusted = AXIsProcessTrusted()
        if authorized != trusted { authorized = trusted }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let scrollStatus = gate(
            enabled: profile.scrollingEnabled, trusted: trusted,
            competingApp: running.contains("com.pilotmoon.scroll-reverser") ? "Scroll Reverser" : nil)
        if let scrollStatus {
            scroll.stop()
            setScrollStatus(scrollStatus)
        } else {
            setScrollStatus(scroll.start() ? .enabled : .unavailable)
        }

        let gestureStatus = gate(
            enabled: profile.gesturesEnabled, trusted: trusted,
            competingApp: running.contains("com.turhe123.trackpadgesturemap") ? "TrackpadGestureMap" : nil)
        if let gestureStatus {
            trackpad.stop()
            setGestureStatus(gestureStatus)
        } else {
            setGestureStatus(trackpad.start() ? .enabled : .unavailable)
        }
    }

    private func gate(enabled: Bool, trusted: Bool, competingApp: String?) -> FeatureStatus? {
        if !enabled { return .paused }
        if !trusted { return .permissionRequired }
        if let competingApp { return .alreadyManaged(competingApp) }
        return nil
    }

    private func setScrollStatus(_ status: FeatureStatus) {
        if scrollStatus != status { scrollStatus = status }
    }

    private func setGestureStatus(_ status: FeatureStatus) {
        if gestureStatus != status {
            gestureStatus = status
            if status != .enabled {
                lastGesture = nil
                lastDrawing = nil
                resetDrawingCapture()
            }
        }
    }

    private func handle(_ gesture: TrackpadGesture) {
        guard gestureStatus == .enabled else { return }
        lastGesture = gesture
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        run(profile.action(for: gesture), gesture: gesture)
    }

    func beginDrawingRecording() {
        guard gestureStatus == .enabled else { return }
        resetDrawingCapture()
        drawingDraft = .capturing
    }

    func cancelDrawingRecording() {
        resetDrawingCapture()
    }

    func saveDrawing(name: String, assignment: DrawingAssignment) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, assignment.isConfigured, case .ready(let shape) = drawingDraft else { return }
        profile.drawing.custom.append(
            CustomDrawing(id: UUID(), name: name, shape: shape,
                          action: assignment.action, application: assignment.application))
        resetDrawingCapture()
    }

    private func resetDrawingCapture() {
        drawingTimer?.invalidate()
        drawingTimer = nil
        drawingCapture.reset()
        drawingTarget = nil
        if drawingDraft != .idle { drawingDraft = .idle }
    }

    private func handleDrawingFrame(_ frame: ContactFrame) {
        guard gestureStatus == .enabled else { return }
        let recording = drawingDraft == .capturing
        var canStart = false
        var appID: pid_t?
        if frame.count == 1 && drawingCapture.canBeginStroke {
            if recording {
                canStart = NSApp.isActive
            } else if drawingDraft == .idle && profile.drawing.enabled && drawingKeyIsPressed() {
                let frontmost = NSWorkspace.shared.frontmostApplication
                if let frontmost {
                    appID = frontmost.processIdentifier
                    canStart = true
                }
            }
            if let drawingTarget, let appID, drawingTarget != appID {
                resetDrawingCapture()
            }
        }
        switch drawingCapture.feed(frame, canBegin: canStart) {
        case .started:
            drawingTimer?.invalidate()
            drawingTimer = nil
            drawingTarget = appID
        case .singleStroke:
            let timer = Timer(timeInterval: 0.62, repeats: false) { [weak self] _ in self?.finishDrawing() }
            drawingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .twoStrokes:
            finishDrawing()
        case .cancelled:
            resetDrawingCapture()
            if recording { drawingDraft = .tryAgain }
        case .none:
            break
        }
    }

    private func drawingKeyIsPressed() -> Bool {
        let activation = profile.drawing.activation
        if activation == .noKey { return true }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(activation == .control ? .maskControl : .maskAlternate)
    }

    private func finishDrawing() {
        drawingTimer?.invalidate()
        drawingTimer = nil
        let captured = drawingCapture.takeDrawing()
        defer { drawingTarget = nil }
        if drawingDraft == .capturing {
            drawingDraft = captured.map(DrawingDraft.ready) ?? .tryAgain
            return
        }
        guard profile.drawing.enabled, let captured,
              let match = profile.drawing.match(captured) else { return }
        lastDrawing = match
        guard let drawingTarget, let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == drawingTarget else { return }
        let assignment = match.assignment
        if assignment.action == .openApplication, let application = assignment.application {
            openDrawingApplication(application)
        } else if frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            run(assignment.action)
        }
    }

    private func openDrawingApplication(_ application: DrawingApplication) {
        let workspace = NSWorkspace.shared
        guard let url = application.resolvedURL(findApplication: workspace.urlForApplication(withBundleIdentifier:))
        else {
            applicationLaunchFailure = application.name
            return
        }
        applicationLaunchFailure = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        workspace.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard error != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.applicationLaunchFailure = application.name
            }
        }
    }

    private func run(_ action: GestureAction, gesture: TrackpadGesture? = nil) {
        if action == .missionControl {
            if gesture?.fingers != 4 || gesture?.motion != .up || !systemOpensMissionControl() {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            }
        } else {
            postKeyboardAction(action)
        }
    }

    private func systemOpensMissionControl() -> Bool {
        let enabled = CFPreferencesCopyAppValue(
            "showMissionControlGestureEnabled" as CFString, "com.apple.dock" as CFString
        ) as? NSNumber
        let fourFingerSwipe = CFPreferencesCopyAppValue(
            "TrackpadFourFingerVertSwipeGesture" as CFString, "com.apple.AppleMultitouchTrackpad" as CFString
        ) as? NSNumber
        return enabled?.boolValue != false && fourFingerSwipe?.intValue == 2
    }

    private func postKeyboardAction(_ action: GestureAction) {
        let key: Int
        switch action {
        case .copy: key = kVK_ANSI_C
        case .paste: key = kVK_ANSI_V
        case .cut: key = kVK_ANSI_X
        case .undo, .redo: key = kVK_ANSI_Z
        case .selectAll: key = kVK_ANSI_A
        case .closeWindow: key = kVK_ANSI_W
        case .quitApp: key = kVK_ANSI_Q
        case .minimize: key = kVK_ANSI_M
        case .none, .missionControl, .openApplication: return
        }
        let flags: CGEventFlags = action == .redo ? [.maskCommand, .maskShift] : .maskCommand
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
