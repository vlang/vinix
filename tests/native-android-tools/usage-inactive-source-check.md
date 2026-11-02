# Disabled AppStandby inactivity query

`UsageStatsManager.isAppInactive(String)` now returns false under this target's
disabled AppStandby policy. There is no classification/history/enforcement
backend in the native runtime, job/alarm/power policy or existing manager.
The result means that no AppStandby inactivity restriction is classified here;
it does not establish installation, foreground state, recent use, usage history
or a permission grant.

This follows the
[API 28 disabled-policy short circuit](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/services/usage/java/com/android/server/usage/AppStandbyController.java#L916):
`isAppIdleFilteredOrParoled` returns false when `isParoledOrCharging` is true,
and [that predicate](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/services/usage/java/com/android/server/usage/AppStandbyController.java#L466)
returns true when AppStandby is disabled. Package lookup/validation is not
reached on that path, including for null, empty or unknown names. This is an
explicit disabled-feature contract, rather than an assertion that a missing
service is automatically equivalent to AOSP's RemoteException fallback.

The source appends only one public instance boolean query. The fieldless
manager's original constructor and metadata remain unchanged. No argument
lookup, validation, mutable state, backend method, Context lookup, permission
check or native binding is added. The manager is outside the retained native
bundle's 70 consumed classes; complete SDK/native equality remains a deployment
check. The actual GMS failure is the missing call through `esqc.a`, `esqr.a`
and the network-scheduler Handler. The bounded caller audit found no additional
certain adjacent API needed for this change.

Focused checks passed on the first attempt: twelve malformed/repeated/schema
refusals, five independent policy/API/member controls, API-28 baseline and
patched assembly, and two DEX disassembly rounds with identical canonical second
roundtrip bytes. Refusals use the real wrapper and require unchanged input.
Independent provider, checker, driver and backend/native-membership reviews
approved. ARM execution remains a separate check.

Evidence is outside Git at
`/Users/alex/.local/state/vinix/android/usage-inactive-source-check-2026-11-02-r1`.
It retains frozen sources, generated C, input pins, guarded commands, original
and patched DEX and both roundtrips. Proof receipt SHA-256 is
`f2af16f921a5e5bab861d619c3b89ba157a516c72f7a2a898999d8d21608502d`.
Source parent before this commit is `ac92c061fb522ce08105e2e4060df8f4666aa3f8`.
Provider/integration/driver/checker SHA-256 values are respectively
`f6ade1627c3b8fbf90af86e77473de55ef1e1bfbcc4c76c4f8bfde78a0799b44`,
`dad3433840fe2a69504dc2aab3492740dc95111f836c676a9027be612f77eb4f`,
`80ba124bc6d7d6895c82d88ba9419483c205c78273fd358fcd10157e21f6932f`
and `732d3c707eae62e539ea78344828a818d9f7ef6d25df94cf17cec3e5fd81c991`.

The focused run took 6.946 guard seconds, sampled 207,273,984 bytes aggregate
RSS and recorded 176,422,912 bytes detailed RSS. Compiler sampled/detailed
maxima were 276,496,384/278,151,168 bytes. All guards and children exited zero,
with complete cleanup and zero swaps under the original 600 MiB RSS,
300-second, 512 MiB shared-growth, 1 GiB reserve, 4 MiB output and file cap
16777216 limits. Full SDK, native equality, ARM and live GMS/Maps checks remain
separate; these host checks establish no authentication or imagery result.
