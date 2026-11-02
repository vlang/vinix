# Absent keyguard policy feature mask

`DevicePolicyManager.getKeyguardDisabledFeatures(ComponentName)` now returns
`0` for both a null aggregate query and a named administrator. This target has
no Android policy service or enrolled administrators. The result matches
[AOSP API 28's absent-service branch](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-9.0.0_r3/core/java/android/app/admin/DevicePolicyManager.java#L4528),
which returns `KEYGUARD_DISABLE_FEATURES_NONE` (defined as zero at line 3434).
This is a read-only fallback, without policy enforcement, admin enrollment,
keyguard security, trust-agent or authentication claims.

The change appends one public instance method to the fieldless manager and
preserves all ten existing methods and class metadata. Context's cached policy
manager, service lookup, StrictMode and native bindings remain unchanged.
The manager is outside the retained native bundle's 70 consumed classes;
complete successor native equality remains a deployment check.

The preceding GMS run failed on the missing query through `fgup.b`, `fgup.a`
and the on-body trustlet. The audited helper passes a null admin, masks bit
`0x10` and returns false for zero before its separate trust-agent configuration
path. Its caller continues other initialization after that result. The bounded
fix establishes neither the rest of GMS initialization nor a working trustlet.

Focused checks passed on their first attempt: twelve malformed/repeated/schema
refusals, five independent output controls, original/patched API-28 assembly
and two DEX disassembly rounds. Refusals use the real file wrapper and verify
unchanged bytes; the positive oracle requires the exact public zero getter,
all original members and stable canonical second-roundtrip bytes. Independent
source and checker review approved.

Evidence is outside Git at
`/Users/alex/.local/state/vinix/android/keyguard-policy-source-check-2026-11-02-r1`.
It retains frozen sources, generated C, input pins, guarded commands, original
and patched DEX and both roundtrips. The proof receipt hashes to
`2009565acf2d249c101375b80109fa9ea2db463d946af46062d3f4b6b46f1695`.
The source parent before this commit is `def8812a8b8d55815c253b2a32eeb2f24cb5409b`.
Provider/integration/driver/checker SHA-256 values are respectively
`ae7bae002ab11e9bde1f32a0ba4fd9482575d413a7ed582ca0eba77fad23734a`,
`c5e3386fb58b9139f0a18e62b772de655fb7bd97765a2e2b708e332fa4f4fbfe`,
`b539208a9d9f501856dfc16cd17d7416b4a43e3d033da9d610b8ea82320f1896`
and `606e657cad7d8f6cf8bdd2273b8b064541d6be0e27cb788de503df8e1143df79`.

The focused run took 6.534 guard seconds, sampled 252,706,816 bytes aggregate
RSS and recorded 176,439,296 bytes detailed RSS. The compiler's largest
sampled/detailed RSS was 261,292,032/278,265,856 bytes. Every guard and child
exited zero, with complete cleanup and zero swaps, under the original 600 MiB
RSS, 300-second, 512 MiB shared-growth, 1 GiB reserve, 4 MiB output and file cap
16777216 limits. Full SDK assembly, ARM and live GMS/Maps remain separate checks.
