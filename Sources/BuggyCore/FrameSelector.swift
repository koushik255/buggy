import Foundation

public enum MouseButton: String, Equatable, Sendable {
    case left
    case right
    case other
}

/// Why a frame was kept. A frame can carry more than one reason.
public enum FrameReason: Equatable, Sendable {
    case sessionStart
    case sessionEnd
    case screenChange(delta: Double)
    case click(x: Double, y: Double, button: MouseButton)
    case key(name: String)

    public var summary: String {
        switch self {
        case .sessionStart:
            return "session start"
        case .sessionEnd:
            return "session end"
        case .screenChange(let delta):
            return "screen change (delta \(ClipText.number(delta)))"
        case .click(let x, let y, let button):
            return "click \(button.rawValue) at (\(ClipText.pixel(x)), \(ClipText.pixel(y)))"
        case .key(let name):
            return "key \(name)"
        }
    }

    var sortRank: Int {
        switch self {
        case .sessionStart: return 0
        case .click: return 1
        case .key: return 2
        case .screenChange: return 3
        case .sessionEnd: return 4
        }
    }

    var isInput: Bool {
        switch self {
        case .click, .key: return true
        default: return false
        }
    }
}

public struct TimelineSample: Equatable, Sendable {
    public var timestamp: TimeInterval
    public var signature: FrameSignature

    public init(timestamp: TimeInterval, signature: FrameSignature) {
        self.timestamp = timestamp
        self.signature = signature
    }
}

public struct TimelineEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case click(x: Double, y: Double, button: MouseButton)
        case key(name: String)
    }

    public var timestamp: TimeInterval
    public var kind: Kind

    public init(timestamp: TimeInterval, kind: Kind) {
        self.timestamp = timestamp
        self.kind = kind
    }
}

public struct SelectedFrame: Equatable, Sendable {
    /// Index into the sample array that was passed to the selector.
    public var sampleIndex: Int
    public var timestamp: TimeInterval
    public var reasons: [FrameReason]
    public var clickMarks: [ClickMark]

    public init(sampleIndex: Int, timestamp: TimeInterval, reasons: [FrameReason], clickMarks: [ClickMark]) {
        self.sampleIndex = sampleIndex
        self.timestamp = timestamp
        self.reasons = reasons
        self.clickMarks = clickMarks
    }
}

public struct SelectionResult: Equatable, Sendable {
    public var frames: [SelectedFrame]
    /// Input events that attached to a frame the cap later discarded.
    public var droppedEventCount: Int
    /// Input events that had no sample inside the association window.
    public var unmatchedEventCount: Int

    public init(frames: [SelectedFrame], droppedEventCount: Int, unmatchedEventCount: Int) {
        self.frames = frames
        self.droppedEventCount = droppedEventCount
        self.unmatchedEventCount = unmatchedEventCount
    }
}

/// Picks a small set of frames from a sampled timeline.
///
/// Order of preference when the cap is hit: the opening frame, the closing
/// frame, click and key frames spread across the clip, then the screen
/// changes with the largest delta. Near-duplicate screen changes are dropped
/// before the cap is applied. Click and key frames are not dropped as
/// duplicates, because the event itself is the point of keeping them.
public enum FrameSelector {
    public static func select(
        samples: [TimelineSample],
        events: [TimelineEvent],
        config: ClipConfig
    ) -> SelectionResult {
        let config = config.sanitized()
        guard !samples.isEmpty else {
            return SelectionResult(frames: [], droppedEventCount: 0, unmatchedEventCount: events.count)
        }

        let order = samples.indices.sorted { lhs, rhs in
            let left = samples[lhs].timestamp
            let right = samples[rhs].timestamp
            if left == right { return lhs < rhs }
            return left < right
        }
        let sorted = order.map { samples[$0] }
        var reasons = Array(repeating: [FrameReason](), count: sorted.count)
        reasons[0].append(.sessionStart)

        var baseline = 0
        for index in 1..<sorted.count {
            let sinceBaseline = sorted[index].signature.meanAbsoluteDifference(to: sorted[baseline].signature)
            let instant = sorted[index].signature.meanAbsoluteDifference(to: sorted[index - 1].signature)
            let delta = max(sinceBaseline, instant)
            let elapsed = sorted[index].timestamp - sorted[baseline].timestamp
            let major = delta >= config.majorChangeThreshold
            let due = elapsed >= config.minChangeInterval
            if delta >= config.changeThreshold && (due || major) {
                reasons[index].append(.screenChange(delta: delta))
                baseline = index
            }
        }
        if sorted.count > 1 {
            reasons[sorted.count - 1].append(.sessionEnd)
        }

        let orderedEvents = events.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp { return false }
            return lhs.timestamp < rhs.timestamp
        }
        var attachedSample = [Int]()
        attachedSample.reserveCapacity(orderedEvents.count)
        var unmatched = 0
        for event in orderedEvents {
            guard let index = nearestIndex(in: sorted, to: event.timestamp, window: config.eventAssociationWindow) else {
                unmatched += 1
                continue
            }
            attachedSample.append(index)
            switch event.kind {
            case .click(let x, let y, let button):
                reasons[index].append(.click(x: x, y: y, button: button))
            case .key(let name):
                reasons[index].append(.key(name: name))
            }
        }

        var kept = [Int]()
        var anchor: FrameSignature?
        for index in 0..<sorted.count where !reasons[index].isEmpty {
            let hasInput = reasons[index].contains(where: \.isInput)
            let isStart = reasons[index].contains { reason in
                if case .sessionStart = reason { return true }
                return false
            }
            if let anchor, !hasInput, !isStart {
                let delta = sorted[index].signature.meanAbsoluteDifference(to: anchor)
                if delta < config.duplicateThreshold {
                    continue
                }
            }
            kept.append(index)
            anchor = sorted[index].signature
        }

        let limited = limit(kept, reasons: reasons, maxFrames: config.maxFrames)
        let keptSet = Set(limited)
        let dropped = attachedSample.reduce(into: 0) { count, index in
            if !keptSet.contains(index) { count += 1 }
        }

        let frames = limited.map { index in
            let cleaned = normalized(reasons[index])
            let marks = cleaned.compactMap { reason -> ClickMark? in
                if case .click(let x, let y, _) = reason {
                    return ClickMark(x: x, y: y)
                }
                return nil
            }
            return SelectedFrame(
                sampleIndex: order[index],
                timestamp: sorted[index].timestamp,
                reasons: cleaned,
                clickMarks: marks
            )
        }
        return SelectionResult(frames: frames, droppedEventCount: dropped, unmatchedEventCount: unmatched)
    }

    private static func nearestIndex(
        in samples: [TimelineSample],
        to timestamp: TimeInterval,
        window: TimeInterval
    ) -> Int? {
        var bestIndex: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        for index in samples.indices {
            let distance = abs(samples[index].timestamp - timestamp)
            guard distance <= window else { continue }
            let isCloser = distance < bestDistance
            let isEarlierTie = distance == bestDistance && index < (bestIndex ?? index)
            if bestIndex == nil || isCloser || isEarlierTie {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func limit(_ kept: [Int], reasons: [[FrameReason]], maxFrames: Int) -> [Int] {
        guard kept.count > maxFrames else { return kept }
        if maxFrames == 1 {
            let inputs = kept.filter { reasons[$0].contains(where: \.isInput) }
            if inputs.isEmpty {
                return [kept[0]]
            }
            return [inputs[inputs.count / 2]]
        }

        var selected = [kept[0], kept[kept.count - 1]]
        let reserved = Set(selected)
        let inputFrames = kept.filter { index in
            !reserved.contains(index) && reasons[index].contains(where: \.isInput)
        }
        let changeFrames = kept.filter { index in
            !reserved.contains(index) && !reasons[index].contains(where: \.isInput)
        }
        let slots = maxFrames - selected.count
        let pickedInputs = evenlySpaced(inputFrames, limit: min(slots, inputFrames.count))
        selected.append(contentsOf: pickedInputs)
        let remaining = maxFrames - Set(selected).count
        if remaining > 0 {
            let ranked = changeFrames.map { index -> (Int, Double) in
                let score = reasons[index].compactMap { reason -> Double? in
                    if case .screenChange(let delta) = reason { return delta }
                    return nil
                }.max() ?? 0
                return (index, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
                return lhs.1 > rhs.1
            }
            selected.append(contentsOf: ranked.prefix(remaining).map(\.0))
        }
        return Array(Set(selected)).sorted()
    }

    /// Picks `limit` values spread from the first to the last.
    static func evenlySpaced(_ values: [Int], limit: Int) -> [Int] {
        guard limit > 0 else { return [] }
        if values.count <= limit { return values }
        if limit == 1 { return [values[values.count / 2]] }
        var chosen = [Int]()
        var used = Set<Int>()
        let last = Double(values.count - 1)
        for step in 0..<limit {
            let position = Double(step) * last / Double(limit - 1)
            var index = Int(position.rounded())
            index = min(max(index, 0), values.count - 1)
            if used.contains(index) {
                var found: Int?
                for offset in 1..<values.count {
                    let forward = index + offset
                    if forward < values.count, !used.contains(forward) {
                        found = forward
                        break
                    }
                    let backward = index - offset
                    if backward >= 0, !used.contains(backward) {
                        found = backward
                        break
                    }
                }
                if let found { index = found }
            }
            if used.insert(index).inserted {
                chosen.append(values[index])
            }
        }
        return chosen.sorted()
    }

    private static func normalized(_ reasons: [FrameReason]) -> [FrameReason] {
        var unique = [FrameReason]()
        for reason in reasons where !unique.contains(reason) {
            unique.append(reason)
        }
        return unique.sorted { lhs, rhs in
            let left = lhs.sortRank
            let right = rhs.sortRank
            if left != right { return left < right }
            return false
        }
    }
}

enum ClipText {
    static func number(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func pixel(_ value: Double) -> String {
        String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func seconds(_ value: TimeInterval) -> String {
        number(value) + "s"
    }
}
