# Compact configured-repository recovery

The compact Configured repositories view exposes **Reload list** when no child
or trust review is pending and the canvas has room for the row (height 130 or
more). After a stopped, failed or malformed list read, users can retry from the
same compact view. The existing public `--json repo-config` read retains previous
valid identities and literal editor fields until a valid replacement arrives.
The failure-details row also requires enough room after the new action.

At the 180×96 minimum fallback, Back/Stop/Cancel and status remain bounded;
secondary actions appear as height permits. Unaccepted reviews retain Cancel
and their reader, and approved enrollment, revocation and catalog refresh keep
their existing protected worker lifecycle. Compact views never expose trust
confirmation.

The maintained V fixture `software_repository_recovery_fixture.v` uses explicit
error checks, including all side effects, under production optimization. Its
private child service covers partial output and complete output held before
exit, nonzero failure and malformed JSON. It activates the actual rendered
Stop and Reload controls, verifies child reaping and exact retained identities,
selection and literal ID/Unicode URL/key drafts, then admits a fresh valid list
and prepares a new review. Separate real accepted enrollment/revocation children
and a refresh child exercise busy navigation guards. These deterministic replies
do not provide publisher authority or qualify administrator authentication.

Nine compact/tiny canvases include 320×240, 400×300, 180×96, 180×129, 180×130,
180×167, 180×168, 180×220 and 319×239. The fixture checks every element stays
within the canvas, pairwise element separation, action visibility, protected
states and progress/status geometry. Heap variants use positive and balanced
allocation controls before 1000 render cycles (9000 trees).

Run the source-bound driver with an external executable and fresh output path:

```sh
v -backend c -prod -o /external/software-repository-recovery-check tests/packages/software-repository-recovery-check.v
/external/software-repository-recovery-check /path/to/v /path/to/vmodules /external/fresh-repository-recovery
```

The driver freezes project and UI source inventories and preserves actual
implementation/fixture inputs. It stages a private entry dispatch ahead of the
historical assert-based main; those old suites are not executed. The shared
`software_hosted_fixture.v` fails if a headless test reaches hosted graphics.
The staged UI control adapter adds `!ui2_headless` guards only to native
macOS/Windows branches, matching `launcher-check.v`; both original and staged
UI source trees and hashes are retained. Clang 23 uses
`-Wno-error=incompatible-pointer-types` for the existing pkgadmin socket pointer
conversion. This flag does not establish that compiler warnings were emitted.

The 2026-10-26 qualification passed all five modes: normal, production,
heap-tracked normal, heap-tracked production and ASan/UBSan. Each tracked mode
retained **0 V bytes / 0 records** across 1000 cycles / 9000 trees. The sanitizer
mode passed with `ASAN_OPTIONS=detect_leaks=0:abort_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1`; this establishes no whole-process leak result.

Implementation revision: `7f3ca9014e6aeec1679d4d4a1816ef04244a436d`, based on
`2588b47ecccc7dc3f7f3733e2753a0ceab2e8234`. The frozen inputs additionally include
the shared hosted adapter (separately integrated), SHA256
`502d852d447240a982c8bef719415025f6f3a9846020d015fc863886e0904aaa`.
The production navigation source SHA256 is
`ee4d66bddea22a513ca1b96f846dfa157f35ea8156b99efe8ca5446db049dbe4`.

The complete external directory is
`/Users/alex/.cache/vinix-package-repository-recovery-20261026-a`.
The archive includes that bundle and the source-bound driver executable:
`/Users/alex/.cache/vinix-package-repository-recovery-7f3ca9014e6a.tar.gz`, SHA256
`54d7426555035ef6dbf3af000017c2f1ac2aa32f35ba9049a4d337866a05e52a`.

| Receipt | SHA256 |
| --- | --- |
| `result.json` | `327c092424d7bab572c2d898ca8c64bf6af442e93191a1177fa7c8d25ddb1beb` |
| Project sources, 308 files | `1bd4f94d8eac9e72177135df641747efeddcadaad5cb13844c914ce570e2f85b` |
| Original UI sources | `deef2d596e58515ea55a3f252139198971a1c1ff3f163e502de51e98e09155b9` |
| Staged UI sources | `63f3ff23a45e6e3714fa888e1eafae5d53258e4ab11cf31682095bfc3ddd4e03` |
| Staged Software sources | `a9c5938ab17cd39bb517930f26b137cb11040aca09eb2e574a1b9848a7a5bb1f` |
| Other artifact inventory | `29f509478edf0e5d51538f0586c5708e3427c0822914c2b0bed67ab4be6eb003` |

The driver checked original and staged source inventories and V/Clang executable
hashes before and after the run. Evidence remains external to Git. Transitive
compiler inputs, vlib, third-party code, headers and linker are not frozen; the
run is not hermetic or reproducible. This is host headless recovery validation,
without guest graphics, screenshots, native HTTPS or full roadmap section 14
acceptance.
