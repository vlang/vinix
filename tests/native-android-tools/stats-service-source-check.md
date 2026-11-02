# Unsupported stats service type and lookup

`android.app.StatsManager` is now a loadable public final, memberless type.
Typed Context lookup explicitly returns null before the generic reflective
manager fallback; string lookup for literal `stats` already returns null.
Every existing ContextImpl method and fallback is preserved, with one early
typed-lookup guard. No StatsManager constructor, backend method, nested exception,
field, Context constant, native binding or telemetry success is added.

This follows [Context's unsupported-class null contract](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r1/core/java/android/content/Context.java#L3528).
[AOSP's registered StatsManager wrapper](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r1/core/java/android/app/SystemServiceRegistry.java#L514)
is separate from daemon availability. This guest leaves that service unsupported;
it does not emulate AOSP's registered wrapper with an unavailable daemon.

The actual fatal stack reaches `fojo.e`, then `InitOperation.b` source 393.
`fojo.e` gets `stats`, check-casts at `0xb`, then returns false for null at
`0xf`/`0x10`, before telemetry paths. Its immediate post-call helper `foli.s`
also check-casts and returns when null. Nested StatsUnavailableException catches
and add/remove/config/report operations occur in separate dormant methods.
The signed ARM regression retains a same-class, never-invoked
`removeConfig(J)V`/missing-nested-catch tuple so ART verification behavior is
tested explicitly. That ARM result is pending; the host checks cannot establish
it. GMS failed while idle in this run; Maps was not launched.

Source parent: `de010b96c859570c5c914e90d02484c665e947b9`. Tested source hashes:

- `framework_stats_service.v`: `d1734c0fda11623626ae44fecc8ea7465a31bd5411aef448b480bb88efd7e0db`
- `framework.v`: `3b7fe1b44ec684cba2e307788a949abe82d663c09b8d038c91480fb11f8c25d0`
- `statsservicecheck/main.v`: `b064e8a86f3b55816d05d9bfc55154c09cadf80f82df6085298d5101da8233c8`
- `stats-service-source-check.v`: `44274986064049a72debb27f7464d6096435cde8c1c1c29c2fac680b7fcf8470`

Focused checks passed 50 malformed/repeated/collision refusals and four independent
output controls. They bind canonical and exact raw preceding-provider labels,
preserve ContextImpl metadata/all other methods, compare every retained fallback
instruction with normalized branch labels, and require the exact memberless
marker. Existing regular-file, directory and dangling-symlink type collisions
remain unchanged on refusal; validation precedes all writes. API 28 assembly and
both DEX roundtrips retain exactly one original/two successor classes and stable
second-roundtrip bytes. Independent provider/checker source reviews passed.

Evidence under `S=/Users/alex/.local/state/vinix/android`:

- `gms-stats-manager-method-audit-2026-11-02-r1`: complete three selected classes,
  input/tool pins, guarded argv and detailed logs. Audit SHA-256
  `25f6f4de554379c68cad6e3d5a2a59c26d2b7407d3c6090f0ae26e415250185a`;
  checksum-list SHA-256
  `96ef253291f3b63d593a4587c4ec6c95506c916ec683b22b62f2b2cc1ac6057e`.
  The preserved first helper filter selected the wrong DEX and produced no class;
  the fresh corrected extraction supplies the inventoried class definition.
- `stats-unavailable-source-check-2026-11-02-r1`: frozen sources, generated host
  project, refusal cases and original/patched DEX/roundtrips. Final receipt
  `feb949ce1b6a437224be9897ecebb2fe035728f003d29fe53014ef5505fc38e2`.

All host guards and children exited zero with complete cleanup/zero swaps under
the unchanged 600 MiB RSS, 300-second, 512 MiB growth, 1 GiB reserve and output/file
caps. Maximum sampled/detailed RSS were 268,615,680/278,151,168 bytes. The focused
run took 6.888 seconds with 21,540,864 bytes observed shared-volume growth.
Complete SDK production, retained-native equality, ARM verification and live GMS
retry remain separate checks. No authentication or imagery result is claimed.
