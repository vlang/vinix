# TrafficStats UID SDK/native and host qualification

Core source `417211d3a8698b42702b931bc2e109ab0e06258e` adds public static
`TrafficStats.setThreadStatsUid(int)` and `getThreadStatsUid()`, backed by a
private plain `ThreadLocal` independent of the existing tags. Signed int values
are retained exactly; unset/cleared state returns -1, and clear removes the
current thread's entry. Values are not inherited by new threads. Existing tag
methods and unsupported per-UID byte counters retain their behavior. This is
thread-local metadata, with no socket or kernel accounting implementation.

The focused source checker passed 20 atomic input refusals, 18 preservation
controls and six accepted formatting forms, followed by stable API-28 DEX
roundtrips. Exactly the initializer and existing clear-UID method are replaced;
two UID accessors and one private field are added. The six other original
methods and original fields remain unchanged. The producer's 33 controls and
complete SDK build passed: class membership remains 2,117, only canonical
TrafficStats changes, and all other 2,116 canonical classes are unchanged.

Paths use `S=/Users/alex/.local/state/vinix/android`. New SDK root:
`S/combined-account-webview-traffic-stats-framework-2026-11-04-r1`.
The native bundle is retained unchanged at
`S/current-native-build-2026-11-04-framework-jni-load-r1`, with its original
framework-boot SDK coupling and complete producer evidence.

| Artifact | SHA-256 |
| --- | --- |
| New SDK manifest | `bffa5dedc87d80979b09d517fcfb752b470d7f9e76a8e44bc24452f152d42025` |
| New SDK build receipt | `85da0dfe7da000decdb80655d5b0069e050bcf2d867fe1858c6af935e968db31` |
| New framework JAR | `dd3af0444459410f28d20f04928e37a19eb6b076d433498b05eac9a922b49f0e` |
| New framework DEX | `64c472412e52f91e5f40277f8077d251ee8de9b61558ecf8eec709227d97bde3` |
| Retained native manifest | `2d9c97030ab7367b487b4a7b3a6b4ed27b1cf4e68cf6567054c7ea03cc667fa0` |
| Retained native DSO | `13cf020729373ad8d20cfa4c5588c0878eee4be4fdf85700f2cf911ded08e81e` |
| Signed fixture APK | `bf1045fb4fd9c5fb468c7c59f7f594654de15cd6b54f9e07bc3f2aa4bc199cc1` |

The [native compatibility readback](traffic-stats-uid-native-readback.v) passed
721 refusal controls and complete native/old-SDK/new-SDK inventory rechecks.
All 70 native-consumed canonical classes retain identical code and declaration
shape. Two exact historical raw-formatting pairs for Resources and ATLLoadedApp
are pinned explicitly; they do not admit arbitrary normalization. TrafficStats
remains outside JNI bindings. The retained 721 exports, 58 header inputs,
91 native origins, 92 inputs and 340/660 generator/builder closures remain
covered. No replacement native library was built or substituted.

| Successful phase | Guard ms | Sampled RSS bytes | Observed growth bytes |
| --- | ---: | ---: | ---: |
| Focused source/DEX checks | 18,550 | 250,413,056 | 82,358,272 |
| Full SDK build | 30,171 | 506,429,440 | 161,333,248 |
| Complete retained-native readback | 18,049 | 57,131,008 | 28,114,944 |
| Signed fixture build | 7,755 | 98,189,312 | 3,727,360 |

These guards/children exited zero, with empty reasons and complete cleanup.
The original 600 MiB RSS, 300-second build, 1 GiB reserve and output/file limits
remain unchanged; the complete native audit retains its 900-second allowance.
The original growth caps were not increased. The initial native-checker compile
with incomplete module search paths remains preserved alongside its corrected
compile and successful readback; no historical audit was weakened.

The fixture build retains its two-class source, signed APK, API-28 roundtrips,
signature checks and complete inputs at
`S/traffic-stats-uid-fixture-2026-11-04-r1`. Its Main/Worker regression checks
public static reflection, exact signed values, default/clear, independent tags,
worker isolation and non-inheritance while restoring main-thread state.
[Delivery qualification](traffic-stats-uid-fixture-run.md) passed all five host
phases: 5,293 runner rejection cases, static ARM ELF readback, transfer build
and all original transfer tests plus six collision controls. The initial
mistyped transfer self-test invocation remains intact. Actual ARM execution,
GMS stability, Maps rendering, imagery and authentication remain unverified.

The complete host aggregate is
`S/traffic-stats-uid-host-sealed-2026-11-04-r3/sealed/manifest.json`, SHA-256
`6d6735fe5defdf92fef8b34ff833e26811622e42e7957c4a6c2c1ff5605cb3c4`.
It covers 18 roots and 8,093 entries: complete source/SDK/native/fixture/delivery
tools, outputs and controls, plus both earlier failed seal roots. Those r1/r2
attempts stopped at the original 64 MiB shared-growth cap with guard 125/child
137 and complete cleanup; all partial output and original controls remain.
The unchanged-cap r3 seal and independent fresh readback passed 0/0 with
complete cleanup in 6,679/2,337 ms, observing 30,355,456/7,909,376 bytes growth.
Original 600 MiB RSS, 900-second, 64 MiB growth and 1 GiB reserve limits remain.
Preserve every complete original bundle and its historical auditor. This seal
establishes retained storage integrity and does not establish guest execution.
