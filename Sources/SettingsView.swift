import SwiftUI

enum SettingsPane {
    case scrolling, gestures, drawings
}

struct SettingsView: View {
    @ObservedObject var controller: InputController
    private var pane: SwiftUI.State<SettingsPane>
    private var fingers: SwiftUI.State<Int>

    init(controller: InputController, pane: SettingsPane = .scrolling, fingers: Int = 3) {
        self.controller = controller
        self.pane = SwiftUI.State(initialValue: pane)
        self.fingers = SwiftUI.State(initialValue: fingers)
    }

    private var language: InterfaceLanguage { controller.profile.language }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !controller.authorized &&
                        (controller.profile.scrollingEnabled || controller.profile.gesturesEnabled) {
                        permissionNotice
                    }
                    switch pane.wrappedValue {
                    case .scrolling: scrollPane
                    case .gestures: gesturePane
                    case .drawings: DrawingSettingsView(controller: controller)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 16) {
                Text(language.appName)
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker(language.text("Language", "Язык"), selection: $controller.profile.language) {
                    Text(language.text("System language", "Язык macOS")).tag(InterfaceLanguage.system)
                    Text("English").tag(InterfaceLanguage.en)
                    Text("Русский").tag(InterfaceLanguage.ru)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 132)
            }
            Picker(language.text("Settings section", "Раздел настроек"), selection: pane.projectedValue) {
                Label(language.text("Scrolling", "Прокрутка"), systemImage: "arrow.up.arrow.down")
                    .tag(SettingsPane.scrolling)
                Label(language.text("Gestures", "Жесты"), systemImage: "hand.tap")
                    .tag(SettingsPane.gestures)
                Label(language.text("Drawings", "Рисование"), systemImage: "scribble")
                    .tag(SettingsPane.drawings)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 15)
        .padding(.bottom, 15)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var permissionNotice: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("Accessibility permission required", "Нужен доступ в «Универсальном доступе»"))
                    .fontWeight(.semibold)
                Text(language.text(
                    "Allow this app to change scrolling and send shortcuts.",
                    "Разреши приложению менять прокрутку и выполнять сочетания клавиш."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(language.text("Open Settings…", "Открыть настройки…")) {
                controller.requestPermission()
            }
            .fixedSize()
        }
        .padding(12)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }

    private var scrollPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureSwitch(
                language.text("Control scrolling", "Управлять прокруткой"),
                enabled: $controller.profile.scrollingEnabled, status: controller.scrollStatus)

            GroupBox {
                VStack(spacing: 0) {
                    directionRow(
                        language.text("Mouse", "Мышь"), symbol: "computermouse",
                        selection: $controller.profile.mouseDirection)
                    Divider()
                    directionRow(
                        language.text("Trackpad", "Трекпад"), symbol: "rectangle",
                        selection: $controller.profile.trackpadDirection)
                    Divider()
                    Toggle(
                        language.text("Match horizontal direction to vertical", "Применять направление и к горизонтальной прокрутке"),
                        isOn: $controller.profile.matchHorizontal)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                }
            } label: {
                Text(language.text("Direction", "Направление"))
            }

            GroupBox {
                VStack(spacing: 0) {
                    Toggle(
                        language.text("Fixed scroll step", "Фиксированный шаг прокрутки"),
                        isOn: $controller.profile.fixedWheel)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    Divider()
                    HStack {
                        Text(language.text("Per wheel notch", "За одно деление колеса"))
                        Spacer()
                        Text(lineCount).monospacedDigit()
                        Stepper(
                            language.text("Lines per wheel notch", "Строк за деление колеса"),
                            value: $controller.profile.wheelLines, in: InputProfile.wheelRange)
                            .labelsHidden()
                    }
                    .frame(minHeight: 36)
                    .disabled(!controller.profile.fixedWheel)
                }
            } label: {
                Text(language.text("Mouse wheel", "Колесо мыши"))
            }
        }
    }

    private var gesturePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureSwitch(
                language.text("Trackpad gestures", "Жесты трекпада"),
                enabled: $controller.profile.gesturesEnabled, status: controller.gestureStatus)

            Picker(language.text("Number of fingers", "Число пальцев"), selection: fingers.projectedValue) {
                Text(language.text("3 fingers", "3 пальца")).tag(3)
                Text(language.text("4 fingers", "4 пальца")).tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 235, alignment: .leading)

            GroupBox {
                VStack(spacing: 0) {
                    ForEach(GestureMotion.allCases, id: \.self) { motion in
                        if motion != .tap { Divider() }
                        gestureRow(TrackpadGesture(fingers: fingers.wrappedValue, motion: motion))
                    }
                }
            } label: {
                Text(language.text("Assignments", "Назначения"))
            }

            HStack(spacing: 7) {
                Image(systemName: "hand.tap")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(language.text("Last gesture", "Последний жест"))
                Spacer()
                Text(controller.lastGesture?.label(language) ?? "—")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 2)

            Text(language.text(
                "If a swipe also triggers a macOS gesture, turn off that swipe in Trackpad settings.",
                "Если свайп запускает ещё и жест macOS, отключи совпадающий свайп в настройках трекпада."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureSwitch(
        _ title: String, enabled: Binding<Bool>, status: FeatureStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(title, isOn: enabled).toggleStyle(.switch)
                Spacer(minLength: 12)
                if status == .enabled {
                    Label(status.label(language), systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            switch status {
            case .alreadyManaged, .unavailable:
                Text(status.label(language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
        }
    }

    private func directionRow(
        _ title: String, symbol: String, selection: Binding<ScrollMode>
    ) -> some View {
        HStack {
            rowLabel(title, symbol: symbol)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(ScrollMode.allCases) { mode in
                    Text(mode.label(language)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 172)
        }
        .frame(minHeight: 37)
    }

    private func gestureRow(_ gesture: TrackpadGesture) -> some View {
        let selected = Binding(
            get: { controller.profile.action(for: gesture) },
            set: { controller.profile.setAction($0, for: gesture) }
        )
        return HStack {
            rowLabel(gesture.motion.label(language), symbol: gesture.motion.symbol)
            Spacer()
            Picker(gesture.label(language), selection: selected) {
                ForEach(GestureAction.allCases.filter { $0 != .openApplication }) { action in
                    Text(action.label(language)).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 186)
        }
        .frame(minHeight: 35)
    }

    private func rowLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
        }
    }

    private var lineCount: String {
        let count = controller.profile.wheelLines
        if !language.usesRussian() { return count == 1 ? "1 line" : "\(count) lines" }
        switch count {
        case 1: return "1 строка"
        case 2...4: return "\(count) строки"
        default: return "\(count) строк"
        }
    }
}
