# Objective-C iOS Calculator

A small UIKit app with a dark calculator keypad, a resizable result display,
and native target/action buttons. `Calculator.m` implements immediate
addition, subtraction, multiplication and division, decimal input, AC, sign
changes, contextual percentages, repeated equals, and error recovery. Input
accepts up to 15 digits; results use double precision and display 12 significant
digits. It has no Swift or private framework dependencies.

From the repository root:

```sh
examples/ios-calculator/build.sh
tests/ios/run-objc-calculator.sh
```

Build products:

```text
build/ios/objc/Calculator.app/Calculator  ARM64 iOS Mach-O executable
build/ios/objc/Calculator.app/Info.plist  application metadata
build/ios/objc/Calculator.ipa             Payload/Calculator.app archive
build/ios/objc/build-mode.txt             compiler API source used
```

The app targets iOS 15.0 or later. The builder uses an installed iPhoneOS SDK
when available, or `IOS_SDK=/path/to/iPhoneOS.sdk` to select one. On this Mac,
only the macOS command-line SDK is installed, so the build uses the narrow,
independently written declarations and `.tbd` import lists in `api/` with
Clang and `ld64.lld`. Those files contain no framework implementations. The
binary still imports real iOS Foundation, UIKit, libobjc and libSystem; its
load-command platform is iOS, not macOS or the iOS Simulator.

`IOS_CLANG`, `IOS_LD` and `VINIX_IOS_CALCULATOR_BUILD_DIR` select the compiler,
Mach-O linker and output directory. The builder adds and verifies an ad-hoc
bundle signature when `codesign` is available. Installing on a normal iPhone
requires the developer's own device provisioning and signing. UI execution
has not been tested on a device or simulator here.

The Objective-C model is executed on this ARM64 Mac with its actual Foundation
runtime, once with Apple's headers and once with the minimal declarations.
Both runs check 27 arithmetic/input cases with AddressSanitizer and UBSan.
The second run also checks that the minimal NSObject declaration reserves its
`isa` object header and gives the calculator's instance variables correct offsets.

## Vinix compatibility target

This is an application to run through [the V Mach-O runtime](../../docs/ios.md),
not a Vinix port of the UI. The build inspected here has 25 chained imports
across four libraries, compared with the local Apple macOS Calculator's
2,059. Its class/selector metadata and imported functions provide a small,
reproducible target for the next Objective-C/Foundation/UIKit compatibility work.

```sh
build/ios/run-ios-host --imports build/ios/objc/Calculator.app/Calculator
```

`run-ios` can inspect it, but cannot launch its UI until those runtimes and the
compositor bridge exist. The existing C Mach-O arithmetic probe remains the
Vinix execution test; the UIKit app is not substituted for that passing test.

The UI uses Apple's documented
[UIButton interface](https://developer.apple.com/documentation/uikit/uibutton?language=objc)
and [target/action event dispatch](https://developer.apple.com/documentation/uikit/responding-to-control-based-events-using-target-action?language=objc).
