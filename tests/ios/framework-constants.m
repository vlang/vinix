// SPDX-License-Identifier: GPL-2.0-or-later
// Run unchanged against installed Catalyst UIKit and the native iOS V runtime.
__attribute__((objc_root_class))
@interface NSString
- (const char *)UTF8String;
@end
extern int puts(const char *), strcmp(const char *, const char *);
extern SEL NSSelectorFromString(NSString *), sel_registerName(const char *);
extern NSString *NSStringFromSelector(SEL);
#define STRINGS(X) \
    X(UIApplicationWillResignActiveNotification, "UIApplicationWillResignActiveNotification") \
    X(UISceneDidActivateNotification, "UISceneDidActivateNotification") \
    X(UISceneWillDeactivateNotification, "UISceneWillDeactivateNotification") \
    X(UIWindowSceneSessionRoleApplication, "UIWindowSceneSessionRoleApplication") \
    X(NSCocoaErrorDomain, "NSCocoaErrorDomain") \
    X(NSMachErrorDomain, "NSMachErrorDomain") \
    X(NSPOSIXErrorDomain, "NSPOSIXErrorDomain") \
    X(NSLocalizedDescriptionKey, "NSLocalizedDescription") \
    X(NSLocalizedFailureReasonErrorKey, "NSLocalizedFailureReason") \
    X(NSLocalizedRecoverySuggestionErrorKey, "NSLocalizedRecoverySuggestion") \
    X(NSFileModificationDate, "NSFileModificationDate") \
    X(NSFilePosixPermissions, "NSFilePosixPermissions") \
    X(NSFileSize, "NSFileSize") \
    X(NSFileSystemFreeSize, "NSFileSystemFreeSize") \
    X(NSFileSystemSize, "NSFileSystemSize") \
    X(NSKeyValueChangeNewKey, "new") \
    X(NSKeyValueChangeOldKey, "old") \
    X(NSKeyedArchiveRootObjectKey, "root") \
    X(NSProcessInfoPowerStateDidChangeNotification, "NSProcessInfoPowerStateDidChangeNotification") \
    X(NSProcessInfoThermalStateDidChangeNotification, "NSProcessInfoThermalStateDidChangeNotification") \
    X(NSHTTPCookieExpires, "Expires") \
    X(NSHTTPCookieName, "Name") \
    X(NSHTTPCookieOriginURL, "OriginURL") \
    X(NSHTTPCookiePath, "Path") \
    X(NSHTTPCookieValue, "Value") \
    X(NSURLAuthenticationMethodServerTrust, "NSURLAuthenticationMethodServerTrust") \
    X(NSURLErrorFailingURLPeerTrustErrorKey, "NSURLErrorFailingURLPeerTrustErrorKey") \
    X(NSURLErrorFailingURLStringErrorKey, "NSErrorFailingURLStringKey") \
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
extern const double UIWindowLevelNormal, UIWindowLevelStatusBar, UIWindowLevelAlert;
extern const unsigned long UIAccessibilityTraitNone, UIAccessibilityTraitButton;
extern const unsigned long UIAccessibilityTraitLink, UIAccessibilityTraitImage;
extern const unsigned long UIAccessibilityTraitNotEnabled, UIAccessibilityTraitAdjustable, UIBackgroundTaskInvalid;
extern const unsigned UIAccessibilityAnnouncementNotification, UIAccessibilityLayoutChangedNotification;
int main(void) { @autoreleasepool {
    if (NSSelectorFromString((NSString *)0) || NSStringFromSelector((SEL)0) ||
        NSSelectorFromString(NSStringFromSelector(@selector(sample:other:))) != @selector(sample:other:) ||
        NSSelectorFromString(NSStringFromSelector(sel_registerName("unicode_\xf0\x9f\x98\x80:"))) != sel_registerName("unicode_\xf0\x9f\x98\x80:")) {
        puts("IOS-CONSTANTS FAIL: selector/string conversion"); return 1;
    }
#define VERIFY(name, value) if (strcmp([name UTF8String], value)) { puts("IOS-CONSTANTS FAIL: " #name); return 1; }
    STRINGS(VERIFY)
#undef VERIFY
    if (UIWindowLevelNormal != 0 || UIWindowLevelStatusBar != 1000 || UIWindowLevelAlert != 2000 ||
        UIAccessibilityTraitNone != 0 || UIAccessibilityTraitButton != 1 ||
        UIAccessibilityTraitLink != 2 || UIAccessibilityTraitImage != 4 ||
        UIAccessibilityTraitNotEnabled != 256 || UIAccessibilityTraitAdjustable != 4096 ||
        UIBackgroundTaskInvalid != 0 || UIAccessibilityAnnouncementNotification != 1008 ||
        UIAccessibilityLayoutChangedNotification != 1001) {
        puts("IOS-CONSTANTS FAIL: typed scalars"); return 1;
    }
    puts("IOS-CONSTANTS: Foundation and UIKit strings, accessibility traits and typed scalars");
    return 0;
} }
