# Exact prebuilt target compiler inputs

2026-11-05: the maintained fixed freezer completed with actual exit 0 and
`CURRENT TARGET PREBUILT INPUT FREEZE PASS`. It preserves an independent
prebuilt executable and complete selected Git source/library archive. This
does not qualify compiler relocation, embedded assets, default GC, native
generators, kernel generated C, guests or production integration.

The source baseline before this tooling commit was
`a1225edd4d1bbadf59e12f5b561128a0d33bb62e`. The separate source copier and its
qualification report are committed there. Maintained freezer source SHA256 is
`c28b539f946627896dc16a61e2f6dc95b7d170cda139dbefea48d361089284eb`;
its strict host executable is
`60623a7726dafd49d4a195d06c56825464de74d5394bc78824404157e0c52397`.
The complete admission ledger remains in `current-target-input-plan.md`.

R is
`/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01`.
SETUP is R/target-freeze-host-01. Compiler input C is
`/Users/alex/Library/Caches/vinix-codex/section14/current-target-v-2f91-20261105-01`;
its audit/observation sibling CA is C-seal-01. No generated C, executable,
archive, raw inventory or result file is added to Git.

The selected source worktree is
`/Users/alex/code/v-worktrees/vox-parallel-cc`, clean in the selected tracked
roots at `2f91a8f4e9b360f3aa1d63aad1595f5a889985c1`. Its existing compiler and
C/toolchain/v both hash to
`482d0c3b5fe591e4b72c613e032c5bc212126c3a0708e18db87dc36e7d907d40`.
Both version commands returned `V 0.5.2 2f91a8f`. The new executable is ordinary
0755, UID 501/GID 20, device 16777230, link count 1; its inode 474973189 differs
from source inode 473752338. No claim is made that the executable was built
from the archived sources.

Git streams directly to deterministic gzip; no raw tar is materialized.
The retained 32,885,933-byte archive has SHA256
`1c25e7abd519486a894a5e18226f67c4cf529ab5976447d57b889073e0514c70`.
All 16,745 regular files and 1,245 directories in `cmd/v`, `vlib`, `thirdparty`
and `v.mod` were checked against the exact Git file/directory sets, modes,
sizes and blob digests. The prebuilt copy is additional to that source set.
No test assets were filtered and no live-vlib symlink was substituted.

Strict copier, freezer and selected-input-checker host builds passed with the
pinned corrected host toolchain. The original full host-overlay checks passed
before and after; direct tools, canonical SDK 26.5 settings and all 326 regular
clang resource-header hashes matched across each compilation. The selected
input checker then matched 370 external entries, 90 loader filesystem records
and 320 baseline-bound loader metadata records to the qualified H map. That
post-bootstrap comparison is combined with the retained before/after captures;
it is not presented as a contemporaneous precompile witness or fresh loader
discovery. The full SDK is not claimed hermetic.

An earlier checker incorrectly required the moving SDK alias to resolve to
26.5; that failed source/binary/log is retained under SETUP/comparer-bootstrap-01
and tool-inputs-01. The alias already pointed to 27.2. The final checker
compares canonical 26.5 directly with its exact H entries and records the alias
only as information. Its source SHA256 is
`957b602391c518a14fa1bb1b8d533138a038fc27548eeda8285827112a003918`;
its executable SHA256 is
`48061bb02c2979b34b282f9e1254e66fd78eb977a4074dfe0f88d0f2b11097f8`.
Its positive comparison passed; a repeat refused and left the result unchanged.
Unknown freezer modes and extra operands returned 1 before creating C or CA.

All nine directly owned action groups returned 0 naturally, with observed
groups, reaped leaders, empty original groups and waitpid -1/ECHILD (10):

| Action | PID |
| --- | ---: |
| Archive | 99460 |
| Independent executable copy | 99921 |
| Extraction | 185 |
| Complete Git source check | 468 |
| Source executable version | 835 |
| Private executable version | 974 |
| Complete inventory size admission | 1152 |
| Original full seal | 1310 |
| Separate original full check | 4899 |

No action required a kill. These receipts cover each directly owned leader and
its original PGID, and native DF observations. Separate bounded read-only Git
probes use the unchanged sourcecommand ownership primitive; the nine receipts
do not independently attest separate probe groups.

The complete original inventory contains 17,995 entries and 5,032,256 bytes,
below the conservative 5,321,852-byte pre-admission forecast and unchanged
6 MiB resource admission. The full seal and separate full check passed without
changing the original auditor. Inventory SHA256 is
`e9fc44d9c400e810aeed3345467b7b89d097077370050f322fb8b467b9a0e5cf`.
Root's independent original check also returned 0 with the exact CHECK PASS
marker and unchanged inventory checksum. Its separate direct GNU-timeout
receipt is SETUP/independent-original-check-01/check.log, SHA256
`a0f49b6703f4c067b1166aebd9cfe67bdc22b9c52ab17c7dbbacea91a20e82b7`.
That independent check has endpoint/status evidence, without a typed cleanup
or continuous observation claim.
The native receipts retain 109 complete samples and 47,354 bytes of result
JSON. The 600-second entry-through-PASS, measured observation-gap and final
five-second checks all passed; apparent storage was checked at endpoints.

Quiescent C used 209,012 KiB allocated / 165,074 KiB apparent; CA used
6,848/5,239 KiB. Their combined 215,860/170,313 KiB stays below the 248 MiB
working ceiling and retains the 8 MiB tail inside the separate 256 MiB input
cap. SETUP remained below its 16 MiB allowance in the existing kernel 512 MiB
cap, including both comparer builds, the failed run and all generated host C.
Final SETUP endpoints were 9,152/8,875 KiB; all earlier failed states, including
the failed current-kernel build, remain intact.

SETUP/input-freeze-launch-01/actual-status.json binds all nine native result
hashes and the copied executable/archive/proof identities; its SHA256 is
`387b632b88fd3fb3b179b11631986bc1f3dc2558b135e96fc804daaf41488cab`.
SETUP/tool-inputs-02/after-freezer/comparison.json has SHA256
`4af70941b2a71d6f8d3059449a9e8786c26ba1518f2a86d143bcfee52475b900`.
Complete source-copy identities, original host-overlay checks, compiler argv,
private caches, generated host C, all logs and failed attempts remain in SETUP;
the complete source archive and all inventoried bytes remain in C.

The next consumer gates must establish private-root/embedded-asset behavior
and the required GC/library closure before native-generator qualification.
Actual candidate C on both architectures must retain every semantic assertion
and all 18 frame plus 29 peer mutation refusals. The old compiler, historical
checkers, current kernel `uint` changes and seven-path isolated patch remain
unchanged; no new kernel build or VM was run in this input phase.
