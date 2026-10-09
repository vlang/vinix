// SPDX-License-Identifier: GPL-2.0-or-later
// Same data-symbol and NSString ABI against Mac GameController and Vinix.
__attribute__((objc_root_class))
@interface NSString
- (const char *)UTF8String;
@end
extern int puts(const char *), printf(const char *,...), strcmp(const char *,const char *);
#define KEYS(X) \
    X(GCKeyCodeDeleteOrBackspace,42) X(GCKeyCodeSpacebar,44) X(GCKeyCodeCapsLock,57) \
    X(GCKeyCodeF1,58) X(GCKeyCodeF2,59) X(GCKeyCodeF3,60) X(GCKeyCodeF4,61) \
    X(GCKeyCodeF5,62) X(GCKeyCodeF6,63) X(GCKeyCodeF7,64) X(GCKeyCodeF8,65) \
    X(GCKeyCodeF9,66) X(GCKeyCodeF10,67) X(GCKeyCodeF11,68) X(GCKeyCodeF12,69) \
    X(GCKeyCodeLeftControl,224) X(GCKeyCodeLeftShift,225) X(GCKeyCodeLeftAlt,226) X(GCKeyCodeLeftGUI,227) \
    X(GCKeyCodeRightControl,228) X(GCKeyCodeRightShift,229) X(GCKeyCodeRightAlt,230) X(GCKeyCodeRightGUI,231)
#define STRINGS(X) \
    X(GCControllerDidConnectNotification,"GCControllerDidConnectNotification") \
    X(GCControllerDidDisconnectNotification,"GCControllerDidDisconnectNotification") \
    X(GCControllerDidBecomeCurrentNotification,"GCControllerDidBecomeCurrentNotification") \
    X(GCKeyboardDidConnectNotification,"GCKeyboardDidConnectNotification") \
    X(GCKeyboardDidDisconnectNotification,"GCKeyboardDidDisconnectNotification") \
    X(GCMouseDidConnectNotification,"GCMouseDidConnectNotification") \
    X(GCMouseDidDisconnectNotification,"GCMouseDidDisconnectNotification") \
    X(GCHapticsLocalityDefault,"Default") X(GCHapticsLocalityHandles,"Handles") \
    X(GCHapticsLocalityLeftHandle,"Left Handle") X(GCHapticsLocalityRightHandle,"Right Handle")
#define DECLARE_KEY(name,value) extern const long name;
KEYS(DECLARE_KEY)
#define DECLARE_STRING(name,value) extern NSString *const name;
STRINGS(DECLARE_STRING)
int main(void) { @autoreleasepool {
#define VERIFY_KEY(name,value) if (name != value || sizeof name != 8) { printf("IOS-GAME-CONSTANTS FAIL: %s = %ld\n",#name,name); return 1; }
    KEYS(VERIFY_KEY)
#define VERIFY_STRING(name,value) if (strcmp([name UTF8String],value)) { puts("IOS-GAME-CONSTANTS FAIL: " #name); return 1; }
    STRINGS(VERIFY_STRING)
    puts("IOS-GAME-CONSTANTS: 64-bit keyboard codes, notification strings and haptic localities match Mac libraries");
    return 0;
} }
