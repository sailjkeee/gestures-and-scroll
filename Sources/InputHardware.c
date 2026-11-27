// SPDX-License-Identifier: Apache-2.0
// Scroll source detection reference: Scroll Reverser, Copyright 2011 Nicholas Moore.
#include "InputHardware.h"

#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <math.h>
#include <stddef.h>

// MultitouchSupport is absent from the public SDK. It is loaded lazily so
// scrolling can still work if a future macOS version removes the touch feed.
// The Apple Silicon contact layout is 96 bytes with little-endian Float32
// coordinates. Only phase and normalized position are read from each record.
typedef struct {
    uint8_t beforePhase[20];
    int32_t phase;
    uint8_t beforePosition[8];
    float x;
    float y;
    uint8_t rest[56];
} MSTouchRecord;

_Static_assert(sizeof(MSTouchRecord) == 96, "Unexpected touch record size");
_Static_assert(offsetof(MSTouchRecord, x) == 32, "Unexpected touch record layout");

typedef int32_t (*MSFrameCallback)(CFTypeRef, const MSTouchRecord *, int32_t, double, int32_t, void *);
typedef struct {
    CFArrayRef (*listDevices)(void);
    bool (*isBuiltIn)(CFTypeRef);
    void (*addCallback)(CFTypeRef, MSFrameCallback, void *);
    void (*removeCallback)(CFTypeRef, MSFrameCallback);
    int32_t (*start)(CFTypeRef, int32_t);
    int32_t (*stop)(CFTypeRef);
} MSFunctions;

static MSFunctions multitouch;
static CFMutableArrayRef activeTrackpads;
static GSTouchObserver touchObserver;

static int32_t receiveTouches(CFTypeRef device, const MSTouchRecord *touches, int32_t count,
                              double timestamp, int32_t frame, void *context) {
    (void)frame;
    GSTouchSample sample = {
        .deviceID = (uint64_t)(uintptr_t)device,
        .generation = (uint64_t)(uintptr_t)context,
        .timestamp = timestamp
    };
    if (count > 16 || count < 0 || (count > 0 && !touches)) {
        sample.count = -1;
        touchObserver(sample);
        return 0;
    }

    double minX = 1, maxX = 0, minY = 1, maxY = 0;
    for (int32_t index = 0; index < count; index++) {
        const MSTouchRecord touch = touches[index];
        if (touch.phase < 0 || touch.phase > 7) {
            sample.count = -1;
            break;
        }
        // 3 enters contact, 4 is contact. Hover and lift aren't fingers down.
        if (touch.phase != 3 && touch.phase != 4) continue;
        if (!isfinite(touch.x) || !isfinite(touch.y) ||
            touch.x < -0.08 || touch.x > 1.08 || touch.y < -0.08 || touch.y > 1.08) {
            sample.count = -1;
            break;
        }
        sample.count++;
        sample.x += touch.x;
        sample.y += touch.y;
        minX = fmin(minX, touch.x);
        maxX = fmax(maxX, touch.x);
        minY = fmin(minY, touch.y);
        maxY = fmax(maxY, touch.y);
    }
    if (sample.count > 0) {
        sample.x /= sample.count;
        sample.y /= sample.count;
        sample.span = hypot(maxX - minX, maxY - minY);
    }
    touchObserver(sample);
    // Returning zero keeps the system's own gestures in the event stream.
    return 0;
}

bool GSTrackpadAPIAvailable(void) {
    static bool checked = false;
    static bool available = false;
    if (checked) return available;
    checked = true;
    void *framework = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_LOCAL | RTLD_NOW);
    if (!framework) return false;
    multitouch.listDevices = dlsym(framework, "MTDeviceCreateList");
    multitouch.isBuiltIn = dlsym(framework, "MTDeviceIsBuiltIn");
    multitouch.addCallback = dlsym(framework, "MTRegisterContactFrameCallbackWithRefcon");
    multitouch.removeCallback = dlsym(framework, "MTUnregisterContactFrameCallback");
    multitouch.start = dlsym(framework, "MTDeviceStart");
    multitouch.stop = dlsym(framework, "MTDeviceStop");
    available = multitouch.listDevices && multitouch.isBuiltIn && multitouch.addCallback &&
                multitouch.removeCallback && multitouch.start && multitouch.stop;
    return available;
}

int32_t GSStartTrackpadFeed(GSTouchObserver observer, uint64_t generation) {
    if (!GSTrackpadAPIAvailable()) return -1;
    if (activeTrackpads) return (int32_t)CFArrayGetCount(activeTrackpads);
    if (!touchObserver) touchObserver = observer;
    if (!touchObserver || observer != touchObserver) return -1;
    CFArrayRef devices = multitouch.listDevices();
    if (!devices) return 0;
    activeTrackpads = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    for (CFIndex index = 0; index < CFArrayGetCount(devices); index++) {
        CFTypeRef device = CFArrayGetValueAtIndex(devices, index);
        if (!multitouch.isBuiltIn(device)) continue;
        multitouch.addCallback(device, receiveTouches, (void *)(uintptr_t)generation);
        if (multitouch.start(device, 0) == 0) {
            CFArrayAppendValue(activeTrackpads, device);
        } else {
            multitouch.removeCallback(device, receiveTouches);
        }
    }
    CFRelease(devices);
    int32_t connected = (int32_t)CFArrayGetCount(activeTrackpads);
    if (connected == 0) {
        CFRelease(activeTrackpads);
        activeTrackpads = NULL;
    }
    return connected;
}

void GSStopTrackpadFeed(void) {
    if (!activeTrackpads) return;
    for (CFIndex index = 0; index < CFArrayGetCount(activeTrackpads); index++) {
        CFTypeRef device = CFArrayGetValueAtIndex(activeTrackpads, index);
        multitouch.removeCallback(device, receiveTouches);
        multitouch.stop(device);
    }
    CFRelease(activeTrackpads);
    activeTrackpads = NULL;
}

CFTypeRef GSCopyScrollHIDEvent(CGEventRef event) {
    static CFTypeRef (*copyEvent)(CGEventRef);
    static bool checked = false;
    if (!checked) {
        checked = true;
        copyEvent = dlsym(RTLD_DEFAULT, "CGEventCopyIOHIDEvent");
    }
    return copyEvent ? copyEvent(event) : NULL;
}

uint64_t GSHIDSenderID(CFTypeRef hidEvent) {
    static uint64_t (*senderID)(CFTypeRef);
    static bool checked = false;
    if (!checked) {
        checked = true;
        senderID = dlsym(RTLD_DEFAULT, "IOHIDEventGetSenderID");
    }
    return senderID && hidEvent ? senderID(hidEvent) : 0;
}

static bool propertyContains(io_registry_entry_t entry, CFStringRef key, CFStringRef term) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, key, NULL, 0);
    if (!value) return false;
    bool matches = CFGetTypeID(value) == CFStringGetTypeID() &&
        CFStringFind(value, term, kCFCompareCaseInsensitive).location != kCFNotFound;
    CFRelease(value);
    return matches;
}

GSDeviceKind GSDeviceKindForSender(uint64_t senderID) {
    if (!senderID) return GSDeviceUnknown;
    io_registry_entry_t entry = IOServiceGetMatchingService(
        kIOMainPortDefault, IORegistryEntryIDMatching(senderID));
    GSDeviceKind kind = GSDeviceUnknown;
    for (int depth = 0; entry && depth < 4; depth++) {
        if (IOObjectConformsTo(entry, "AppleMultitouchTrackpadHIDEventDriver") ||
            propertyContains(entry, CFSTR("HIDScrollAccelerationType"), CFSTR("Trackpad")) ||
            propertyContains(entry, CFSTR("Product"), CFSTR("Trackpad"))) {
            kind = GSDeviceTrackpad;
        } else if (kind == GSDeviceUnknown &&
                   (IOObjectConformsTo(entry, "AppleMultitouchMouseHIDEventDriver") ||
                    propertyContains(entry, CFSTR("HIDScrollAccelerationType"), CFSTR("Mouse")) ||
                    propertyContains(entry, CFSTR("Product"), CFSTR("Mouse")))) {
            kind = GSDeviceMouse;
        }

        io_registry_entry_t parent = IO_OBJECT_NULL;
        if (kind != GSDeviceTrackpad) {
            IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
        }
        IOObjectRelease(entry);
        entry = parent;
    }
    if (entry) IOObjectRelease(entry);
    return kind;
}

void GSReverseRawScroll(CFTypeRef hidEvent, bool vertical, bool horizontal) {
    static double (*getValue)(CFTypeRef, uint32_t);
    static void (*setValue)(CFTypeRef, uint32_t, double);
    static bool checked = false;
    if (!checked) {
        checked = true;
        getValue = dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
        setValue = dlsym(RTLD_DEFAULT, "IOHIDEventSetFloatValue");
    }
    if (!getValue || !setValue || !hidEvent) return;
    const uint32_t scrollX = 6u << 16;
    const uint32_t scrollY = scrollX | 1u;
    if (vertical) setValue(hidEvent, scrollY, -getValue(hidEvent, scrollY));
    if (horizontal) setValue(hidEvent, scrollX, -getValue(hidEvent, scrollX));
}
