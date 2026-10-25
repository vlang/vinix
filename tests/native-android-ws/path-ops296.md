# Path Boolean operations

Base source revision: `e0c6bc0535e7a141df6530b752cc1699ad7523b2`.
Both `Path.op` overloads previously logged a stub warning and returned false.
The replacement implements difference, intersection, union, XOR and reverse
difference for the renderer's flattened polygon geometry, including winding,
even-odd and both inverse fill types.

The native sweep splits at vertices and intersections, classifies filled
intervals, cancels shared horizontal boundaries and stitches closed contours.
It emits boundaries rather than individual trapezoids, avoiding internal
edges when the result is stroked. Results use even-odd contours with the
inverse flag determined by the operation's value outside both operands.
Operands are borrowed; each successful result owns independent storage.
Java installs it only after success, including when the destination aliases
either operand. Native failure preserves destination geometry and fill.
`isEmpty()` now examines both native handles without materializing a path:
a nonzero empty result is empty, while a move-only path remains nonempty.

Work is bounded by 4,096 combined input points, 256 combined nonhorizontal
edges, 65,536 boundary segments and finite coordinates with absolute value at
most `1e12`. There can be at most 33,152 candidate Y cuts. Allocation failure,
exceeded limits and ambiguous or collapsed numeric topology return false.
This operates on existing flattened curves; it does not preserve analytic
curve segments or provide unrestricted Skia PathOps precision. An output can
exceed the input-point budget for a later chained operation.

Independent review found a cancellation bug in the first implementation:
unioning the exact-f32 triangle `(0,0), (2^-20,0), (2^39,2^39)` with empty
returned a successful empty path. The fix certifies collinearity using exact
differences/products and rejects equal midpoint crossings whose collinearity
cannot be certified. It also checks edge order at slab endpoints. The
regression requires a known interior point to survive or the operation to
fail without mutation or leaked native allocations.
The retained failing native source SHA256 is
`d2fab56ee68922b115e31e5137080c614065f02b36429577cefa974d0d308c1d`.

`path-ops-host.v` compiles production geometry with an independent winding
oracle and allocation tracking. Normal and AddressSanitizer runs passed:
22 shape pairs across all 80 operation/fill combinations, two thin-sliver
pairs across the same combinations, pointer aliasing, 30 chained unions,
independent result lifetime, empty/move-only paths, invalid inputs, complexity
limits and all 55 injected allocation failures. Shapes include partial
shared edges, vertex touches, holes, opposite/coincident contours,
self-crossings and production-flattened cubic/quadratic curves. Output
edges are probed on both sides to detect internal stroke seams; deliberate
empty-fill and seam negative controls are rejected. ASAN leak detection is
disabled; native allocation balance is checked explicitly.
The frozen host compiler SHA256 is
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`;
runner source SHA256 is
`9295550e0ce20193407db35a18ae121e72489473195a86c5766468fa0f754f96`;
harness SHA256 is
`8976b5155756cbf450e25354fb00b3740af0cc10edd2f8c412c0898ead0194b0`.

Final native source SHA256:
`a48953c3653c064c899fc4fb744b0ac25efe95be47321729476f03123186a729`.
JNI bindings SHA256:
`f92c2d320520deb5256a4ded4082ba54d79d15ba2baca490bbffd7d79857517f`.
Framework patch SHA256:
`d5c47a3f62e58617ff2974d904cdaaf61f434bc8f75d74ddd1c2c346ad599f6e`;
its `framework_paths.v` caller is
`17801169b764a20faa969e2429ff42b4eaf23bd00b828c0f1629bc2c26d35d1e`.

Native296 passed AArch64 `-O2 -Wall -Wextra -Werror` compilation with no
`v_fixed_index` references. Native293 source/runtime inputs are unchanged
apart from the new `path_ops.v` and appended JNI wrappers. Actual JNI exports
increase from 598 to 600, adding only `native_op` and `native_is_empty`.
The library SHA256 is
`ddea604e0759bf57587231ed0634f5586771c6266ed88d6bfcecb74ee73e0d0a`.

Framework296b rebuilds the frozen Framework290 inputs with only
`framework_path_ops.v` and its caller changed. Disassembly comparison finds
only `android/graphics/Path.smali` changed, with no added or removed classes.
The final `api-impl.jar` SHA256 is
`1a8e5c929c23f842561fbe2ea30f403327a317d3b27984c0280b9dd509b74200`.

Evidence is retained outside Git under
`/Users/alex/.local/state/vinix/android/`:

| Bundle | Manifest SHA256 |
| --- | --- |
| `path-ops296-native-build-2026-10-25` | `a27c6341933371e7c0e70dfa6de1b8ce3ab67d5acb69d2e6ea0ed27bb0a36f87` |
| `path-ops296b-framework-build-2026-10-25` | `b8d69c2b136873eb75d8891099295cf6b99d56e6144fdae394771d87078442e5` |
| `path-ops-host296-final-2026-10-25` | `f3ac11a06896f068c18bfca484f9b0332c2ce734f78e0dec5744cf5f2d825544` |
| `path-ops-host296-final-asan-2026-10-25` | `34cb61aa5f20d2302de5d4cf7bd70f91ce0683d45ba735d73b340d80e3f5b2d4` |
| `path-ops-host296-numeric-2026-10-25` (pre-fix failure) | `106e922f68f091af0a773a667505467999820147da9546ff02d4d5f06dd35a75` |

Independent exact-fileset readback passed all 2,407 native-build files and
6,957 framework-build files. Independent readback of both final host bundles
passed all 22 artifacts in each; the host verifier also rejected an incorrect
manifest pin. The pre-fix failure bundle retains 21 artifacts.

Host bundles retain sources, harness, runner/compiler, generated C, arguments
and logs; they do not claim a complete historical host C/SDK/V toolchain closure.

## Guest297c

The same signed APK passed the expected old/new results in separate 45-second
guests. Old Framework290/Native293 emitted exactly one expected-stub marker;
Framework296b/Native296 emitted exactly one each of MATRIX, SHAPES, ALIASES,
CONTRACTS and the final PATH-OPS-PASS markers. Both emitted TRACE-ENV-ABSENT
and BOOTSTRAP-READY exactly once. The changed guest covers 255 Boolean cases,
including `isEmpty`, plus fresh/reset, inverse-empty, move-only, builder,
published and copied path states. Both suite processes exited zero and shared
inputs matched before/after. Only the framework JAR and native library differ;
the signed APK, clean launcher, runtime and initial boot/firmware media match.

The APK SHA256 is
`ae23d44f323ee960a86bc0f49161209249e25c9ee323e7d8e1d9aa0b6801f829`.
The unchanged launcher SHA256 is
`406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0`.
Both unchanged historical classifiers report `window_observed`,
`functional_passed: null` and no failure markers; the fixture's separate
semantic checks report `expected-result-pass`.

Completed evidence: `path-ops297c-fixture-2026-10-25`, manifest
`7511a2dcf20e811fd616f7a006f7d389b8930eff838c3f68ab08958b049876af`.
Independent exact-fileset readback passed all 590 files, including a second
readback recorded in `path-ops297c-root-readback-2026-10-25.json`.
Old/new serial SHA256 values are respectively
`74d521932940062f3db631081e3c76e3813ff87e61ed32641b5cf2546bca81cb` and
`7ea2915f9fcd1a8e5686cba9eab839ce5ffe789280a11669f1cc82d4c41a8a37`.
Old/new raw results SHA256 values are
`0de18269bdab6ff4e2f280d6061f72e75663ebcb5c47e8160894309930629288` and
`2b3d8e699338318bb254423ca921c366b38592955c5983e3e069de2b4d383d89`.

Prepared-only Guest297 is retained with manifest
`f9b68402622a7e606c80d673f23aa22b3b84f7800611fab1518049c7599dc9c2`.
Guest297b exhausted host disk space while recording the baseline suite;
the changed guest was never launched. Its complete 503-file partial bundle
is retained and independently read back under
`path-ops297b-fixture-2026-10-25`, manifest
`896777e7ea36affd50fa667b39949380a9d497263e2a91f15b57e97f492b104f`.

## Maps298

Maps298 exhausted host disk space during preparation, after writing the
runtime archive and matching its producer/FAT readback hashes. No launch
configuration or guest was created. Its complete partial target, both build
bundles, runner build and failure sealer are preserved under
`maps298-2026-10-25`, manifest
`4b56d716ae4debcd967dac3861b3d3ad18f7ca214d98c8d6023dea7edf2de039`.
Two complete readbacks passed all 21,090 typed entries.

## Maps299

The fresh runner is derived from the frozen Maps298 source by
`maps299-generate.v`, changing attempt names and its generated source path.
`maps299-build-check.v` independently verifies that derivation, all 272
actual V dependencies, retained/live source hashes, the compiler and C
compiler, recorded arguments and the resulting binary. The generated source
SHA256 is
`0dd0b9acfa91f5d10e944c61be934978a84a78e1aac1088fa673f5305b3c6ced`;
the recorded runner binary is
`f973b89016304d8646705511b77d132709674e5b1889a019ba445c89860c4922`.
Its build is retained in `maps299-run-build-c-2026-10-25`.

Before launch, all 109 runtime regular files and 304 typed module entries
matched Maps295 except the framework JAR and native library: 107 regular
files were unchanged. The launch record SHA256 is
`1c94c4803a0ae5287a4d2409966c136307012fac969718a893729d58af08e835`;
the prelaunch manifest is
`cc3157db272594e15312b42cf1a7fe6905c7ff811302866d3d4c46f8b5072e21`.

Reviewed screenshots show Skip leaving onboarding, the North America map,
Paris search suggestions and its place card, an Eiffel Tower starting-point
search, a blue driving route to Paris showing 14 minutes, and route preview.
The preview begins with “Head toward Pont d'Iéna”; Next changes it to
“Turn left onto Pont de l'Alma” at 750 m, and Previous restores the first
instruction and map position. These are manual visual observations; pixel
probes only decide when to interact. The retained `interaction.log` records
commands and timestamps, with screenshots including `onboarding.png`,
`map.png`, `paris-suggestions.png`, `paris-card.png`,
`eiffel-suggestions.png`, `route-loading.png`, `preview-first.png`,
`preview-next.png` and `preview-previous.png`. Next and Previous also
responded after several minutes idle (`preview-next-late.png` and
`preview-final.png`, captured at 07:37–07:38 UTC).

The unchanged suite completed its full 600-second observation and exited
zero. Its raw classifier remains `window_observed`,
`functional_passed: null`, `native_maps_observed: true`,
`process_exited: false` and `qemu_alive_before_capture: true`, with no
failure markers. Manual UI checks above are separate evidence; this does
not establish continuous navigation or a comprehensive Maps conformance pass.

The complete bundle is `maps299-2026-10-25`, manifest
`f364979f7d7b20cc449bbccd927f9c6f9bb034eb9cce08c5e38d26baffb91daf`.
Two complete readbacks passed all 22,760 typed entries; root also rejected
a wrong manifest pin. Raw serial SHA256 is
`f54417d3ebb8f37627c34351a388b6058521e49dd25c41bc12a6182529b6d2cf`;
raw results SHA256 is
`bba0a25e5c01b0b7c358ce084871b754dc77850bddf1cf50fafd1356ed43e0f1`.

`maps-path-op-audit.v` authenticates both sealed serial/results pairs and
compares literal diagnostics without changing either classifier. Adjacent
`Path` / `STUB: op` warning pairs drop from 65,949 in Maps295 to zero in
Maps299; all `STUB: op` lines drop from 65,952 to zero. Both runs contain
zero matches for the audited fatal, JNI/linkage, missing class/method/field,
out-of-memory, dependency/process failure and process-exit markers. This
measures logged warnings, not the success rate of every native operation.
The six-artifact audit bundle `maps-path-op299-audit-2026-10-25` passed
complete readback, manifest
`145eb21be2acce09940b7b8f844a97548bab7c8da1b080342509e53f2e22819c`.
