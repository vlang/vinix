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

The same compiled `.app` executable runs on Vinix through
[the V Mach-O runtime](../../docs/ios.md). It has 25 imports across Foundation,
UIKit, libobjc and libSystem. Vinix implements the subset needed by this app;
its ARM64 Objective-C methods and target/action callbacks execute directly.

```sh
./build-ios-aarch64.sh
./build-desktop-aarch64.sh
./run-desktop-aarch64.sh --no-build
# Open "iOS Calculator".
```

The first command builds and stages both the runtime and app. The desktop
builder installs `/usr/bin/vinix-ios-calculator` and the unchanged bundle below
`/usr/share/vinix/ios/`. The compositor draws UIKit's controls and delivers button
and keyboard input. The runtime handles resize callbacks and ARC teardown.

`python3 tests/ios/run.py` runs the C probe and UIKit binary in an isolated Vinix
VM. The UIKit test clicks all 27 model cases through the desktop protocol,
checks resize and keyboard input, and runs 1,000 update cycles before closing.
`python3 tests/ios/desktop.py --desktop build/vinix-desktop` additionally verifies
real QEMU pointer clicks and saves a screenshot. Unknown imports or selectors
fail explicitly; this is not general iOS framework compatibility.

The UI uses Apple's documented
[UIButton interface](https://developer.apple.com/documentation/uikit/uibutton?language=objc)
and [target/action event dispatch](https://developer.apple.com/documentation/uikit/responding-to-control-based-events-using-target-action?language=objc).
