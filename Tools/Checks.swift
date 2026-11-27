import AppKit
import CoreGraphics
import SwiftUI

@main
enum Checks {
    @MainActor static func main() throws {
        checkDefaults()
        checkGestures()
        checkDrawings()
        try checkApplicationAssignments()
        checkScrolling()
        precondition(GSTrackpadAPIAvailable(), "MultitouchSupport symbols unavailable on this Mac")
        print("Passed profile migration, localization, gestures, application assignments, scrolling, and native-symbol checks.")
        if CommandLine.arguments.count > 1 {
            try renderSettings(to: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
        }
    }

    static func checkDefaults() {
        let standard = InputProfile()
        let three = TrackpadGesture(fingers: 3, motion: .tap)
        let four = TrackpadGesture(fingers: 4, motion: .tap)
        let swipe = TrackpadGesture(fingers: 4, motion: .up)
        precondition(standard.scrollingEnabled && standard.gesturesEnabled)
        precondition(standard.mouseDirection == .classic && standard.trackpadDirection == .natural)
        precondition(standard.matchHorizontal && standard.fixedWheel && standard.wheelLines == 3)
        precondition(standard.action(for: three) == .copy && standard.action(for: four) == .paste)
        precondition(standard.action(for: swipe) == .missionControl)
        precondition(InterfaceLanguage.system.usesRussian(preferredLanguages: ["ru-RU"]))
        precondition(!InterfaceLanguage.system.usesRussian(preferredLanguages: ["en-US", "ru"]))
        precondition(three.label(.ru) == "Касание тремя пальцами")
        precondition(three.label(.en) == "3-finger tap")
        precondition(GestureAction.paste.label(.en) == "Paste" && GestureAction.paste.label(.ru) == "Вставить")

        var changed = standard
        changed.language = .ru
        changed.setAction(.none, for: four)
        changed.setAction(.undo, for: three)
        let data = try! JSONEncoder().encode(changed)
        let reloaded = try! JSONDecoder().decode(InputProfile.self, from: data)
        precondition(reloaded == changed && reloaded.action(for: four) == .none)

        // A version 1.0 profile has no drawing settings and keeps its user bindings.
        let oldProfile = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(oldProfile["storedDrawingSettings"] == nil)
        precondition(reloaded.action(for: three) == .undo)
        precondition(reloaded.drawing.enabled && reloaded.drawing.crossAction == .quitApp)
        precondition(reloaded.drawing.activation == .control)
    }

    static func checkDrawings() {
        func point(_ x: Double, _ y: Double) -> DrawingPoint {
            DrawingPoint(x: x, y: y)
        }
        let diagonal = [point(0.3, 0.2), point(0.5, 0.4), point(0.7, 0.6)]
        let otherDiagonal = [point(0.3, 0.6), point(0.5, 0.4), point(0.7, 0.2)]
        let cross = TrackpadDrawing(rawStrokes: [diagonal, otherDiagonal])!
        let reversed = TrackpadDrawing(rawStrokes: [Array(otherDiagonal.reversed()), diagonal])!
        precondition(cross.isCross && reversed.isCross)
        precondition(cross.distance(to: reversed) < 0.01)
        let vertical = [point(0.5, 0.15), point(0.5, 0.35), point(0.5, 0.55)]
        let horizontal = [point(0.25, 0.35), point(0.5, 0.35), point(0.75, 0.35)]
        let plus = TrackpadDrawing(rawStrokes: [vertical, horizontal])!
        precondition(plus.isCross)
        let below = [point(0.25, 0.16), point(0.5, 0.16), point(0.75, 0.16)]
        precondition(!TrackpadDrawing(rawStrokes: [vertical, below])!.isCross)
        precondition(!TrackpadDrawing(rawStrokes: [horizontal, below])!.isCross)
        precondition(TrackpadDrawing(rawStrokes: [[point(0, 0), point(0.01, 0.01), point(0.02, 0)]]) == nil)

        let angle = TrackpadDrawing(rawStrokes: [[point(0.3, 0.7), point(0.5, 0.3), point(0.7, 0.55)]])!
        let largerAngle = TrackpadDrawing(rawStrokes: [[point(0.1, 0.9), point(0.4, 0.3), point(0.7, 0.675)]])!
        let line = TrackpadDrawing(rawStrokes: [diagonal])!
        var profile = InputProfile()
        precondition(profile.drawing.match(cross) == .cross(DrawingAssignment(action: .quitApp)))
        precondition(profile.drawing.match(line) == nil)
        profile.drawing.custom.append(CustomDrawing(id: UUID(), name: "Angle", shape: angle, action: .minimize))
        precondition(profile.drawing.match(largerAngle) == .custom("Angle", DrawingAssignment(action: .minimize)))
        precondition(profile.drawing.match(line) == nil)
        profile.drawing.crossAction = .none
        profile.drawing.activation = .option
        precondition(profile.drawing.match(cross) == nil)
        let reloaded = try! JSONDecoder().decode(InputProfile.self, from: JSONEncoder().encode(profile))
        precondition(reloaded.drawing == profile.drawing)

        var capture = TrackpadDrawingCapture()
        var timestamp = 0.0
        func send(_ count: Int, _ x: Double = 0, _ y: Double = 0, armed: Bool = true) {
            timestamp += 0.03
            _ = capture.feed(ContactFrame(count: count, timestamp: timestamp, x: x, y: y, span: 0),
                             canBegin: armed)
        }
        send(1, 0.20, 0.12, armed: false)
        send(1, 0.35, 0.30)
        send(1, 0.52, 0.60)
        send(0)
        precondition(capture.takeDrawing() == nil)
        send(1, 0.20, 0.20)
        send(1, 0.35, 0.40)
        send(1, 0.50, 0.60)
        send(0)
        send(1, 0.20, 0.60)
        send(1, 0.35, 0.40)
        send(1, 0.50, 0.20)
        send(0)
        precondition(capture.takeDrawing()?.isCross == true)
        precondition(capture.takeDrawing() == nil)
        send(1, 0.20, 0.20)
        send(2)
        send(1, 0.35, 0.40)
        send(1, 0.50, 0.60)
        send(0)
        precondition(capture.takeDrawing() == nil)
    }

    static func checkApplicationAssignments() throws {
        let calculatorURL = URL(fileURLWithPath: "/System/Applications/Calculator.app").standardizedFileURL
        let calculator = DrawingApplication(url: calculatorURL)!
        precondition(calculator.resolvedURL { _ in nil } == calculatorURL)
        precondition(DrawingApplication(url: URL(fileURLWithPath: "/System/Applications")) == nil)

        // Simulate a stored path becoming stale and the OS finding the same app elsewhere.
        let oldReference = try JSONSerialization.data(withJSONObject: [
            "url": URL(fileURLWithPath: "/Applications/Former Location/Calculator.app").absoluteString,
            "bundleIdentifier": calculator.bundleIdentifier,
            "name": calculator.name
        ])
        let moved = try JSONDecoder().decode(DrawingApplication.self, from: oldReference)
        precondition(moved.resolvedURL { $0 == calculator.bundleIdentifier ? calculatorURL : nil } == calculatorURL)
        precondition(moved.resolvedURL { _ in nil } == nil)

        let rising = [DrawingPoint(x: 0.2, y: 0.2), DrawingPoint(x: 0.4, y: 0.4), DrawingPoint(x: 0.6, y: 0.6)]
        let falling = [DrawingPoint(x: 0.2, y: 0.6), DrawingPoint(x: 0.4, y: 0.4), DrawingPoint(x: 0.6, y: 0.2)]
        let line = TrackpadDrawing(rawStrokes: [rising])!
        let cross = TrackpadDrawing(rawStrokes: [rising, falling])!
        let launch = DrawingAssignment(action: .openApplication, application: calculator)
        precondition(!DrawingAssignment(action: .openApplication).isConfigured)
        var profile = InputProfile()
        profile.drawing.crossAssignment = launch
        profile.drawing.custom = [
            CustomDrawing(id: UUID(), name: "Calculator", shape: line,
                          action: launch.action, application: launch.application)
        ]
        let restored = try JSONDecoder().decode(InputProfile.self, from: JSONEncoder().encode(profile))
        precondition(restored.drawing.match(cross) == .cross(launch))
        precondition(restored.drawing.match(line) == .custom("Calculator", launch))
        profile.drawing.custom[0].assignment = DrawingAssignment(action: .copy)
        precondition(profile.drawing.custom[0].application == nil)
        precondition(profile.drawing.match(line) == .custom("Calculator", DrawingAssignment(action: .copy)))
    }

    static func checkGestures() {
        func frame(_ count: Int, _ timestamp: Double, x: Double = 0.5,
                   y: Double = 0.5, span: Double = 0.33) -> ContactFrame {
            ContactFrame(count: count, timestamp: timestamp, x: x, y: y, span: span)
        }
        func detect(_ frames: ContactFrame...) -> [TrackpadGesture] {
            var recognizer = TrackpadRecognizer()
            return frames.compactMap { recognizer.ingest($0) }
        }
        precondition(detect(frame(1, 0), frame(3, 0.02), frame(3, 0.07, x: 0.51),
                            frame(2, 0.08, x: 0.57), frame(0, 0.09)) ==
                     [TrackpadGesture(fingers: 3, motion: .tap)])
        precondition(detect(frame(3, 0), frame(4, 0.03), frame(4, 0.08), frame(0, 0.11),
                            frame(4, 0.23), frame(4, 0.28), frame(0, 0.3)) ==
                     Array(repeating: TrackpadGesture(fingers: 4, motion: .tap), count: 2))
        precondition(detect(frame(4, 0), frame(4, 0.18, y: 0.69), frame(3, 0.19), frame(0, 0.2)) ==
                     [TrackpadGesture(fingers: 4, motion: .up)])
        precondition(detect(frame(3, 0), frame(3, 0.16, x: 0.32), frame(0, 0.2)) ==
                     [TrackpadGesture(fingers: 3, motion: .left)])
        precondition(detect(frame(3, 0), frame(3, 0.17, y: 0.33), frame(0, 0.19)) ==
                     [TrackpadGesture(fingers: 3, motion: .down)])
        precondition(detect(frame(3, 0), frame(3, 0.14, x: 0.65), frame(0, 0.18)) ==
                     [TrackpadGesture(fingers: 3, motion: .right)])

        precondition(detect(frame(5, 0), frame(4, 0.08), frame(0, 0.1)).isEmpty)
        precondition(detect(frame(2, 0), frame(2, 0.08, y: 0.68), frame(0, 0.1)).isEmpty)
        precondition(detect(frame(1, 0), frame(3, 0.22), frame(3, 0.26), frame(0, 0.28)).isEmpty)
        precondition(detect(frame(3, 0), frame(3, 0.36), frame(0, 0.4)).isEmpty)
        precondition(detect(frame(3, 0), frame(3, 0.08, span: 0.48), frame(0, 0.12)).isEmpty)
        precondition(detect(frame(3, 0), frame(3, 0.08, x: 0.65, y: 0.66), frame(0, 0.12)).isEmpty)
        precondition(detect(frame(4, 0), frame(4, 0.05), frame(3, 0.07), frame(4, 0.09),
                            frame(4, 0.12), frame(0, 0.14)).isEmpty)
        precondition(detect(frame(3, 0), frame(3, 0.07), frame(-1, 0.08), frame(0, 0.09)).isEmpty)
    }

    static func checkScrolling() {
        func scrollEvent(_ vertical: Int32, _ horizontal: Int32) -> CGEvent {
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                    wheel1: vertical, wheel2: horizontal, wheel3: 0)!
        }
        let engine = ScrollEngine()
        let first = scrollEvent(1, -1)
        engine.transform(first, isTrackpad: false, isContinuous: false, systemIsNatural: true)
        precondition(first.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3)
        precondition(first.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 3)

        let second = scrollEvent(1, -1)
        engine.transform(second, isTrackpad: true, isContinuous: true, systemIsNatural: true)
        precondition(second.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1)
        precondition(second.getIntegerValueField(.scrollWheelEventDeltaAxis2) == -1)

        engine.profile.fixedWheel = false
        engine.profile.matchHorizontal = false
        let third = scrollEvent(2, 2)
        let originalPoint = third.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let originalFixed = third.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let result = engine.transform(third, isTrackpad: true, isContinuous: true, systemIsNatural: false)
        precondition(result.vertical && !result.horizontal)
        precondition(third.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -2)
        precondition(third.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 2)
        precondition(third.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -originalPoint)
        precondition(third.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -originalFixed)
    }

    @MainActor static func renderSettings(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        for (language, pane, rect, dark, filename) in [
            (InterfaceLanguage.ru, SettingsPane.scrolling, NSRect(x: 0, y: 0, width: 610, height: 570),
             false, "scrolling-ru.png"),
            (.ru, .gestures, NSRect(x: 0, y: 0, width: 610, height: 570), false, "gestures-ru.png"),
            (.ru, .drawings, NSRect(x: 0, y: 0, width: 610, height: 570), false, "drawings-ru.png"),
            (.en, .drawings, NSRect(x: 0, y: 0, width: 540, height: 430), true, "drawings-en-dark.png")
        ] {
            let controller = InputController(live: false)
            controller.profile.language = language
            if pane == .drawings, let application = DrawingApplication(
                url: URL(fileURLWithPath: "/System/Applications/Calculator.app")) {
                controller.profile.drawing.crossAssignment = DrawingAssignment(
                    action: .openApplication, application: application)
            }
            let view = SettingsView(controller: controller, pane: pane, fingers: 4)
                .frame(width: rect.width, height: rect.height)
                .environment(\.colorScheme, dark ? .dark : .light)
            let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = rect
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: folder.appendingPathComponent(filename))
        }
        print("Rendered Russian and English settings.")
    }
}
