import Foundation

struct DrawingPoint: Codable, Equatable {
    let x: Double
    let y: Double

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    var length: Double { hypot(x, y) }

    func cross(_ other: Self) -> Double {
        x * other.y - y * other.x
    }
}

struct TrackpadDrawing: Codable, Equatable {
    let strokes: [[DrawingPoint]]
    private static let samplesPerStroke = 17

    init?(rawStrokes: [[DrawingPoint]]) {
        guard (1...2).contains(rawStrokes.count),
              rawStrokes.allSatisfy({ $0.count >= 3 }) else { return nil }
        let points = rawStrokes.flatMap { $0 }
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              let left = points.map(\.x).min(), let right = points.map(\.x).max(),
              let bottom = points.map(\.y).min(), let top = points.map(\.y).max() else { return nil }

        let scale = max(right - left, top - bottom)
        guard scale >= 0.10 else { return nil }
        let center = DrawingPoint(x: (left + right) / 2, y: (bottom + top) / 2)
        var normalized: [[DrawingPoint]] = []
        for stroke in rawStrokes {
            guard let resampled = Self.resample(stroke) else { return nil }
            normalized.append(resampled.map {
                DrawingPoint(x: ($0.x - center.x) / scale, y: ($0.y - center.y) / scale)
            })
        }
        strokes = normalized
    }

    private static func resample(_ stroke: [DrawingPoint]) -> [DrawingPoint]? {
        var distances = [0.0]
        for index in 1..<stroke.count {
            distances.append(distances[index - 1] + (stroke[index] - stroke[index - 1]).length)
        }
        guard let total = distances.last, total >= 0.12 else { return nil }
        var index = 1
        return (0..<samplesPerStroke).map { sample in
            let target = total * Double(sample) / Double(samplesPerStroke - 1)
            while index < stroke.count - 1 && distances[index] < target { index += 1 }
            let start = stroke[index - 1]
            let end = stroke[index]
            let segmentLength = distances[index] - distances[index - 1]
            let fraction = segmentLength > 0 ? (target - distances[index - 1]) / segmentLength : 0
            return DrawingPoint(
                x: start.x + (end.x - start.x) * fraction,
                y: start.y + (end.y - start.y) * fraction)
        }
    }

    func distance(to other: Self) -> Double {
        guard (1...2).contains(strokes.count), strokes.count == other.strokes.count,
              strokes.allSatisfy({ $0.count == Self.samplesPerStroke }),
              other.strokes.allSatisfy({ $0.count == Self.samplesPerStroke }) else { return .infinity }

        func error(_ first: [DrawingPoint], _ second: [DrawingPoint]) -> Double {
            func squaredSum(_ other: [DrawingPoint]) -> Double {
                zip(first, other).reduce(0) { sum, pair in
                    let delta = pair.0 - pair.1
                    return sum + delta.x * delta.x + delta.y * delta.y
                }
            }
            return min(squaredSum(second), squaredSum(Array(second.reversed())))
        }

        var squared = error(strokes[0], other.strokes[0])
        if strokes.count == 2 {
            squared += error(strokes[1], other.strokes[1])
            let swapped = error(strokes[0], other.strokes[1]) + error(strokes[1], other.strokes[0])
            squared = min(squared, swapped)
        }
        return sqrt(squared / Double(strokes.count * Self.samplesPerStroke))
    }

    var isCross: Bool {
        guard strokes.count == 2,
              let first = line(for: strokes[0]), let second = line(for: strokes[1]) else { return false }
        let area = first.vector.cross(second.vector)
        let lengthProduct = first.vector.length * second.vector.length
        guard abs(area) >= 0.80 * lengthProduct else { return false }
        let offset = second.start - first.start
        let firstIntersection = offset.cross(second.vector) / area
        let secondIntersection = offset.cross(first.vector) / area
        return (0.16...0.84).contains(firstIntersection) && (0.16...0.84).contains(secondIntersection)
    }

    private func line(for stroke: [DrawingPoint]) -> (start: DrawingPoint, vector: DrawingPoint)? {
        guard let start = stroke.first, let end = stroke.last else { return nil }
        let vector = end - start
        let distance = vector.length
        guard distance >= 0.37 else { return nil }
        let traveled = zip(stroke, stroke.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
        guard traveled <= distance * 1.16,
              stroke.allSatisfy({ abs(($0 - start).cross(vector)) / distance <= 0.12 }) else {
            return nil
        }
        return (start, vector)
    }
}

enum DrawingActivation: String, Codable, CaseIterable, Identifiable {
    case control, option, noKey

    var id: Self { self }

    func label(_ language: InterfaceLanguage) -> String {
        switch self {
        case .control: return "Control"
        case .option: return "Option"
        case .noKey: return language.text("No key", "Без клавиши")
        }
    }

    func instructions(_ language: InterfaceLanguage) -> String {
        switch self {
        case .control, .option:
            return language.text("Hold \(label(language)) and draw with one finger.",
                                 "Удерживай \(label(language)) и рисуй одним пальцем.")
        case .noKey:
            return language.text("Draw with one finger.", "Рисуй одним пальцем.")
        }
    }
}

struct CustomDrawing: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let shape: TrackpadDrawing
    var action: GestureAction
    var application: DrawingApplication?

    var assignment: DrawingAssignment {
        get { DrawingAssignment(action: action, application: application) }
        set {
            action = newValue.action
            application = newValue.application
        }
    }
}

struct DrawingSettings: Codable, Equatable {
    var enabled = true
    var activation: DrawingActivation = .control
    var crossAction: GestureAction = .quitApp
    var crossApplication: DrawingApplication?
    var custom: [CustomDrawing] = []

    var crossAssignment: DrawingAssignment {
        get { DrawingAssignment(action: crossAction, application: crossApplication) }
        set {
            crossAction = newValue.action
            crossApplication = newValue.application
        }
    }

    func match(_ drawing: TrackpadDrawing) -> DrawingMatch? {
        let candidates = custom
            .filter { $0.action != .none && $0.assignment.isConfigured }
            .map { ($0, $0.shape.distance(to: drawing)) }
            .filter { $0.1 <= 0.12 }
            .sorted { $0.1 < $1.1 }
        if let (best, distance) = candidates.first {
            if candidates.count > 1 && candidates[1].1 - distance < 0.025 { return nil }
            return .custom(best.name, best.assignment)
        }
        if crossAction != .none && crossAssignment.isConfigured && drawing.isCross {
            return .cross(crossAssignment)
        }
        return nil
    }
}

enum DrawingMatch: Equatable {
    case cross(DrawingAssignment)
    case custom(String, DrawingAssignment)

    var assignment: DrawingAssignment {
        switch self {
        case .cross(let assignment), .custom(_, let assignment): return assignment
        }
    }

    func label(_ language: InterfaceLanguage) -> String {
        switch self {
        case .cross: return language.text("Cross", "Крест")
        case .custom(let name, _): return name
        }
    }
}

struct TrackpadDrawingCapture {
    enum Change {
        case none, started, singleStroke, twoStrokes, cancelled
    }

    private var previousCount = 0
    private var strokeBegan: TimeInterval = 0
    private var current: [DrawingPoint]?
    private var complete: [[DrawingPoint]] = []

    var canBeginStroke: Bool { previousCount == 0 }

    mutating func reset() {
        current = nil
        complete.removeAll()
    }

    mutating func takeDrawing() -> TrackpadDrawing? {
        defer { reset() }
        return TrackpadDrawing(rawStrokes: complete)
    }

    mutating func feed(_ frame: ContactFrame, canBegin: Bool) -> Change {
        let previous = previousCount
        previousCount = frame.count
        guard (0...1).contains(frame.count), frame.timestamp.isFinite else {
            let hadDrawing = current != nil || !complete.isEmpty
            reset()
            return hadDrawing ? .cancelled : .none
        }
        if frame.count == 0 {
            guard let current else { return .none }
            self.current = nil
            complete.append(current)
            return complete.count == 2 ? .twoStrokes : .singleStroke
        }

        // Normalized touch coordinates describe a pad wider than it is tall.
        let point = DrawingPoint(x: frame.x * 1.5, y: frame.y)
        if previous == 0 && canBegin {
            strokeBegan = frame.timestamp
            current = [point]
            return .started
        }
        guard let last = current?.last else { return .none }
        guard frame.timestamp - strokeBegan <= 2.5, frame.timestamp >= strokeBegan else {
            reset()
            return .cancelled
        }
        if (point - last).length >= 0.0015 && (current?.count ?? 0) < 400 {
            current?.append(point)
        }
        return .none
    }
}
