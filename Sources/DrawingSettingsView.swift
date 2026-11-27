import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DrawingSettingsView: View {
    @ObservedObject var controller: InputController
    private var name = SwiftUI.State(initialValue: "")
    private var assignment = SwiftUI.State(initialValue: DrawingAssignment(action: .closeWindow))

    init(controller: InputController) {
        self.controller = controller
    }

    private var language: InterfaceLanguage { controller.profile.language }
    private var options: DrawingSettings { controller.profile.drawing }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(language.text("One-finger drawings", "Фигуры одним пальцем"),
                   isOn: $controller.profile.drawing.enabled)
                .toggleStyle(.switch)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(language.text("Activation key", "Клавиша для рисования"))
                        Spacer()
                        Picker(language.text("Activation key", "Клавиша для рисования"),
                               selection: $controller.profile.drawing.activation) {
                            ForEach(DrawingActivation.allCases) { activation in
                                Text(activation.label(language)).tag(activation)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 186)
                    }
                    Text(options.activation.instructions(language))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label(language.text("Cross", "Крест"), systemImage: "xmark")
                        Spacer()
                        DrawingActionPicker(title: language.text("Cross action", "Действие для креста"),
                                            language: language, assignment: $controller.profile.drawing.crossAssignment)
                    }
                    .frame(minHeight: 36)
                    Text(language.text(
                        "Draw two intersecting lines, like an X or a plus.",
                        "Проведи две пересекающиеся линии в форме «Х» или плюса."
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 7)

                    ForEach(options.custom) { drawing in
                        Divider()
                        HStack(spacing: 8) {
                            DrawingThumbnail(shape: drawing.shape)
                                .frame(width: 22, height: 22)
                            Text(drawing.name)
                                .lineLimit(1)
                                .help(drawing.name)
                            Spacer()
                            DrawingActionPicker(title: drawing.name, language: language,
                                                assignment: customAssignment(for: drawing.id))
                            Button {
                                controller.profile.drawing.custom.removeAll { $0.id == drawing.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help(language.text("Remove drawing", "Удалить фигуру"))
                            .accessibilityLabel(language.text("Remove \(drawing.name)", "Удалить «\(drawing.name)»"))
                        }
                        .frame(minHeight: 36)
                    }
                }
            } label: {
                Text(language.text("Drawings", "Фигуры"))
            }

            recording

            if let match = controller.lastDrawing {
                LabeledContent(language.text("Last recognized drawing", "Последняя фигура"), value: match.label(language))
                    .font(.callout)
            }
            if let application = controller.applicationLaunchFailure {
                Text(language.text("Could not open \(application). Choose the application again.",
                                   "Не удалось открыть «\(application)». Выбери приложение заново."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { controller.cancelDrawingRecording() }
    }

    @ViewBuilder private var recording: some View {
        switch controller.drawingDraft {
        case .idle:
            if !controller.profile.gesturesEnabled || controller.gestureStatus == .unavailable {
                Text(controller.profile.gesturesEnabled
                     ? language.text("Trackpad input is unavailable.", "Ввод с трекпада недоступен.")
                     : language.text("Turn on trackpad gestures in the Gestures tab to record a drawing.",
                                     "Включи жесты трекпада во вкладке «Жесты», чтобы записать фигуру."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if case .alreadyManaged = controller.gestureStatus {
                Text(controller.gestureStatus.label(language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button(language.text("Record a Drawing…", "Записать фигуру…"), action: start)
                .disabled(controller.gestureStatus != .enabled)
        case .capturing:
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Draw on the trackpad", "Нарисуй фигуру на трекпаде"))
                        .fontWeight(.semibold)
                    Text(language.text(
                        "Use one finger for one or two strokes, then lift it.",
                        "Сделай один или два штриха одним пальцем и подними его."
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                cancelButton
            }
        case .ready(let shape):
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        DrawingThumbnail(shape: shape)
                            .frame(width: 48, height: 48)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(language.text("Drawing name", "Название фигуры"), text: name.projectedValue)
                                .textFieldStyle(.roundedBorder)
                            DrawingActionPicker(title: language.text("Action", "Действие"),
                                                language: language, assignment: assignment.projectedValue)
                        }
                    }
                    HStack {
                        Button(language.text("Record Again", "Записать заново"), action: start)
                        Spacer()
                        cancelButton
                        Button(language.text("Save", "Сохранить")) {
                            controller.saveDrawing(name: name.wrappedValue, assignment: assignment.wrappedValue)
                        }
                        .disabled(name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || !assignment.wrappedValue.isConfigured)
                        .buttonStyle(.borderedProminent)
                    }
                }
            } label: {
                Text(language.text("New drawing", "Новая фигура"))
            }
        case .tryAgain:
            VStack(alignment: .leading, spacing: 8) {
                Text(language.text(
                    "The stroke was too short or interrupted. Draw again with one finger.",
                    "Штрих получился слишком коротким или прервался. Попробуй ещё раз одним пальцем."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
                HStack {
                    Button(language.text("Record Again", "Записать заново"), action: start)
                    cancelButton
                }
            }
        }
    }

    private var cancelButton: some View {
        Button(language.text("Cancel", "Отмена")) {
            controller.cancelDrawingRecording()
        }
    }

    private func start() {
        controller.beginDrawingRecording()
    }

    private func customAssignment(for id: UUID) -> Binding<DrawingAssignment> {
        Binding(
            get: {
                controller.profile.drawing.custom.first { $0.id == id }?.assignment
                    ?? DrawingAssignment(action: .none)
            },
            set: { selected in
                if let index = controller.profile.drawing.custom.firstIndex(where: { $0.id == id }) {
                    controller.profile.drawing.custom[index].assignment = selected
                }
            })
    }
}

private struct DrawingActionPicker: View {
    let title: String
    let language: InterfaceLanguage
    @Binding var assignment: DrawingAssignment

    var body: some View {
        let action = Binding(
            get: { assignment.action },
            set: { selected in
                if selected == .openApplication {
                    chooseApplication()
                } else {
                    assignment = DrawingAssignment(action: selected)
                }
            })
        VStack(alignment: .trailing, spacing: 4) {
            Picker(title, selection: action) {
                ForEach(GestureAction.allCases) { available in
                    Text(available.label(language)).tag(available)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if assignment.action == .openApplication {
                let appName = assignment.application?.name
                    ?? language.text("Choose Application…", "Выбрать приложение…")
                Button(action: chooseApplication) {
                    Label(appName, systemImage: "arrow.up.forward.app")
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .help(language.text("Choose an application", "Выбрать приложение"))
                .accessibilityLabel(language.text("Change application \(appName)", "Сменить приложение «\(appName)»"))
                .padding(.horizontal, 7)
            }
        }
        .frame(width: 186)
        .padding(.vertical, 3)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = language.text("Choose an Application", "Выбор приложения")
        panel.prompt = language.text("Choose", "Выбрать")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = assignment.application?.url.deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/Applications", isDirectory: true)

        let selection = $assignment
        let accept: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            if let application = DrawingApplication(url: url) {
                selection.wrappedValue = DrawingAssignment(action: .openApplication, application: application)
            } else {
                let alert = NSAlert()
                alert.messageText = language.text("Unable to read this application", "Не удалось прочитать приложение")
                alert.informativeText = language.text("Choose a macOS application again.", "Выбери приложение macOS заново.")
                if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) }
                else { alert.runModal() }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: accept)
        } else {
            panel.begin(completionHandler: accept)
        }
    }
}

private struct DrawingThumbnail: View {
    let shape: TrackpadDrawing

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) * 0.75
            var path = Path()
            for stroke in shape.strokes {
                for (index, point) in stroke.enumerated() {
                    let projected = CGPoint(x: size.width / 2 + point.x * scale,
                                            y: size.height / 2 - point.y * scale)
                    if index == 0 {
                        path.move(to: projected)
                    } else {
                        path.addLine(to: projected)
                    }
                }
            }
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
