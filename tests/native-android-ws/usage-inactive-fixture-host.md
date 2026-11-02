# Disabled AppStandby query fixture

The standalone fixture exercises public instance
UsageStatsManager.isAppInactive(String) returning primitive boolean. Vinix has
no AppStandby classification or enforcement backend; false describes disabled
policy rather than measured recent use, foreground activity or a permission
grant. The fixture contains only its application Main class and declares minSdk
28, with no platform manager stub or SDK override.

Real typed service lookups through Activity and application contexts and the
existing public no-argument constructor provide the managers. The fixture checks
the exact manager class without requiring cached or distinct manager identities.
Each query run exercises own package from the actual context, GMS, Maps, unknown,
empty, null and Unicode package arguments for 32 rounds. Seven query runs cover
six typed lookups and one direct constructor, for 1,568 actual isAppInactive
calls. Legacy string `usagestats` discovery must remain null before and after
each service sequence. No generic manager subclass or fake usage backend is used.

Reflection checks the public instance method and exact String/primitive-boolean
descriptor. Every real call must return false, including malformed or unknown
package arguments; the disabled-policy path does not perform package lookup.
Independent source review checked register/loop dataflow and exception ranges.
The manager and own-package parameters remain intact across loop iterations,
and the catchall uses only its separately captured Throwable.

The V builder preserves the complete source/tool closure, exact one-class
membership, API-28 assembly and two canonical disassembly rounds around
reassembly, v3 signature, signed manifest floor and exact signed DEX extraction.
Unicode source assertions accept the equivalent canonical escaped spelling.
Builder compile and signed production passed on their first attempts. Exact
one-class membership, both canonical trees, signed manifest minSdk 28 and v3
signature checks passed. Production, roundtrip and signed-extracted DEX bytes
are identical. Original inputs were rehashed at completion and current V
sources match their frozen copies. Independent final artifact review is
separate from ARM verification and execution.

Paths use `S=/Users/alex/.local/state/vinix/android`. Complete fixture and control
roots are `S/usage-inactive-fixture-2026-11-02-r1` and
`S/usage-inactive-fixture-controls-2026-11-02-r1`. The immutable build records
source revision `ac92c061fb522ce08105e2e4060df8f4666aa3f8` and source hashes
`bb237fdf2337315b5644df3c255adebd477c40f119178e740c4c9d8e7b8181f9`
for main.v and `04d1e56ed93cf20287aa73e0da036564853e16e6a911b59a957b15ade2bb0305`
for sources.v.

| Artifact | SHA-256 |
| --- | --- |
| Signed probe.apk | `ae580b4c0ed99b97787f552d8e6f08a94daeed137fc346440cea832a7795a3d2` |
| Build receipt | `beee74016585a4a814d7dcb41573ef4e0b4e983adf8e23659767af27d571dc78` |
| Production / signed-extracted / roundtrip DEX | `b8bc5cde7e32cf6d1a0827f1a90ed429ada2dfea00e175dd6741b291506222d6` |
| Both canonical Main classes | `36eb66e73641fddac2f76e2b5eab7c6208fa355a0c969d4ca40da7099e4ea0a8` |

Both guards and children returned zero with empty reasons and complete cleanup.
Compile elapsed 1.264 seconds, sampled RSS 319,471,616 bytes, detailed maximum
357,695,488 bytes and observed growth 1,343,488 bytes. Production elapsed 5.809
seconds, sampled RSS 86,278,144 bytes, detailed maximum 93,536,256 bytes and
observed growth 18,558,976 bytes. Both time records report zero swaps. Limits
stayed 600 MiB aggregate RSS, 300 seconds, 512 MiB observed growth, 1 GiB reserve,
4 MiB output and shell file cap 16777216. The compiler lane was released after
actual completion.

The terminal marker is:

```text
USAGE-INACTIVE-PASS public-instance typed-service constructor arbitrary-packages null-empty-unicode repeat-32 legacy-service-null disabled-policy
```

ARM execution, application usage history, access permission enforcement, Google
Play Services, Maps and authentication remain separate checks.
