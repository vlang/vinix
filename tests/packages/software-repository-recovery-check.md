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

## Refresh a selected repository

The full Repositories pane exposes **Refresh selected** for an enrolled row
whose displayed ID, URL and key match the current editor fields. **Go offline**
and **Use policy** control source access from the same pane. Refresh uses the
usual administrator prompt and shows completion once the child has exited.
Failure details remain available in the repository pane.

The host fixture checks literal arguments, approval and cancellation, edited
trust fields, and a failed child that emits a completion frame before it exits.
It also checks that package-file verification and signed-index verification
keep distinct progress labels.

Run the native fixture with `native-catalog-check --software-targeted-refresh`
using the same inputs as the bundled HTTPS Software scenario. It adds an
enrolled local field repository with two signed indexes. After the initial
installation, the guest switches the field repository to sequence 2 and
temporarily takes the bundled HTTPS source out of service. The Software
controller activates **Go offline** and **Refresh selected** from the
rendered element tree as UID 1000. The root observer checks the exact retained
HTTPS snapshot, new field index and signature, updated trust history, unchanged
installed generation and one additional successful administrator approval.

At `b7f43becb6342b9b73d5b854e535e07c9f393f62`, all five host variants passed
with V `2655544` and the retained headless UI source. Both tracked variants
retained zero V bytes and records across the 9,000 compact recovery renders.
ASan and UBSan passed with process leak detection disabled.

Both production compositors linked statically. The native controller fixture
passed on AArch64 in 56.579 seconds and x86-64 in 69.402 seconds with QEMU TCG
and guest-initiated shutdowns. It used the actual Software element tree and
administrator service on the staged image. Framebuffer input and presentation
were qualified separately through production login on both architectures.
See [selected refresh through production login](software-first-run-native-check.md#selected-repository-refresh-through-production-login).

The evidence archive is
`~/.local/state/vinix/r14-software-refresh-5Vddg5/qualification.tar.gz`.
Its SHA-256 is `fcbab47ce4ecbe0c41d373a5dd92e4aba4d33695a44b72b9047a0ec3d338fd25`.
Independent extraction matched all 10,104 inventory entries.

## Refresh after publisher enrollment

Software takes the repository ID from the completed enrollment command and
asks for separate approval to refresh that source. It passes the window's
offline selection to the follow-up. Cancellation preserves the trust change.
A refresh failure preserves the service diagnostic and points to **Refresh**
in the catalog when other repositories need current indexes.

The host fixture drives both approval prompts through the element tree. It
checks exact offline command arguments, successful refresh, cancellation and
failure after enrollment. All five host variants passed with V `2655544`,
including ASan/UBSan with leak detection disabled. Both tracked variants
retained zero V bytes and records across the 9,000 compact recovery renders.

Add `--software-enrollment-refresh` to the native catalog check with the
bundled HTTPS Software inputs. After the normal image maintenance cases, the
guest withdraws the existing publisher's image bundle and enrolls a new local
publisher through Software as UID 1000. The guest checks two successful
administrator operations, the new publisher's exact sequence-2 index and
history floor, and the original publisher's cached snapshot and floor. The
installed generation and package state stay byte-identical.

At revision `f171d6a9b96f8e8b8e1d883052ce12a5bab29441`, the headless native
Software runs passed under QEMU TCG on AArch64 in 59.987 seconds and x86_64
in 71.433 seconds. Both had guest-initiated shutdowns. The full production
compositor also linked statically for both targets. The native test exercised
Software's element tree and administrator service.

The [retained archive](/Users/alex/.local/state/vinix/r14-software-enrollment-refresh-AtUPPY/qualification.tar.gz)
contains the source snapshot, host outputs, compositor builds, staged images
and native logs. All 65 receipt entries matched per target. The independent
archive checker verified all 9,687 sealed files and symlinks. Archive SHA-256
`2d5ee602314424c9199b7450ddd88e772740039b4b8ec6b240f5f7ba61f82b88`.

## Refresh identity binding

At revision `cc7c6262bee890260b381fe06c77c7251e468c80`, both selected refresh
paths pass an identity fingerprint for the repository ID, URL and key. Under
the writer lock, the package service checks the current configured identity
before fetching metadata. Host checks cover changed URLs, rotated keys, removed
repositories and a successful retry with the matching identity. All five host
UI modes passed with V `2655544`. Both tracked rendering modes retained zero
V bytes and records across 9,000 trees. The focused refresh check retained zero
tracked allocations across 72 scopes and 4,608 requests. ASan and UBSan passed
with process leak detection disabled.

On 2026-11-24, the manual and post-enrollment approval paths passed on AArch64
and x86_64 under QEMU TCG. Each exercised Software's actual element tree and
administrator service on the staged image and ended with guest-initiated
shutdown. Both enrollment runs used the guest CLI to refuse stale URL and key
fingerprints before fetch or publication and verified unchanged catalog, trust
history and installed generation. Both production compositors linked
statically. Framebuffer interaction and installed-root boot were outside these
four runs.

The [retained archive](/Users/alex/.local/state/vinix/r14-refresh-identity-8RoREo/qualification.tar.gz)
contains the pinned source, host checks, compositor builds and native receipts.
All 65 receipt entries matched per enrollment run and all 66 per manual run.
The independent archive checker verified all 10,181 sealed files and symlinks.
Archive SHA-256 is
`b0020f8d173d4cf11d2802fd58369f87a0dd79b1568391ef927dc30ea66b559e`.

## Browse and refresh in compact windows

At 180×220, the compact catalog opens **Repositories** through its **Sources**
entry. **Browse repositories** pages through configured identities and opens
the ordinary administrator prompt for the displayed source's **Refresh**
action. At 320 pixels wide the compact repository list also offers **Go offline**.
The refresh worker receives the displayed identity fingerprint. Browsing and
refreshing preserve the editor's literal draft.

At `6c5f35869e79ab63112982d65faf3a3cf830ab7e`, all five host modes passed.
The tests reconstruct a 4,096-byte UTF-8 URL and its publisher key from the
rendered pages, check bounded controls, and exercise password approval and
cancellation at 320×240. Both tracked variants retained zero V bytes and
records over 64 open, navigate, render and close cycles and over the existing
9,000 recovery renders. ASan/UBSan passed with process leak detection disabled.

Both production compositors linked statically. On 2026-11-24, the selected
refresh check drove Software from its compact catalog through actual
administrator approval at 320×240 on AArch64 and x86_64 under QEMU TCG. The
selected local source advanced while the saved HTTPS index and installed
generation stayed byte-identical. Both guests initiated shutdown. The
retained receipts match all 66 entries on each target. These runs covered
controller interaction on the staged image.

The broader package-navigation allocation fixture retained 5,400,000 bytes
over 1,000 cycles. It reported the same total at the earlier
`cc7c6262b` baseline and at `b1dc7b107` before the compact catalog entry.
The launch-navigation allocation fixture retained zero tracked bytes.

The [retained archive](/Users/alex/.local/state/vinix/r14-compact-repositories-mcirSh/entry/qualification.tar.gz)
contains the final source snapshot, host checks, compositor builds and native
receipts. The independent checker verified all 9,789 sealed files and
symlinks. Archive SHA-256 is
`2d65394ecb21e592a85e9d1e576a9878f90a99271d34ab74ed76628c5841dbf9`.
