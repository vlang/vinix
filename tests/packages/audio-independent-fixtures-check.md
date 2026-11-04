# Independent audio fixtures host checkpoint

Generic preparation and evidence fixtures now copy regular files independently
instead of hardlinking source inputs. They preserve modes, verify bytes,
require destination nlink 1 and a distinct inode, and check source metadata and
hashes. Evidence cloning validates an existing equal independent target;
preparation retains its fresh-target requirement. Explicit hardlink-refusal
controls remain unchanged.

Two added regressions use a shared source with mode 0550 and nlink 2. They change
only the copied target to mode 0600, write through that owned inode, and verify
source bytes, nlink and captured timestamps remain unchanged. Duplicate,
mismatched, hardlinked and symlinked target cases retain their required behavior.

Validation used isolated source baseline
`069036c7d8468720dc83f8703d4e797757733a2d` plus five pinned V changes:
three fresh-kernel binding files and the two fixture checkers. Source hashes,
literal commands and the exact environment are retained in the approved plan.
Six production host tools built successfully with pinned V, LLVM 23 and
`-prod -nocache -keepc -backend c`. The strict bootstrap additionally used
`-Werror=incompatible-pointer-types`. The maintained host returned actual exit 0.

All **151 controls** passed: 89 preparation, 35 strict synthetic evidence and
27 matched-kernel controls. The previous 149 names and order are preserved.
Both required original complete audits passed. All 14 owned command cleanup
records show reaped children, empty groups, ECHILD, exit 0 and no held pipe.

A fresh complete source inventory was captured before execution. Its SHA-256 is
`75476767071701f4bd89036a66e49ae244d46c25f4ca82070971a7f7f4954cc1`.
Unchanged original full checks returned actual 0 after bootstrap and after all
151 controls. Compiler and selected-kernel complete postchecks also returned 0.
The complete maintained input maps compared equal:
`cace7b1dc16eabb25bc033a76f079aa94ddbd1fb5698bdef8ecbad6b975cea33`.

The complete retained run is outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-independent-fixtures-host-20261104-01`.
`qualification-01/host-build.json` SHA-256:
`8356c6ff33736f6c2671f27b3a89cb3f22c3e6d164389b8819e7789fc64fa7cd`.
`qualification-01/qualification.json` SHA-256:
`0fd0bbaf05de75f3baa6a2ee5fb2692a6ca48ce388d545337c1b064f6fdd0e46`.
`qualification-01-final-status.json` SHA-256:
`e15d54d653d0a967b2e390f721c9ef8bde5d7e2494775e10c8c12c39ab92d6d6`.

Final broader six-root endpoint observations were 1,058,216 KiB allocated and
1,230,694 KiB apparent, below the 2 GiB cap, with 34,197,624 KiB actual free.
The unchanged live guard charges S/complete; external observations include all
S/history. Direct checks supply endpoint observations only. No actual sample
start-gap or unconditional continuous free-space guarantee is claimed.

The [earlier alias diagnosis](audio-binding-alias-diagnose.md) remains a record
of four historical fixture mutations. Its original snapshots and refusals are
preserved without repair or requalification; this checkpoint supersedes its
pending-151-validation note. Original source/legacy aliases remain fixed.
Source N and this new run are frozen. The subsequent whole-history seal,
separate check and root-owned independent check all returned actual exit 0 with
exact original markers. The original checker and source remained unchanged.

The complete raw run remains at the path above. Its complete inventory and
audit output are retained in the adjacent `a4-independent-fixtures-host-20261104-01-seal-01`
directory. `complete/inventory.json` is 8,464,458 bytes with SHA-256
`7ff70ca14f128ac8dc204d4a95ca9b2a687caf7871125ba296146114a40f9caa`.
That manifest stayed identical through both checks. The first two actual
results are retained in `first-two-audits-status.json`, SHA-256
`b9b13184ec389ffd50bdcd4ceb615fca83e909dec8979895315eb01ea4df7d3a`.
The root-owned third result is `root-independent-status-03.json`, SHA-256
`34d8ad7ad00592fb4bd5ae8e8a1e69bcfa35797dd434b7787501572c8598b6b3`.

All ten audit anchors and 27 retained input pins verified unchanged before and
after the root check. Its log contained exactly the 37-byte original PASS marker.
Final seven-root observations were 1,066,636 KiB allocated/1,239,013 KiB apparent
under the 2 GiB cap, with 35,227,504 KiB actual free. The unchanged original leaf
used 600/300-second timeouts and five-second kill grace; these audits provide
endpoint observations, without continuous resource, RSS or group-cleanup claims.
Retain the complete raw run together with its inventory; this new audit does
not requalify any historical refusal. No target compilation, guest execution,
native audio backend/device or hermetic toolchain acceptance is claimed.
