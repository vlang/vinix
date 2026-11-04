# Process package-list host qualification

Host qualification passed for the field-only SDK and freshly coupled native
provider and delivery tools. **Live ARM execution remains pending.**
This report establishes no GMS stability, Maps rendering, imagery or
authentication result.

Source commits are `2443f94f06ce4746b2838837a295e262e95453c9` for the public
`RunningAppProcessInfo.pkgList` field,
`9071f1164a6e60ba3b71c267daa1a85c9c8b9135` for its SDK producer, and
`24f6064594c10ed24907b861f364144d83593642` for native self-process snapshots.
The field is a public mutable instance `String[]`; all eleven original fields,
three constructors and other metadata are preserved. An empty info object keeps
the Java null default. Native enumeration creates a fresh one-element array
from the primary package's actual `packageName`, independently of `processName`.
`getMyMemoryState` and its native helper remain unchanged. This represents
Vinix's single primary process, without asserting companion or global process
liveness.

Paths use `S=/Users/alex/.local/state/vinix/android`. The completed SDK is
`S/combined-account-webview-process-packages-framework-2026-11-04-r2`; the fresh
native producer is `S/current-native-build-2026-11-04-process-packages-r1`.

| Artifact | SHA-256 |
| --- | --- |
| SDK manifest | `4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d` |
| SDK build receipt | `a72f6b55ea908182d7d4fd331a71290c62eb8367cc9cd3250d6eefb65b696335` |
| Framework JAR | `875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8` |
| Framework DEX | `6e7f03d2fe6951d172f04bbd67993f9e8e00f23a4e794994849b3555e8d77837` |
| Native manifest | `0b8ad44d408b90824a69fa7d42c9376965eaa34a93dc81b056050ef227bc3d7f` |
| Native build receipt | `b2235db3cebb559f8aef6aea9693beaea4db59022c2cbca89e9cdb7e548e830b` |
| Native DSO | `b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f` |
| Complete generated C | `e04800dcc13f7dddfa34ee3e135cf7c9df1acba33b2cc6bb7f6983555dcd8aa8` |
| Native readback receipt | `bd46ca974731051a95a3a02fad972d3148f50509a13c95de7bdf90336a2fce70` |
| Signed fixture APK | `db555d086522f003e912e3de5fcf0905d3079025c92397c7b92c6ba714d497e7` |

The focused source check passed 28 atomic input refusals, 18 preservation
controls, eight formatting forms and stable API-28 DEX roundtrips. The producer
passed 30 field/class controls plus four transitive-helper controls. Its final
source SHA is
`7381929ba53f75bfc669df52fac317a43f8ffecfce11ed73fafc3fdf4dc07f81`.
Class membership remains 2,117; only canonical RunningAppProcessInfo changes
relative to the TrafficStats parent. The other 2,116 classes, including
TrafficStats and all 70 native-consumed classes, remain unchanged.

The [fresh-native readback](process-packages-native-readback.v) passed 765
refusal controls and complete before/after inventories of both native bundles
and the original, parent and successor SDKs. The old native keeps its original
framework-boot SDK coupling; the new native couples directly to the successor.
Only `importance.v` changes among the 91 native origins and 92 inputs, and only
`ws_running_processes` changes in generated C. The independently reviewed C
function hashes to
`d43aed9f589856ee5877c4a9ec4b843dc68459eab6a06a4c28c5a911dd1e4f2a`.
Its local frame releases temporary references on every exit and promotes the
returned list. Bindings, generated JNI, 721 exports, ELF dependencies, compiler
inputs and the 340-input generator closure remain unchanged. The 660-input
builder closure admits only the two exact reviewed ActivityManager and
TrafficStats provider pairs. Among 58 C/header inputs, only generated C changes.
The two exact historical Resources/ATLLoadedApp raw-formatting pairs retain
identical canonical code. The final reader source and successful frozen copy
both hash to
`d10cfa3b653a4d5eea88832d7eff76d1815159d0657a6f479c3c87eb7cb7774b`.
The production receipt is at
`S/process-packages-native-proof-2026-11-04-r1/readback.json`.

| Successful phase | Guard ms | Sampled RSS bytes | Observed growth bytes |
| --- | ---: | ---: | ---: |
| Focused source/DEX checks | 11,718 | 194,822,144 | 65,302,528 |
| Full SDK r2 build | 18,105 | 492,683,264 | 244,965,376 |
| Fresh native build | 42,260 | 565,018,624 | 463,450,112 |
| Final reader compile | 5,862 | 485,326,848 | 2,633,728 |
| Complete native readback | 5,555 | 60,620,800 | 139,264 |
| Signed fixture r2 build | 8,838 | 99,172,352 | 112,967,680 |

These successful guards/children exited 0/0 with empty reasons and complete
cleanup. The 765-control reader self-test passed in 226 ms. Recorded limits are
600 MiB RSS, 300-second builds, 900-second complete readback, 1 GiB disk reserve
and 4 MiB supervisor output. Growth limits remain 512 MiB, with the native
producer's existing 1 GiB allowance.

The signed fixture is at `S/process-packages-fixture-2026-11-04-r2/probe.apk`.
Its host checks cover signing, two-class Main/Worker packaging, signed-manifest
identity and DEX roundtrips. The actual manifest process is
`org.vinix.bootstrap:process_packages`, distinct from package
`org.vinix.bootstrap`. The regression encodes checks for null default, native
self PID/UID/package metadata, fresh records/arrays, mutation isolation,
caller-owned arrays through `getMyMemoryState` and a bounded worker. These ARM
behaviors have not yet been measured. The [delivery recipe](process-packages-fixture-run.md)
now binds the qualified runner and transfer. Host tests rejected 5,503 cases;
static ELF readback confirms AArch64 EXEC without INTERP/DYNAMIC segments.
Transfer qualification passed all historical cases and six new collision
controls. The ARM runner hashes to
`725710de6957816c0ece03008c54bf3ca78bc31635d9495c18a04a922f12d21f`;
transfer hashes to
`495ac838ee5bda910c18732fc4739332d836440d037b1fb8f41cca662c3af358`.
The five initial delivery commands omitted the explicit shell file-size cap;
all five were repeated successfully with zsh `limit filesize 16m` (16MB), retaining both
sets of controls. Requalification guards/children exited 0/0 with complete
cleanup under the original RSS/wall/growth/reserve/output limits. The repeated
static runner matches the original pin. Exact repeated metrics and frozen
source identities are recorded in the delivery report; this is host
qualification, not ARM execution.

Preserve all failed attempts and their original controls. SDK r1 stopped at
provider compilation because the full ActivityManager source also required
`interface_class`; r2 captures the complete `framework_classes.v` input and
extracts that exact helper. Fixture r1 stopped at its signed-manifest process
attribute assertion; corrected r2 passed. Both failures exited 1/1 with cleanup.
Two source-driver compile preflights, four diagnostic-reader compile preflights
and one final-reader compile preflight refused on the original disk growth or
reserve rules. Those receipts record guard 125, child -1, PID 0 and
`cleanup_complete=false`; no child was launched. They are not successful
cleanup receipts. A malformed `compile-r5` wrapper invocation also failed
before writing a supervisor receipt; no child or cleanup status is inferred
for that invocation. Diagnostic extraction at
`S/process-packages-native-inspection-2026-11-04-r1` is explicitly marked
`qualification=false`; only the later fixed-pin production readback qualifies
the pair.

Retain the complete `process-packages-source-{tools,controls,check}-2026-11-04-r1`
roots; SDK tools, controls and outputs for r1/r2; native producer and controls;
native reader tools/controls for r1/r2, inspection and production proof;
fixture build, controls and outputs for r1/r2; and the complete delivery build,
output and control roots. Braces denote separate existing roots below S.
Also preserve the complete original native, framework-boot SDK and TrafficStats
SDK producers required by the historical auditors.

The complete host aggregate at
`S/process-packages-host-sealed-2026-11-04-r1/sealed/manifest.json` hashes to
`bbb1d713abc911a85bc7628975f4540bb889dd6b6a2c85a5fbd413e17c3da93f`.
It binds 27 complete roots and 15,042 entries, including failed outputs and
controls plus the completed delivery artifacts and capped requalifications.
The seal passed 0/0 with complete cleanup in 2,654 ms, sampled RSS 27,017,216
bytes and observed growth 5,341,184 bytes. The independent fresh readback passed
0/0 with complete cleanup in 722 ms, sampled RSS 23,429,120 bytes and observed
growth 1,314,816 bytes. Both retain the original 600 MiB RSS, 900-second,
64 MiB growth, 1 GiB reserve and 4 MiB output limits. The first separate
readback used the incorrect `check --sealed` CLI and exited 1/1 with cleanup
in 57 ms; its original guard/log remain beside the seal. The corrected
`check --out ... --pin ...` invocation performed the successful readback.
This establishes retained host evidence integrity; live ARM execution remains
separate and pending.
