# Stats unavailable-service fixture host qualification

The standalone signed fixture passed host qualification on 2026-11-02. Its build
records source revision `de010b96c859570c5c914e90d02484c665e947b9` and retains the
exact two V source files in the evidence bundle. ARM execution remains required.

The one-class APK checks real `StatsManager` class identity, repeated string and
typed null service queries through Activity and application contexts, and the
audited GMS-style null-cast early-false/early-void paths. A known
DevicePolicyManager lookup checks the existing cached string/class fallback.
The same loaded Main class contains an uncalled `StatsManager.removeConfig(J)V`
reference and a typed catch of `StatsManager$StatsUnavailableException`. The APK
provides neither platform definition. These unresolved references must remain in
the runtime test; host assembly does not establish ART verification behavior.

The generator verified the exact Main-only class closure, API-28 assembly, two
stable canonical Smali/DEX roundtrips, the exact unresolved method/catch tuples
and absence of any call to the dormant method. APK v3 signature verification,
unique archive membership, signed DEX extraction/readback, and unchanged source
and tool inputs all passed. No telemetry backend or simulated backend success is
supplied. Preserve every actual ART verifier and runtime health diagnostic;
runtime acceptance must not whitelist verification failures.

Evidence is external under `/Users/alex/.local/state/vinix/android/`:

| Artifact | Path relative to evidence root | SHA-256 |
| --- | --- | --- |
| Signed APK | `stats-unavailable-fixture-2026-11-02-r1/probe.apk` | `a0742e010e52dd042500a6811fddc6fe369b28852a85bfd22987dbb0c894a4dc` |
| Build receipt | `stats-unavailable-fixture-2026-11-02-r1/build.json` | `dc708735955aedc4fff17b5932a280e4e5340e0eccc093a816eb5824988ec320` |
| Checked DEX | `stats-unavailable-fixture-2026-11-02-r1/classes.dex` | `0183a34db6571c6269825ea8fc0e655d25d6ce55e2329c7f102aeeef36900eb6` |
| Generator source | `statsunavailablefixture/main.v` in Git and retained `inputs/main.v` | `d1db0256d8b31ddc7306bdb4c25035b827a77b6d61885fec8848d3b137237592` |
| Probe source | `statsunavailablefixture/sources.v` in Git and retained `inputs/sources.v` | `077dc39e356e0e68a6c3d4c8955e05edb0903d645de628ebd382ca295ecc6bf5` |

The compile and production guards are retained in
`stats-unavailable-fixture-controls-2026-11-02-r1/`. Both returned actual exit 0
with cleanup complete. Compilation took 1.615 seconds, sampled 312,754,176 bytes
RSS, and `/usr/bin/time -l` recorded 358,252,544 bytes maximum RSS. Production
took 5.862 seconds, sampled 88,719,360 bytes RSS, and recorded 92,717,056 bytes
maximum RSS. Both recorded zero process swaps. The unchanged limits were
629,145,600 bytes aggregate RSS, 300 seconds, 536,870,912 bytes shared disk growth,
1,073,741,824 bytes free reserve, 4,194,304 bytes output, and shell file-size limit
16,777,216 blocks. The compiler lane was released immediately after production
exit 0. Both evidence roots are closed.

The sole runtime success marker is:

```text
STATS-UNAVAILABLE-PASS class-identity string-null typed-null early-returns dormant-references service-fallback repeated-queries
```

The failure marker is `STATS-UNAVAILABLE-FAIL`; the fixture rethrows its original
failure after printing it. Runtime identity, runner/transfer qualification and
future ARM receipts belong in `stats-unavailable-fixture-run.md`.
