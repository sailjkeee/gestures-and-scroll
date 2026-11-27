#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

typedef enum {
    GSDeviceUnknown = 0,
    GSDeviceMouse = 1,
    GSDeviceTrackpad = 2
} GSDeviceKind;

typedef struct {
    uint64_t deviceID;
    uint64_t generation;
    double timestamp;
    double x;
    double y;
    double span;
    int32_t count;
} GSTouchSample;

typedef void (*GSTouchObserver)(GSTouchSample);

bool GSTrackpadAPIAvailable(void);
int32_t GSStartTrackpadFeed(GSTouchObserver observer, uint64_t generation);
void GSStopTrackpadFeed(void);

CFTypeRef GSCopyScrollHIDEvent(CGEventRef event) CF_RETURNS_RETAINED;
uint64_t GSHIDSenderID(CFTypeRef hidEvent);
GSDeviceKind GSDeviceKindForSender(uint64_t senderID);
void GSReverseRawScroll(CFTypeRef hidEvent, bool vertical, bool horizontal);
