import Foundation

struct ContactFrame {
    let count: Int
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let span: Double
}

struct TrackpadRecognizer {
    private struct Stroke {
        let began: TimeInterval
        var anchor: ContactFrame
        var lastFullFrame: ContactFrame
        var peakCount: Int
        var greatestTravel = 0.0
        var greatestSpanChange = 0.0
        var metRelease = false
        var interrupted = false

        init(_ frame: ContactFrame) {
            began = frame.timestamp
            anchor = frame
            lastFullFrame = frame
            peakCount = frame.count
        }

        mutating func advance(_ frame: ContactFrame) {
            if frame.count > peakCount {
                anchor = frame
                lastFullFrame = frame
                peakCount = frame.count
                greatestTravel = 0
                greatestSpanChange = 0
            }
            if frame.count < peakCount {
                metRelease = true
            } else if metRelease {
                interrupted = true
            } else {
                lastFullFrame = frame
                greatestTravel = max(greatestTravel, hypot(frame.x - anchor.x, frame.y - anchor.y))
                greatestSpanChange = max(greatestSpanChange, abs(frame.span - anchor.span))
            }
        }

        func gesture(at released: TimeInterval) -> TrackpadGesture? {
            guard !interrupted, peakCount == 3 || peakCount == 4,
                  anchor.timestamp - began <= 0.16,
                  lastFullFrame.timestamp - anchor.timestamp >= 0.012,
                  released - lastFullFrame.timestamp <= 0.15,
                  greatestSpanChange <= 0.085 else { return nil }

            let elapsed = released - began
            if elapsed <= 0.32 && greatestTravel <= 0.035 && greatestSpanChange <= 0.04 {
                return TrackpadGesture(fingers: peakCount, motion: .tap)
            }

            let dx = lastFullFrame.x - anchor.x
            let dy = lastFullFrame.y - anchor.y
            guard elapsed <= 0.9, max(abs(dx), abs(dy)) >= 0.13 else { return nil }
            if abs(dx) >= 1.3 * abs(dy) {
                return TrackpadGesture(fingers: peakCount, motion: dx > 0 ? .right : .left)
            }
            if abs(dy) >= 1.3 * abs(dx) {
                return TrackpadGesture(fingers: peakCount, motion: dy > 0 ? .up : .down)
            }
            return nil
        }
    }

    private var stroke: Stroke?
    private var latestTimestamp = -Double.infinity

    mutating func ingest(_ frame: ContactFrame) -> TrackpadGesture? {
        guard frame.count >= 0, frame.timestamp.isFinite,
              frame.x.isFinite, frame.y.isFinite, frame.span.isFinite else {
            stroke = nil
            return nil
        }
        if frame.timestamp < latestTimestamp {
            stroke = nil
        }
        latestTimestamp = frame.timestamp
        if frame.count == 0 {
            defer { stroke = nil }
            return stroke?.gesture(at: frame.timestamp)
        }
        if stroke == nil {
            stroke = Stroke(frame)
        } else {
            stroke?.advance(frame)
        }
        return nil
    }
}
