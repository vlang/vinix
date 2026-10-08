// SPDX-License-Identifier: GPL-2.0-or-later
// Run unchanged against installed Catalyst UIKit and the native iOS V runtime.
__attribute__((objc_root_class))
@interface NSString
- (const char *)UTF8String;
@end
extern int puts(const char *), strcmp(const char *, const char *);
#define STRINGS(X) \
    X(NSDocumentTypeDocumentAttribute, "DocumentType") \
    X(NSForegroundColorAttributeName, "NSColor") \
    X(NSPlainTextDocumentType, "NSPlainText") \
    X(UIAccessibilityVoiceOverStatusDidChangeNotification, "UIAccessibilityVoiceOverTouchStatusChanged") \
    X(UIActivityTypeAssignToContact, "com.apple.UIKit.activity.AssignToContact") \
    X(UIActivityTypePostToFlickr, "com.apple.UIKit.activity.PostToFlickr") \
    X(UIActivityTypePostToVimeo, "com.apple.UIKit.activity.PostToVimeo") \
    X(UIActivityTypePrint, "com.apple.UIKit.activity.Print") \
    X(UIActivityTypeSaveToCameraRoll, "com.apple.UIKit.activity.SaveToCameraRoll") \
    X(UIApplicationDidBecomeActiveNotification, "UIApplicationDidBecomeActiveNotification") \
    X(UIApplicationDidEnterBackgroundNotification, "UIApplicationDidEnterBackgroundNotification") \
    X(UIApplicationOpenNotificationSettingsURLString, "app-settings:notifications") \
    X(UIApplicationOpenSettingsURLString, "app-settings:") \
    X(UIApplicationOpenURLOptionsSourceApplicationKey, "UIApplicationOpenURLOptionsSourceApplicationKey") \
    X(UIApplicationWillEnterForegroundNotification, "UIApplicationWillEnterForegroundNotification") \
    X(UIDeviceBatteryStateDidChangeNotification, "UIDeviceBatteryStateDidChangeNotification") \
    X(UIFontTextStyleBody, "UICTFontTextStyleBody") \
    X(UIKeyboardDidShowNotification, "UIKeyboardDidShowNotification") \
    X(UIKeyboardFrameEndUserInfoKey, "UIKeyboardFrameEndUserInfoKey") \
    X(UIKeyboardWillHideNotification, "UIKeyboardWillHideNotification") \
    X(UIKeyboardWillShowNotification, "UIKeyboardWillShowNotification") \
    X(kCFBundleVersionKey, "CFBundleVersion") \
    X(kCFLocaleCountryCode, "kCFLocaleCountryCodeKey") \
    X(kCFLocaleLanguageCode, "kCFLocaleLanguageCodeKey") \
    X(kCFPreferencesCurrentApplication, "kCFPreferencesCurrentApplication") \
    X(kCFRunLoopCommonModes, "kCFRunLoopCommonModes")
#define DECLARE(name, value) extern NSString *const name;
STRINGS(DECLARE)
#undef DECLARE
extern const unsigned long UIAccessibilityTraitNone, UIAccessibilityTraitButton;
extern const unsigned long UIAccessibilityTraitLink, UIAccessibilityTraitImage;
extern const unsigned long UIAccessibilityTraitNotEnabled, UIAccessibilityTraitAdjustable, UIBackgroundTaskInvalid;
extern const unsigned UIAccessibilityAnnouncementNotification, UIAccessibilityLayoutChangedNotification;
int main(void) { @autoreleasepool {
#define VERIFY(name, value) if (strcmp([name UTF8String], value)) { puts("IOS-CONSTANTS FAIL: " #name); return 1; }
    STRINGS(VERIFY)
#undef VERIFY
    if (UIAccessibilityTraitNone != 0 || UIAccessibilityTraitButton != 1 ||
        UIAccessibilityTraitLink != 2 || UIAccessibilityTraitImage != 4 ||
        UIAccessibilityTraitNotEnabled != 256 || UIAccessibilityTraitAdjustable != 4096 ||
        UIBackgroundTaskInvalid != 0 || UIAccessibilityAnnouncementNotification != 1008 ||
        UIAccessibilityLayoutChangedNotification != 1001) {
        puts("IOS-CONSTANTS FAIL: typed scalars"); return 1;
    }
    puts("IOS-CONSTANTS: Foundation and UIKit strings, accessibility traits and typed scalars");
    return 0;
} }
