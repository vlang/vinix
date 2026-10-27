# Broadcast receiver result compatibility checkpoint

Actual Play Services startup in `maps-context-storage-vm-r1` reached a manifest
receiver and failed at a super call to the missing
`BroadcastReceiver.setResultCode(int)`. The source checkpoint containing this
report adds the generic result APIs and delivery state; fixture source is
committed separately as `2b3abad87`.

Each manifest or registered delivery gets fresh, unordered pending state.
Its initial result code is `Activity.RESULT_OK` (-1), as passed by ordinary
[Android 10 ContextImpl.sendBroadcast](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r47/core/java/android/app/ContextImpl.java);
the receiver's result-code getter returns zero after detachment. The fixture distinguishes
these two states.
Code, data, extras and abort mutations remain local to that delivery.
`goAsync()` transfers the existing pending object and clears the receiver.
Normal and exceptional dispatch clear and finish state still owned by the
receiver. Detached getters return defaults, setters require pending state,
and clearing abort is harmless. Component completion rejects a second finish;
unordered registered completion is repeatable. This follows the relevant
[Android 10 BroadcastReceiver contract](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r47/core/java/android/content/BroadcastReceiver.java).
The existing transport sends unordered, non-sticky broadcasts; this change
does not add ordered broadcast transport or an ActivityManager completion queue.

Manifest delivery and `VinixBroadcast.run()` share the dispatch helper. The
native sender still creates and posts the same task to its Handler. The task's
Java implementation leaves an existing library's lazy JNI export unused.
Fresh native binding generation retains the historical native export for old
frameworks and skips it only for the exact canonical Java bridge. Other stale
bindings and altered bridges remain errors.

The `--broadcast-result` producer requires the complete sealed credential
baseline, inventory SHA-256
`cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691`
and JAR SHA-256
`9b894cc92c5d3d0e871b5389285b09b107d49cd5c4493fcc2449f3510f961352`.
It permits exactly four changed classes: BroadcastReceiver, its PendingResult,
ATLLoadedApp and VinixBroadcast. Their changed-method counts are 2/2/1/1;
added-method counts are 14/11/0/0. Seven exact fields are added across the first
two classes, with no new classes. The existing full-profile audit also checks
all 2104 classes and repeats the member delta after DEX roundtrip.

The fixture covers the real manifest super call, two actual registered
deliveries through a HandlerThread, independent async ownership, synchronous
result reset, abort isolation, detached state and exceptional cleanup. A queued
Handler barrier makes assertions after dispatch cleanup. All waits and thread
cleanup are bounded. The focused checker covers exact transforms, malformed
input rejection and optional four-class assembly; binding tests retain old
framework compatibility and reject a changed Java bridge.

Independent source reviews passed. Sequential V typechecks passed for the
focused checker/provider, native binding checker, strict producer and enhanced
fixture. Their peak resident sizes were respectively 453,591,040; 447,266,816;
311,033,856; and 279,822,336 bytes, with zero swaps. Typechecks found and corrected
V string continuation and array concatenation errors. `git diff --check` passed.
The initial executable checker build stopped before C compilation at those
syntax errors. At that source-only checkpoint, executable selftests, DEX
assembly, signed APK generation, a sealed successor framework and ARM execution
had not passed.

The retained source snapshots, initial failures and final typecheck logs are in
`/Users/alex/.local/state/vinix/android/broadcast-result-host-tools-2026-10-27-r1/`.
Its `sha256.txt` checksum is
`12ded9462ada61afc1a945fa955ac00fe5394772e65b6e889e818ff2a236b234`.

A subsequent source correction initializes active deliveries to -1 and splits
the fixture's callback and detached default checks. The checker/provider and
updated fixture typechecks passed again, using 454,623,232 and 268,615,680 bytes
peak RSS respectively, with zero swaps. These corrected sources and logs are
retained separately in
`/Users/alex/.local/state/vinix/android/broadcast-result-initial-code-2026-10-27-r1/`,
whose `sha256.txt` checksum is
`e500ba05f9afdb666a0e1ac1cfcd530b5ccf758cafddd9361a39370860cfafcc`.
The original source-only bundle remains unchanged. Executable checks subsequently
passed for source `e82ca648198b9e412a5c4defb8e2724503abf01c`; ARM checks remain
pending.

The focused transform checker and four-class DEX assembly passed. The native
binding selftest and complete baseline binding check passed (628 spec entries,
629 historical exports); the strict framework producer's selftest also passed.
The enhanced fixture built both signed APKs, disassembled their DEX and verified
APK v3 signatures. Its complete bundle is
`/Users/alex/.local/state/vinix/android/broadcast-result-fixture-2026-10-27-r1/`,
inventory SHA-256
`93146d2bff516752ca62ea21cfb7bd532ced9abfe81345beb61e40a0b5d9b77d`.
The client APK is
`44f6c4356a5d031cf68191476bb0d2fb0fc2ceec8ecea26ffd395024d19321e7`;
the disabled companion is
`5293215a5899d2adb3ca9c6a52248c10874a2ad5b2e9cf08168935e829527966`.

Builds ran sequentially using the pinned V compiler at
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA-256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
The four host builds peaked at 553,254,912; 550,518,784; 375,635,968; and
374,767,616 bytes RSS. Checker execution and four-class assembly peaked at
104,038,400 bytes; binding execution at 21,790,720; producer selftest at
9,977,856; and signed fixture generation at 111,247,360. All eight measurements
recorded zero swaps. Commands used 45-second CPU and 32 MiB file-size limits;
smali used two workers. These measurements do not explain the earlier reported
92 GiB session usage or establish sustained broker memory behavior.

Raw logs and host executables are retained in
`/Users/alex/.local/state/vinix/android/broadcast-result-executable-checks-2026-10-27-r1/`.
The complete retained inputs and results are bound by the fourteen-root streamed
seal in
`/Users/alex/.local/state/vinix/android/broadcast-result-host-evidence-sealed-2026-10-27-r1/`,
manifest SHA-256
`0ffbd89937df2a811d9d98131e0fc373125af03157e320707fec1eb7216aa9ce`.
Both sealing and a separate full readback check passed for all 8,292 entries.
The committed `broadcast-result-host-evidence.v` captures the pinned seven
relevant source files, a newly observed V source closure, compiler and fixture
inputs. Its plan inventory is
`70d0856a9956041ab3f977f96b8c8da9c737a9b8f738f3f55a6b8ec2034cb572`.
Historical host command arguments and limits are explicitly reconstructed from
the session; these are not contemporaneous command receipts. The signed
fixture's run arguments come from its original sealed build receipt. The
capture is not a hermetic SDK, C toolchain or dynamic-library closure.

The remaining work requires the full sealed framework successor:

1. Run the combined builder with `--broadcast-result`, the two baseline pins
   above, and fresh output
   `combined-account-webview-broadcast-result-framework-2026-10-27-r1` below the
   Android state directory. Preserve at least 1 GiB free while producing it.
2. Add a separate strict runner/transfer profile with the newly sealed JAR/APK
   pins and exact `broadcast-results` marker; preserve historical profiles.
3. Stage the six-file framework successor and execute the fixture on ARM before
   retrying real Play Services, Maps and Google account authentication.

Host free space fell below 1 GiB while preparing this checkpoint, then varied
around 1.2–1.4 GiB during the final read-only disk audit. Full framework
production remains below its 1.7 GiB start requirement, and staging requires
1.5 GiB initially with a 1 GiB reserve. No safe task-owned cleanup large enough
was found; no old evidence was removed and no VM was launched. Independent
source review found no concrete register, ownership or cleanup defect. Assembly and APK
verification do not establish ART verification, actual Maps startup, a fresh
Maps screenshot or Google account login. Those runtime results remain pending.
