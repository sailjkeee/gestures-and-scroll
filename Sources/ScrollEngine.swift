// SPDX-License-Identifier: Apache-2.0
// Scroll processing reference: Scroll Reverser, Copyright 2011 Nicholas Moore.
import AppKit
import CoreGraphics

private let scrollEventCallback: CGEventTapCallBack = { _, type, event, context in
    if let context {
        Unmanaged<ScrollEngine>.fromOpaque(context).takeUnretainedValue().handle(type, event)
    }
    return Unmanaged.passUnretained(event)
}

final class ScrollEngine {
    private struct Axis {
        let line: CGEventField
        let point: CGEventField
        let fixed: CGEventField

        static let vertical = Axis(
            line: .scrollWheelEventDeltaAxis1, point: .scrollWheelEventPointDeltaAxis1,
            fixed: .scrollWheelEventFixedPtDeltaAxis1)
        static let horizontal = Axis(
            line: .scrollWheelEventDeltaAxis2, point: .scrollWheelEventPointDeltaAxis2,
            fixed: .scrollWheelEventFixedPtDeltaAxis2)

        func apply(to event: CGEvent, invert: Bool, wheelLines: Int) -> Bool {
            let lines = event.getIntegerValueField(line)
            let direction: Int64 = invert ? -1 : 1
            if wheelLines > 0 && lines.magnitude == 1 {
                // Changing the one-notch line count asks Quartz to recompute
                // the corresponding point deltas without wheel acceleration.
                event.setIntegerValueField(line, value: lines * direction * Int64(wheelLines))
                return false
            }
            if invert {
                let points = event.getIntegerValueField(point)
                let fraction = event.getDoubleValueField(fixed)
                event.setIntegerValueField(line, value: 0 &- lines)
                event.setDoubleValueField(fixed, value: -fraction)
                event.setIntegerValueField(point, value: 0 &- points)
            }
            return invert
        }
    }

    var profile = InputProfile()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var deviceKinds: [UInt64: GSDeviceKind] = [:]

    func start() -> Bool {
        if let tap, CFMachPortIsValid(tap) {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return CGEvent.tapIsEnabled(tap: tap)
        }
        stop()
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: scrollEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        self.tap = nil
        self.source = nil
        deviceKinds.removeAll()
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .scrollWheel, let native = NSEvent(cgEvent: event) else { return }
        let hid = GSCopyScrollHIDEvent(event)
        let sender = GSHIDSenderID(hid)
        guard sender != 0 || event.getIntegerValueField(.eventSourceUnixProcessID) == 0 else {
            return
        }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let kind = deviceKind(sender)
        let isTrackpad = kind == GSDeviceTrackpad || (kind == GSDeviceUnknown && continuous)
        let reversed = transform(
            event, isTrackpad: isTrackpad, isContinuous: continuous,
            systemIsNatural: native.isDirectionInvertedFromDevice)
        if reversed.vertical || reversed.horizontal {
            GSReverseRawScroll(hid, reversed.vertical, reversed.horizontal)
        }
    }

    @discardableResult
    func transform(
        _ event: CGEvent, isTrackpad: Bool, isContinuous: Bool, systemIsNatural: Bool
    ) -> (vertical: Bool, horizontal: Bool) {
        let mode = isTrackpad ? profile.trackpadDirection : profile.mouseDirection
        let invert = mode.reverses(systemIsNatural: systemIsNatural)
        let lines = !isTrackpad && !isContinuous && profile.fixedWheel ? profile.wheelLines : 0
        let vertical = Axis.vertical.apply(to: event, invert: invert, wheelLines: lines)
        let horizontal = Axis.horizontal.apply(
            to: event, invert: invert && profile.matchHorizontal, wheelLines: lines)
        return (vertical, horizontal)
    }

    private func deviceKind(_ sender: UInt64) -> GSDeviceKind {
        guard sender != 0 else { return GSDeviceUnknown }
        if let kind = deviceKinds[sender] { return kind }
        if deviceKinds.count >= 64 { deviceKinds.removeAll(keepingCapacity: true) }
        let kind = GSDeviceKindForSender(sender)
        deviceKinds[sender] = kind
        return kind
    }
}
