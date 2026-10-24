# Maps267: partial padding and minimum-size replay

Maps267 observed onboarding Skip and Paris search/place details with the paired266
relative-padding and TextView minimum-size changes. The operator missed the manual
route window during compaction. Directions was opened at 19:33:03 UTC, but no origin
was entered; the final application frame shows directions entry with an empty
origin. This attempt provides no complete directions, advancing route-preview,
route-geometry or full visual pass. Maps263's earlier completed route evidence
remains unchanged.

The suite started at 19:29:31 UTC on 2026-10-24; its QEMU launch receipt was
recorded at 19:30:36. The configured 240-second observation completed naturally.
The original Maps256 classifier remains
`startup_failed`, with `functional_passed: null`; launcher, backend-ready and native
Maps markers were present, and QEMU was alive before final capture. Classification
is separate from the observed UI. The final serial bytes were captured after
bounded final capture and QEMU termination/wait; gzip round-trip and recomputed
classification were verified against the retained result.

Skip was clicked at 19:31:10. The unique `after-skip` frame was captured at
19:31:48; Paris suggestions at 19:32:25; Paris details/loading at 19:32:41; and
loaded Paris streets/boundary at 19:33:02. The automatic `application` frame was
captured at 19:34:50. These five frames and every original ordinary run output,
command stream, supplemental log and stopped private-media image are retained.
`route-ready`, `route-first` and `route-next` are explicitly absent. The manual
timeline, findings and frame digests are retained in `audit/manual-review.json`.

The unchanged [`maps-geometry-evidence.v`](maps-geometry-evidence.v) strict checker
was actually invoked first with the five observed frames. It rejected collection
for missing `route-first` and left all collection destinations absent. Its frozen
source, executable, before/result receipts and rejection log are preserved. The
distinct [`maps-geometry-partial-evidence.v`](maps-geometry-partial-evidence.v)
archives this incomplete replay: it requires the exact five observed frames,
the three absent route-frame predicates, every complete unique258 command stream,
successful matching end records, all original provenance and the unchanged
classifier. An archive check never asserts a successful route or visual result.

Preparation revision: `e6bfb9327ddc4654fba82695b45ab5269d24a070`; collection revision:
`b5188cbaa83fb3516f44ddea25b9a859b7ce643f`.
The 109-file runtime differs from frozen Maps256 only at the paired266 framework
jar and native library. All 125 framework and 83 native sources, six actual
before/completed build receipts, 73 original inputs, signed Maps APK, production
identity256 launcher, unique258 driver, tools, runtime inventories and FAT archive
readback are preserved. Framework SHA-256:
`69f560aef5965acd2e4c1eba35a545dae5c8e48708695b0c747a1267d75643c3`;
native SHA-256: `0a9928b59585bc7e1d6518c22a9a388f5bb99e4f43f3c0838d6c1c47588fb680`.

Complete external archive:
`/Users/alex/.local/state/vinix/android/maps267-prelaunch-2026-10-24`.
The independently checked prelaunch inventory has 3,663 entries and pin
`fdfbef9ad7b620cecc60cc621f62074a4a98e5822a4f36a6eff003c572edeb77`.
The final complete inventory has 3,867 entries and SHA-256
`46edb8a94db8e47c6a244f31fc3a66f6d03fff9895e8884481287e96dbfb6122`.
The independent full check and wrong-pin/incomplete-bundle rejection tests passed.
Their before/result receipts, logs, seal result and negative fixture are preserved
in `/Users/alex/.local/state/vinix/android/maps267-partial-validation-2026-10-24`
(16 entries; manifest SHA-256
`8f837461f1ab19e37c5f0922c43043f285f1449df37ae8b8202202ee60707a63`).
The checker independently verified all inventory bytes, complete runtime FAT
readback, serial/classifier bindings and the complete unique command streams.

Four complete immutable tool workflows are retained under `audit/build-validation`:
strict checker (23 entries), partial checker (24), replay helper (42) and actual
preparation/full-check receipts (8). The partial checker was compiled with
assertions enabled; parser positives and ten rejection cases, original-classifier
byte comparison, deliberate assertion failure and production-binary refusal all
passed. Its source SHA-256 is
`b046072515a5c65ceab77a9ffb8d6160a3ed2692f1d81fdb7788ec201f95a42d`,
and executable SHA-256 is
`696cd99c45124365ef893ab7f5e83b8dc1d507c6c07b590b3752c37334cabcd7`.

From the repository, recheck the complete bundle with its retained executable:

```sh
/Users/alex/.local/state/vinix/android/maps267-prelaunch-2026-10-24/audit/maps-geometry-partial-evidence check /Users/alex/.local/state/vinix/android/maps267-prelaunch-2026-10-24 46edb8a94db8e47c6a244f31fc3a66f6d03fff9895e8884481287e96dbfb6122
```

Maps261's prelaunch bundle remains sealed and unlaunched. Maps265 was neither
prepared nor launched after paired264 generation failed before any VM. Maps267
does not measure GPS, sign-in, voice navigation, 900-second endurance or independent
post-drop identity. Suggestion-circle rendering and further CompoundButton text
alignment remain separate work.
