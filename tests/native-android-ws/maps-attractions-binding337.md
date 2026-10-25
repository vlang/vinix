# Maps Attractions scene binding and transition contract

Source baseline: `edf5cb5cc27ca67e580110e450ce2a0a3a8103ba`.
This is a read-only investigation of the actual Maps APK used by
[Maps335](maps335.md), SHA256
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.
It does not qualify a new Maps run or prove the cause of the loading sheet.

`avho.P` creates the search-list scene with `cvsd.I`, obtains its RecyclerView
from `bs`, and intentionally returns null: the scene manager owns attachment.
Its null fragment view is not evidence of a failed framework attachment.
The visible Maps335 spinner is inside a separate `nvv` sibling after the list
content (`serial.log:23945–24030`). GmmRecyclerView's layout/measure overrides
only wrap the RecyclerView superclass with a metric scope. No further
RecyclerView completion gate was established.

The actual app uses `nvu` states Hidden, Shown and Behind. `nwa.f(View)` installs
the scene content, then calls `nvv.d(Shown, koj(cid16))` (`nwa.smali:941`). The
normal transition has these finite ViewPropertyAnimator batches:

| Target | Implementation | Animator count | Properties |
| --- | --- | --- | --- |
| Hidden | `nwh` → `bux(cid7)` | 2 | scene translationY/Z, overlay alpha |
| Shown | `nwi(cid0)` → `swy(cid1)` | 3 | scene translationY/Z/scaleX/Y, overlay/content alpha |
| Behind | `nwi(cid1)` → `bux(cid6)` | 3 | scene translationY/Z/scaleX/Y, overlay/content alpha |

Every batch sets a duration and interpolator and has no repeat/infinite setting.
`nwd` installs itself through Animator.addListener or VPA.setListener, counts
one end event per animator, then invokes `nvt(cid0)`. That callback applies the
target with `nvv.f`, then invokes the caller. `koj(cid16)` clears `nwa`'s pending
scene references. A missing end event would block this commit, but no retained
runtime sample establishes that occurrence. The alternate `nwj` transitions
are synchronous; `nvv.n` selects them only for normalized configuration value6.

There is a definite compatibility gap: all three normal branches invoke
`ViewPropertyAnimator.translationZ(F)`, at `bux.smali:2064`, `bux.smali:2227`,
and `swy.smali:411`. The sealed Framework336 class extends Object and lacks that
entry. This would fail while constructing the animation batch, before the
`nwd` barrier starts. Neither `nwa.f` nor `nvv.d` has a local catch. Maps335 has
no retained translationZ linkage error, and the selected runtime branch and
outer exception handling remain unobserved. The compatibility fix therefore
needs an isolated ART regression and a subsequent actual Maps replay.

The [selector](maps-attractions-select.v) pins the original qualified315 DEX
manifest and each of its ten DEX entries, retains its origin receipts, copies
Java and every JAR input, executes baksmali with the retained JARs, and checks
inputs again afterward. It authenticates its source/binary to the recorded
[build](maps-attractions-build.v), which retains the compiler/cc, complete V
source closure before/after, generated C and build receipt. Java's executable
is retained; its host JDK runtime libraries are not a self-contained runtime.

External evidence, all independently read back with the existing complete
bundle checker290 (exact file sets and all hashes):

| Bundle under `/Users/alex/.local/state/vinix/android/` | Files | Manifest SHA256 |
| --- | --- | --- |
| `nine-patch-tint-sourceproof315-qualified-2026-10-25` | 44 | `3fc905f97a238bd3916840b8ee4ec3ac3e172117d59ed29a1049ffd16169740b` |
| `maps337-attractions-selector-build-2026-10-25` | 293 | `ecd8811d759316491eb9e8562ad9a18094a30e9da21222dd90cc53adb2889eab` |
| `maps337-attractions-actual-selected-2026-10-25` | 61 | `030ad83ca95443fdaa192ed71af4b231755d80940b556a9f46852c960cf7c724` |

The actual-selected bundle contains exactly28 requested classes; its
`selected.json` pins each disassembly. Sibling receipts are
`maps337-attractions-dex-origin-readback-2026-10-25.json`,
`maps337-attractions-selector-build-readback-2026-10-25.json`, and
`maps337-attractions-actual-selected-readback-2026-10-25.json`.
Earlier exploratory selections remain separately sealed and unchanged.
Useful future samples are `nvv.c/g`, `nwd.d`, its callback/animator list sizes,
and each pending/running VPA with its listener. No guest input or QMP was used.
