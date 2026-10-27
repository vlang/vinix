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
syntax errors. No executable selftests, DEX assembly, signed APK build, sealed
successor framework or ARM execution has passed for this checkpoint.

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
The original source-only bundle remains unchanged; executable and ARM checks
are still pending.

Host disk pressure blocked executable validation. Resume with the pinned V
compiler at `/Users/alex/code/v-tccbin-bootstrap-20261026/v` and serialize builds:

1. Build and run `check-broadcast-result.v` against the credential baseline's
   `smali` tree, with the retained smali tools and Java for assembly.
2. Build and run `check-native-bindings.v` and the combined builder's
   `--self-test`, then build the enhanced signed fixture.
3. Run the combined builder with `--broadcast-result`, the two baseline pins
   above, and fresh output
   `combined-account-webview-broadcast-result-framework-2026-10-27-r1` below the
   Android state directory. Preserve at least 1 GiB free while producing it.
4. Add a separate strict runner/transfer profile with the newly sealed JAR/APK
   pins and exact `broadcast-results` marker; preserve historical profiles.
5. Stage the six-file framework successor and execute the fixture on ARM before
   retrying real Play Services, Maps and Google account authentication.

Google account login remains unverified; this checkpoint supplies source for
the next observed framework failure and records the outstanding validation.
