# Build ABI families for the native ARM runtime

GMS's Cronet module loader reached the missing `Build.SUPPORTED_64_BIT_ABIS`
field. Build now exposes both public static final ABI-family arrays. Each field
gets a separate property/list read, following the
[API-28 Build list contract](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/os/Build.java).
The private helper uses the existing property getter with an explicit empty
default, creates a new empty array for missing/empty values and otherwise
forwards the value and regex separator to String.split. It preserves ordering
and existing null-key/regex exceptions.

Only SystemProperties' existing aarch64 branch gains three values:
`ro.product.cpu.abilist64=arm64-v8a`, `ro.product.cpu.abilist32=` and
`ro.product.cpu.abi2=`. The last value corrects the previous unknown secondary
ABI for this single-ABI target. Existing CPU_ABI and SUPPORTED_ABIS assignments
are retained. The kernel, ART boot property chain and native APK installer
prove a 64-bit ARM process with only arm64-v8a loading; no 32-bit ABI is added.
This is the proven ARM target policy. Legacy x86 properties remain unchanged;
other architectures' absent new list properties conservatively yield empties.

Build retains all 23 prior fields and five noninitializer methods; its existing
initializer changes only by the two list initializations. SystemProperties
retains its field, six noninitializer methods and all prior initializer control
flow. A private Build helper and two fields are the only member additions.
The complete Build.VERSION class remains byte-identical. Neither changed class
is consumed by the retained native70 map or manual native field access; complete
SDK/native equality remains a deployment check.

First-attempt host qualification passed: 18 malformed-input refusals preserve
the whole two-class family before writes, 17 semantic controls, API-28 baseline
and patched assembly, and two DEX roundtrips with a stable second result.
Controls cover empty defaults, key/separator forwarding, empty allocation,
aliases, single initialization, ARM property values, branch placement and VERSION
preservation. Independent provider/checker/driver reviews approved. Actual
property and array-identity cases in ART remain separate fixture checks.

Evidence is at `/Users/alex/.local/state/vinix/android/build-abis-source-check-2026-11-03-r1`,
including frozen sources, generated C, input pins, guarded receipts and DEX
roundtrips. Receipt SHA-256:
`1a0c6fe0212e6189585d5b305a48c6c7c3d2fb83789c57199fa7bf52b8c62768`.
Recorded source parent: `e44c9c0743505d8516ade8b0c539864f89bc47cc`.
The closed `gms-build-abis-audit-2026-11-02-r1` manifest is
`e256798658e186d604b5531dd17c93c5b893a6ccf877a1cd6f8c0430e0c71ffc`.
Parent EventLog SDK manifest/JAR SHA-256:
`56adef59b9210f72117709c26c5e008503379586407c70ab00297c32a70f5670` /
`0a331f5595b4b6c1298dd0e944389cbeabe2b93f6e02e536c4d26d5d200967ad`.

All guards/children exited zero with complete cleanup and zero swaps. Proof
took 8.605 seconds, sampled 228,016,128 bytes aggregate RSS and recorded
183,025,664 detailed RSS. Split compiler sampled/detailed maxima were
253,247,488/278,740,992 bytes. Original limits remain 600 MiB RSS, 300 seconds,
512 MiB shared-volume growth, 1 GiB reserve, 4 MiB output and file cap 16777216.
