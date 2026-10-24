# Maps252: runtime execution advances to account lookup failure

Maps252 removes the earlier Maps251 `Operation not permitted` launch failure:
the administrator binds the dedicated Android runtime with the advertised
`ro,nosuid,nodev,wxallowed,relatime` policy, then the fixture enters ART with
real/effective/saved/filesystem UID and GID 10000, no supplementary groups,
and root regain denied. The policy is recorded before and after dropping
credentials. This is a causal fixture, not production app isolation:
`CapBnd=000001ffffffffff` and `NoNewPrivs=0` remain in the raw status.

Startup then fails in `java.lang.System.initUnchangeableSystemProperties`:
`getpwuid_r failed: errno 0 (No error information)`. JNI `FindClass` aborts
with the pending `AssertionError`, and the process exits with code 1. The
preserved boot image's initramfs `/etc/passwd` has no UID 10000 account; the
runtime overlay supplies no replacement passwd file. The missing account
explains this next failure and motivates provisioning a real app account.

The original suite result remains **`startup_failed`** with three failure
markers, `launcher_entered=true`, `native_maps_observed=true`,
`process_exited=true`, `backend_ready=false`, and `functional_passed=null`.
There is no onboarding, map, interaction log, or functional qualification.
The configured 180-second limit is not an observed endurance result; ART
aborts before readiness. This run therefore does not test the Maps
`BridgeInitializer` path or onboarding transition fixes.

The prelaunch source revision is
`94decdcab3cdee19099dcdbbca4babff9abac5e4` (2026-10-24 15:05:09 UTC).
The frozen247 runtime incorporates the CompoundButton fix
`5577de6f3667423d27fd7bb01b9bc688494aef05`. Its framework JAR is
`73a10513135f9e264df9afdc7139c5370d67016d864be82fe0d6b2adba1f459b`;
its native library is
`78893e6767c9398a7d6cb513f0f34b8536604afaa065e383f46cb98e9d003f37`.
The original signed Maps APK is version `26.42.01.997557324`, SHA256
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.

The complete external bundle is
`/Users/alex/.local/state/vinix/android/maps252-2026-10-24`.
The separately preserved prelaunch `frozen-inputs.json` SHA256 is
`7527b03bcbb3166f48419fc2f83617e16d8bd2bd3b7ae98c28ed0e56a5c71de0`.
The final `sha256.json` SHA256 is
`ad35b14c4be52d9c39a3b197912aa1cea3283ce2a390481fba098df7c24d77ab`.

The bundle retains the complete raw output, continuous root harness stdout,
serial and compressed serial, screenshot, packet capture, all three APKs,
the staged runtime, post-run private boot image and firmware variables,
QEMU, firmware, actual boot kernel, config, frozen suite and interaction
driver sources/binaries. All 106 original runtime regular-file bytes remain
unchanged after data relocation and original-launcher renaming; only the
wrapper and experiment marker add regular files, for a total of 108.
Actual FAT archive readback also checks hidden files and symlink targets.

Exact compiled framework/native sources (125/83 files), framework manifest,
source deltas, fixture build receipt and its compiler executables are retained.
Supplementary native247 build command source, generated C, headers and binary
identity come from the already sealed CompoundButton bundle. They are a
preserved recipe and source/binary provenance; no original native247 compiler
execution receipt was available. Copies of boot media are explicitly post-run
state. APFS clones preserve independent retained files without a second archive.

The original host generator and suite used `-prod`; their assertion checks
were disabled by V. No original host compiler command receipt was retained.
The raw `PREFLIGHT PASS` marker alone therefore provides no validation. The
separate auditor below retains assertions and independently checks the
completed image archive, frozen inputs, runtime bytes and original result.

Rebuild the assertion-enabled auditor without `-prod`:

```sh
/Users/alex/code/v/v_old -cc cc -cflags -O2 -o /tmp/maps252-evidence \
  tests/native-android-ws/maps252-evidence.v
/tmp/maps252-evidence check \
  /Users/alex/.local/state/vinix/android/maps252-2026-10-24 \
  ad35b14c4be52d9c39a3b197912aa1cea3283ce2a390481fba098df7c24d77ab
```

Validation passed with assertions enabled: the complete retained bundle
passed, while a manifest-only partial bundle with the correct pin and the
complete bundle with an all-zero pin were rejected. A separate `-prod` build
exited 2 before auditing, as required by its assertion guard. Full auditing
used approximately 0.9 GiB of temporary space for actual archive extraction
and removed the scratch directory afterward. Logs are retained beside the
bundle in `maps252-2026-10-24-validation/` and
`maps252-2026-10-24-negative/`.
