# Framework boot fix: host checks passed in part; runtime blocked by disk space

The framework-boot fix is implemented and its SDK/native pair, signed fixture,
delivery tools and inventory batching are committed. The new fix has **not**
run on ARM or in GMS/Maps. Image qualification and preparation remain incomplete.

| Completed work | Commit |
| --- | --- |
| Native boot visibility and absolute JNI loading | `992b426c3` |
| SDK system resource loading | `a16baf6c3` |
| Full SDK/native pair qualification | `399af92a1` |
| Signed boot-classpath regression fixture | `63ba81754` |
| Fixture runner and transfer qualification | `133c69c0a` |
| Complete 134-inventory batching checks | `b193168ff` |

The [qualified pair](framework-boot-pair-2026-11-03.md) uses SDK manifest
`af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91`
and native manifest
`0a6d8126bd0842985123578550fc3fa60c0eb12543e8fcf680d1644f6b49f81f`.
The fifteen-root producer seal, including the signed fixture and retained
failed checker evidence, is
`97d2b432a3be23d570070e7be954a29dbe67c95984748e40037f5bbb14f669a7`.
The four-root [delivery seal](bootclasspath-fixture-run.md) is
`de7342dd6b921e89e96d3a3ab15d3dbf911612ebb7b232fe1db4c78d4a82271d`.
Both seals passed separate fresh-process readback; all original bundles and
auditors remain required outside Git below `/Users/alex/.local/state/vinix/android`.

Stager V/C builds, selftests, complete SDK/native admission and native helper
enumeration passed with guard/child exits zero and complete cleanup. These
five phases used an explicitly stricter 128 MiB host-growth budget while
preserving 600 MiB RSS, 1 GiB reserve and the original time/output/file caps.
The full gate checked all 2,117 SDK classes, exact SDK/native source deltas,
all 70 consumed classes, C/header/JNI/export and complete helper closures.

The corrected patcher V/C builds passed. Its full selftest stopped at the
original shared-volume growth cap after 52 profile checks and 40 FAT passes:
guard 125, child 137, complete cleanup, 93,325 ms and 544,804,864 bytes observed
growth. No functional failure appeared; the complete FAT suite has not passed.
An earlier test-only V ownership refusal and both source/input attempts remain
preserved. No unchecked image feature code was committed.

Before ancestry generation, read-only `df` reported 1,116,635,136 bytes free.
The phase was refused before invoking a guard or child. A later root read-only
snapshot reported 706,727,936 bytes free, below the unchanged 1 GiB reserve;
the two observations have no retained exact timestamps.

| Unchanged admission requirement | Required free bytes |
| --- | ---: |
| Host phase with stricter 128 MiB growth and 1 GiB reserve | 1,207,959,552 |
| Full FAT suite with 512 MiB growth and 1 GiB reserve | 1,610,612,736 |
| Image preparation initial-space gate | 5,368,709,120 |

Complete partial evidence remains in `maps-framework-boot-tools-2026-11-03-r1`
and sibling `maps-framework-boot-inventory-batches-tests-2026-11-03-r1`.
The tool root retains original `sources`, corrected `sources-r2`, both patcher
input lists/projects, every guard/log and full `patcher-selftest-r2-scratch`.
Its original `qualification-pending.md` is unchanged; the final handoff is
`qualification-pending-final.md`. Tool sealing and final complete input capture
remain pending, with the tool root retained for resumption.

Five candidate paths remain uncommitted pending full qualification:
`maps-framework-boot-stage.v`, `maps-framework-boot-ancestry.v`,
`maps-framework-boot-stage.md`, `../android-webview-browser-probe/patch-kernel.v`
and `media-stage-inputs.v`. Ancestry compilation/checks, full input discovery
and capture, FAT completion, final review/sealing, image preparation, signed
ARM execution and GMS/Maps retry remain required. All task processes are closed.
No resource cap was raised, input skipped or evidence deleted.
