import Foundation

enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable {
    case system, en, ru

    var id: Self { self }

    func usesRussian(preferredLanguages: [String] = Locale.preferredLanguages) -> Bool {
        switch self {
        case .ru: return true
        case .en: return false
        case .system:
            return preferredLanguages.first?.lowercased().split(whereSeparator: {
                $0 == "-" || $0 == "_"
            }).first == "ru"
        }
    }

    func text(_ english: String, _ russian: String) -> String {
        usesRussian() ? russian : english
    }

    var appName: String { text("Gestures & Scroll", "Жесты и прокрутка") }
}

enum ScrollMode: String, Codable, CaseIterable, Identifiable {
    case natural, classic, system

    var id: Self { self }

    func label(_ language: InterfaceLanguage) -> String {
        switch self {
        case .natural: return language.text("Natural", "Естественная")
        case .classic: return language.text("Classic", "Классическая")
        case .system: return language.text("Follow macOS", "Как в macOS")
        }
    }

    func reverses(systemIsNatural: Bool) -> Bool {
        switch self {
        case .natural: return !systemIsNatural
        case .classic: return systemIsNatural
        case .system: return false
        }
    }
}

enum GestureMotion: String, CaseIterable {
    case tap, up, down, left, right

    var symbol: String {
        switch self {
        case .tap: return "hand.tap"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        }
    }

    func label(_ language: InterfaceLanguage) -> String {
        switch self {
        case .tap: return language.text("Tap", "Касание")
        case .up: return language.text("Swipe up", "Свайп вверх")
        case .down: return language.text("Swipe down", "Свайп вниз")
        case .left: return language.text("Swipe left", "Свайп влево")
        case .right: return language.text("Swipe right", "Свайп вправо")
        }
    }
}

struct TrackpadGesture: Equatable {
    let fingers: Int
    let motion: GestureMotion

    var key: String { "\(fingers)-\(motion.rawValue)" }

    func label(_ language: InterfaceLanguage) -> String {
        guard language.usesRussian() else { return "\(fingers)-finger \(motion.label(language).lowercased())" }
        let count = fingers == 3 ? "тремя" : "четырьмя"
        return "\(motion.label(language)) \(count) пальцами"
    }
}

enum GestureAction: String, Codable, CaseIterable, Identifiable {
    case none, copy, paste, cut, undo, redo, selectAll, missionControl, closeWindow, quitApp, minimize
    case openApplication

    var id: Self { self }

    func label(_ language: InterfaceLanguage) -> String {
        switch self {
        case .none: return language.text("No action", "Без действия")
        case .copy: return language.text("Copy", "Копировать")
        case .paste: return language.text("Paste", "Вставить")
        case .cut: return language.text("Cut", "Вырезать")
        case .undo: return language.text("Undo", "Отменить")
        case .redo: return language.text("Redo", "Повторить")
        case .selectAll: return language.text("Select All", "Выделить всё")
        case .missionControl: return "Mission Control"
        case .closeWindow: return language.text("Close Window", "Закрыть окно")
        case .quitApp: return language.text("Quit App", "Выйти из приложения")
        case .minimize: return language.text("Minimize Window", "Свернуть окно")
        case .openApplication: return language.text("Open Application…", "Открыть приложение…")
        }
    }
}

struct InputProfile: Codable, Equatable {
    var language: InterfaceLanguage = .system
    var scrollingEnabled = true
    var gesturesEnabled = true
    var mouseDirection: ScrollMode = .classic
    var trackpadDirection: ScrollMode = .natural
    var matchHorizontal = true
    var fixedWheel = true
    var wheelLines = 3
    var actions: [String: GestureAction] = [
        TrackpadGesture(fingers: 3, motion: .tap).key: .copy,
        TrackpadGesture(fingers: 4, motion: .tap).key: .paste,
        TrackpadGesture(fingers: 4, motion: .up).key: .missionControl
    ]
    private var storedDrawingSettings: DrawingSettings?

    var drawing: DrawingSettings {
        get { storedDrawingSettings ?? DrawingSettings() }
        set { storedDrawingSettings = newValue }
    }

    static let wheelRange = 1...12

    func action(for gesture: TrackpadGesture) -> GestureAction {
        actions[gesture.key] ?? .none
    }

    mutating func setAction(_ action: GestureAction, for gesture: TrackpadGesture) {
        actions[gesture.key] = (action == .none) ? nil : action
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: "InputProfile.v1"),
              var profile = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self()
        }
        profile.wheelLines = min(max(profile.wheelLines, wheelRange.lowerBound), wheelRange.upperBound)
        return profile
    }

    func store(in defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: "InputProfile.v1")
        }
    }
}
