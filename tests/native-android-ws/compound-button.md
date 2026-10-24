# CompoundButton indicator regression

Source revision: `5577de6f3667423d27fd7bb01b9bc688494aef05`.
The same signed fixture APK (`ffcdbd2d6c86004b5983912b03bf3b312dde342b5e031773131eeee30f304f59`)
ran on the baseline and fixed Vinix Android runtimes on 2026-10-24.

| Runtime | Observed fixture result |
| --- | --- |
| Baseline framework244/native236 | Default checkbox/radio assertions passed; explicit-null width/bitmap-pixel assertion failed; process exited 1. |
| Fixed | Defaults, explicit null, static custom Canvas pixels/bounds, restoration, resource zero, subclass and negative intrinsic-size assertions passed; `BOOTSTRAP-READY` and native backend readiness observed; no assertion or process exit during 30 seconds. |

The original suite classifies the fixed run as `startup_failed`, with
`functional_passed: null`, because its inherited optional Maps diagnostic reports
`NoSuchFieldError` for `bB:Lnge;` and its caught `ClassNotFoundException: nge`.
The checker preserves that classification and accepts only those known diagnostic
failure markers. Its PASS qualifies the assertions and bounded observation above;
Google Maps functionality and stateful/animated drawables require separate tests.

External archive:
`/Users/alex/.local/state/vinix/android/compound247-2026-10-24.tar.gz`
(175,079,452 bytes). SHA256:
`237c0e4d954fa9f50cac86367907962f0c24ed8bc3fddd7c5b6e63a41e8750ec`.
Its extracted directory contains 2,447 inventoried files, including raw results,
serial logs, screenshots, the APK, full staged runtime modules, frozen sources
and builders. Boot disks and mutable firmware variables are excluded, as recorded
in `scope.txt`. The pinned `sha256.json` SHA256 is
`70e5dd4ae468ed74bf8f362f3d40e5bced9c2cbd0d5bf2757ed8bc7254ff7e20`.

From the repository, audit the complete extracted archive with:

```sh
v -nocache -cc cc -cflags -O2 run tests/native-android-ws/compound-button-evidence.v check \
  /Users/alex/.local/state/vinix/android/compound247-2026-10-24 \
  70e5dd4ae468ed74bf8f362f3d40e5bced9c2cbd0d5bf2757ed8bc7254ff7e20
```

The checker passed against that bundle. It hashes every inventoried file, verifies
the same APK, compares 125 frozen framework-generator sources and 83 native
sources, and verifies staged framework/native identities and unchanged runtime
dependencies. Only the CompoundButton framework function, native view renderer
and generated Canvas binding differ. A negative audit with an all-zero manifest
pin exited 1 with `bundle manifest digest differs from report`.

Build the auditor without `-prod`, which removes its assertions; the maintained
checker now refuses that mode with exit 2. An independent assertion-enabled
recheck passed the complete original pinned bundle, rejected an all-zero pin,
and rejected an APFS clone with the authentic manifest but a modified fixture
source. The `-prod` refusal also passed. Guest checks use explicit Smali
`AssertionError` instructions, independent of the V generator's optimisation mode.
Recheck sources, binaries and logs are retained at
`/Users/alex/.local/state/vinix/android/compound247-assertions-2026-10-24`;
its `sha256.json` SHA256 is
`60dbc2177fd2cc5f4068489b4a7b00cfc8f8cb867958ce2e4b6cb20f5baa0937`.
The historical bundle and its checksums remain unchanged.
