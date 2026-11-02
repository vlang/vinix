# Unmanaged device-owner and profile queries

`DevicePolicyManager.getDeviceOwner()` now returns null and
`UserManager.isManagedProfile()` returns false for the existing unmanaged,
regular guest user. These are ordinary public Java instance methods. The two
classes retain all 19 existing methods, with no new fields, classes or native
bindings. Context service lookup and policy enrollment/enforcement are unchanged.

[AOSP's owner getter](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r1/core/java/android/app/admin/DevicePolicyManager.java#L6303)
returns null when the calling-user owner component is absent.
[AOSP's managed-profile query](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r1/core/java/android/os/UserManager.java#L1969)
describes the caller's user type. The false result follows this regular,
non-profile guest; it is not an AOSP null-service fallback or a managed-profile
implementation.

The observed GMS broker failure reaches `akrf.j`, offset `0x18`, source line 25,
which calls the absent owner API. Its null-owner branch calls an outline at
`0x20`/line 33 that directly invokes the absent managed-profile API. The bounded
five-class audit also inspected the direct component setter and logging flag
helpers. Other Android linkage in the selected method bodies exists. Existing
PackageManager component-enabled getter `-1` and no-op setter semantics remain
an explicit limitation; this fix does not claim component-state persistence.
The broker reached readiness and exited. Missing Maps launch/log artifacts do
not establish a Maps native crash.

Source parent: `2f68a5daadbafd4caf64b61ba232f55923b11688`. Tested source hashes:

- `framework_unmanaged_queries.v`: `abc514d53493bf65827108671c1d7ab7077a73a62a13b5010c692b1b267d29df`
- `framework.v`: `f37430be3118de11416321ad6dcd180b8358e186f3e808d6c3940dd5be9e0fbf`
- `unmanagedqueriescheck/main.v`: `568c5f5703ca1467712425c7bdb7ba994e75f82a79e8bd53bf2dfdb7c6dad198`
- `unmanaged-queries-source-check.v`: `7223f9d40d6adce8d5edaabda33b2668f1fb8b802ebfa1b0a4a6dd3aecfc86a1`

The provider validates both original class schemas before writing either class.
Focused checks reject 116 malformed/repeated/schema inputs and detect 16 output
body/ABI faults. Invalid or missing second-class input leaves the first intact;
this is validation before writes, without a claim of filesystem rollback. API 28
assembly and both DEX roundtrips preserve the 19 original methods, require both
exact added bodies, retain exactly two classes and produce stable second Smali.
Independent source/contract review passed. ARM execution of real Context service
lookups remains the separate signed fixture's responsibility.

Evidence under `S=/Users/alex/.local/state/vinix/android`:

- `gms-device-owner-method-audit-2026-11-02-r1`: complete five selected classes,
  SDK read set, exact DEX/tool pins, guarded commands and audit. Audit SHA-256
  `5be6500f77b004afe5b9a9184a19cf5ea7846723d8d150736f3ab4f1879f9ff1`;
  checksum-list SHA-256
  `955a20400aee7828a6bd7f2f40077efcfc4c6c776438a95d520cfa59010665ed`.
- `unmanaged-queries-source-check-2026-11-02-r1`: frozen source copies, generated
  host project, refusal cases, original/patched DEX and both roundtrips. Final
  receipt SHA-256
  `eff4187b9e68f91c64b397ac3a9bde241e72e502875173e1fa0e6ddcc2e77938`.

All host phases passed their unchanged 600 MiB aggregate RSS, 300-second,
512 MiB growth, 1 GiB reserve, output and file caps, with complete cleanup and
zero swaps. Maximum sampled/detailed RSS were 274,333,696/278,347,776 bytes.
The focused run took 6.888 seconds and observed 25,923,584 bytes shared-volume
growth. The complete SDK build, native-pair equality, ARM fixture and live GMS
retry remain separate checks; no authentication or imagery result is claimed.
