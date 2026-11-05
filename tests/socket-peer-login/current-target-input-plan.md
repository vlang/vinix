# Proposed prebuilt target compiler input phase

Admitted plan, 2026-11-05; the executed result is recorded in
`current-target-input-check.md`. Nothing in this document authorizes another
copy, compiler, kernel build or VM. The previous candidate failed as recorded in
`current-integration-build-refusal.md`; its artifacts remain intact. This
phase freezes inputs only. Relocated compiler execution, GC/library closure,
native generators, generated-C guards and runtime qualification remain open.

The maintained freezer/profile used for this phase is
`tests/socket-peer-login/prepare-current-target-input.v`, SHA256
`c28b539f946627896dc16a61e2f6dc95b7d170cda139dbefea48d361089284eb`.
It calls the existing `nativeguard.supervise` API without modifying its owner
algorithm. Its nine fixed actions have no caller-supplied argv or paths.

## Exact inputs and destinations

The selected prebuilt executable is
`/Users/alex/code/v-worktrees/vox-parallel-cc/v`, 15,389,808 bytes, SHA256
`482d0c3b5fe591e4b72c613e032c5bc212126c3a0708e18db87dc36e7d907d40`.
Its bounded read-only version command returned `V 0.5.2 2f91a8f` with status 0.
The matching source worktree is clean at
`2f91a8f4e9b360f3aa1d63aad1595f5a889985c1`. The same bytes were found at
`/Users/alex/code/v/v`; that shared lookup path is not a continuing input
authority. No as-run compiler-build provenance is asserted.

Git identities at the selected revision:

| Root | Git object |
| --- | --- |
| `vlib` | `baa85da1f320f1b63b060778283497554d018436` |
| `cmd/v` | `9e373465a356e75b638003d904b8fe6b85468060` |
| `vlib/v/driver` | `1f157d529aca3f1eda424276e78bdabff258a2d2` |
| `vlib/v/gen/c` | `08729d10434127b80b4cb4767a71cee84f95bc33` |
| `thirdparty` | `ec205d43fa352bc470081defdbcdc2bb820d23e3` |

Use all tracked files in `cmd/v`, `vlib`, `thirdparty` and `v.mod`, including
tests and assets. No test-directory filtering, mutable live-vlib link, old
compiler alteration or source adaptation is proposed. The Git archive has
16,745 regular files and 1,245 directories, including the `cmd` parent; no
symbolic links or Git submodules occur in these roots.

The section parent is
`/Users/alex/Library/Caches/vinix-codex/section14`. At review it was an ordinary
0755 directory, UID 501/GID 20, device 16777230, inode 369485036. The source
worktree and its executable were ordinary owned entries on that device; the
executable was 0755, inode 473752338, link count 1. Every launch must recheck
identities, ownership, canonical parents and absence of both destinations.

New input C is the section parent plus `/current-target-v-2f91-20261105-01`.
CA is C-seal-01. C/toolchain contains independently extracted sources and the
copied `v`; C/source.tar.gz retains the exact compressed source archive. CA
contains action argv/environments, actual ownership and resource receipts and
the unchanged auditor's complete inventory. Neither destination exists yet.

R is the existing `current-peer-frame-integration-20261105-01` under the same
section parent. All freezer source capture, bootstrap, generated host C,
private compiler caches and setup records go under R/target-freeze-host-01.
They remain charged to the existing kernel 512 MiB cumulative roots. The new
C/CA input phase has its own explicitly reviewed 256 MiB cap; it is not an
unrecorded addition to the old kernel attempt's budget. Once qualified and
frozen it may be declared as a read-only compiler input, as the old ff75 tree
was; the later kernel retry still needs a complete new 512 MiB projection.

## Archive, copy and proof

The raw tar stream is 128,901,120 bytes, SHA256
`d47a990bf32e24dc574c70c4bee29b0fa8cdd1b99d8fe38a41f8cda02c65cd18`.
Its total regular-file payload is 114,945,933 bytes. Deterministic gzip is
32,885,933 bytes, SHA256
`1c25e7abd519486a894a5e18226f67c4cf529ab5976447d57b889073e0514c70`.
Read-only repeated streams, including Git's direct compressed-archive route,
matched. The freezer must generate and verify those bytes again.

The fixed archive argv is:

```text
/Library/Developer/CommandLineTools/usr/bin/git
  -C /Users/alex/code/v-worktrees/vox-parallel-cc
  -c tar.tar.gz.command=/usr/bin/gzip\ -n\ -c
  archive --format=tar.gz --output=C/source.tar.gz
  2f91a8f4e9b360f3aa1d63aad1595f5a889985c1 cmd/v vlib thirdparty v.mod
```

The `-c` value is one structured argv element. Git streams directly to the
pinned gzip command: no raw tar file is materialized, retained or discarded.
Archive hash and length must match before `/usr/bin/tar -xzf C/source.tar.gz
-C C/toolchain` runs. Both commands use the existing native owner.

The selected executable's before/after identity includes device, inode,
owner/group, mode, link count, size, timestamps and SHA256. Its independent
copy must be 0755, owned by the current UID, link count 1, a different inode
on the shared device, and byte-identical. Verify exact Git file and directory
sets, regular-file modes, sizes and Git blob digests; extra empty directories
also refuse. Run original and private version commands and require the exact
same output. Drift in the selected source worktree or executable refuses.

The original full auditor remains SHA256
`fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6`.
Run its complete seal and separate complete check against C, with output in
CA. A conservative size admission calculation counts every actual C entry,
uses all original inventory fields with numeric values quoted to overestimate
their encoded length, and reserves 2,048 bytes for the manifest envelope.
It must fit 6 MiB before seal; the actual complete inventory must also fit
6 MiB afterwards. A larger complete inventory stays retained as a failed
resource admission; no inventory is trimmed and no original check is weakened.

## Inclusive space and timing

The full payload plus 4 KiB of rounding for each file and directory gives an
upper planning total of 188,616,228 bytes (179.88 MiB). Git's complete relative
path listing occupies 836,856 bytes. The 184 MiB source allowance adds 4.12 MiB
for directory entries, root metadata and remaining namespace overhead. A
planning allowance of 128 bytes per namespace entry plus every full relative
pathname uses less than 3 MiB of that margin; 4 KiB per directory is already
included above. This is a conservative admission forecast, not a filesystem
quota guarantee. The matching worktree's selected roots currently measure
167,020 KiB allocated / 122,905 KiB apparent, including an ignored TCC tree
that the archive does not copy; those observations are supporting size
evidence, not an input-closure claim.

| Input C + CA category | MiB |
| --- | ---: |
| Complete extracted Git source, directory/root metadata | 184 |
| Retained compressed source archive | 32 |
| Independent prebuilt executable | 15 |
| Complete inventory, native DF/result journals and metadata | 16 |
| Aggregate child output logs | 1 |
| Reserved final receipts/refusal tail inside cap | 8 |
| Inclusive phase cap | 256 |

C is limited to 231 MiB and CA to 17 MiB in both space measures; together
their working ceiling is 248 MiB, retaining the 8 MiB tail. Native child
observations measure allocated storage; apparent size is checked at action
endpoints. No continuous apparent-size or hermetic SDK claim is made.

The total freeze deadline is 600 seconds from entry through PASS, including
source/Git hashes, inventories, seal/check, final receipts and final endpoint
probes. Each child wall is clamped to the time remaining. No child can reset
the total clock. Nine actions add at most eighteen initial/final observations
to the periodic samples; the profile refuses over 620 complete samples.
At three rounded 4 KiB DF files per sample this is at most 7.27 MiB. Complete
native-result JSON is limited to 1.5 MiB, the complete inventory to 6 MiB,
and other metadata/directories have 1 MiB of provision: total below 16 MiB.
The aggregate child-log limit is separately 1 MiB at endpoints. Every owned
group must retire with status 0, reap/ECHILD and absent group. Before PASS,
the final seal/check is followed by actual complete input endpoints, both
kernel-space endpoints, final receipt accounting and deadline/5-second
last-observation checks. Refusal artifacts remain intact.

Current D/W/R/S/Git roots measure 79,932/71,033 KiB. Proposed setup growth is
at most 16 MiB, independently charged to those kernel roots:

| Setup category under R, including failed bootstrap state | MiB |
| --- | ---: |
| Maintained source capture and module closure, parent metadata | 1 |
| Bootstrap executable, retained generated C and private scratch/cache | 6 |
| Initial compiler log, including failed attempts | 4 |
| Complete setup/source before/after maps and reference receipts | 2 |
| Plans, actual statuses, tool/loader pins and refusal records | 1 |
| Setup final reserve | 2 |
| Inclusive additional setup bound | 16 |

Both initial allocated and apparent totals plus the full 16 MiB must fit
511 MiB before C/CA creation. C/CA and setup are all included in the actual
shared 2 GiB admission / 1 GiB live-floor checks. Each later compiler or
materialization action requires fresh admission; historical free-space
observations cannot admit it.

Before setup, allocated/apparent projections are 96,316/87,417 KiB after
charging the full additional 16 MiB. They include the failed build and all
historical states in the existing roots. SETUP does not exist yet. The fresh
read-only free-space observation was 16,297,100 KiB; admission must be repeated
at the actual compiler launch. This forecast permits only one initial strict
freezer bootstrap; failures remain charged and require a new projection.

## Proposed bootstrap and remaining host gates

After source review and a lane release cue, capture the freezer plus the
existing qualified nativeguard, recoveryguard and seven-file sourcecommand
closure in R/target-freeze-host-01/source. Their exact pins are in the draft.
Keep the old completed host profiles unchanged. Resolve and retain the loaded
tool dependencies, CLT Git/gzip/tar identities and SDK metadata/resource-header
pins; the full SDK is not inventoried by this phase.

Reuse the unchanged complete host-toolchain inventory rather than retaining a
second 14 MiB set of maps. The authoritative root is
`/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain`; its original
inventory is R/observer-host-01/maps-02/host-v/inventory.json, SHA256
`ff729f3d39ad09b0401c2f1e08e69784db5c4781117c1f1480a59ee4ffdd39e9`.
The original full auditor must check that complete root before and after the
bootstrap and retain actual statuses/logs under SETUP. Independently capture
and compare every new SETUP source file and selected clang/resource-header,
SDK metadata and loaded-tool inputs against the qualified complete baseline
R/host-bootstrap-01/inputs-before.json. Only those named roots/entries are
reused: the historical full W snapshot is now stale after admitted kernel
output/dependency setup and must not be claimed equal. Retain the selected
entry list, comparison result, baseline checksum and actual current tool
closure receipt. New source/helper/temp and all such proof growth stay inside
the 16 MiB SETUP allowance and the existing kernel cap.

Initial strict bootstrap uses the pinned corrected-host V executable
`/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v`, SHA256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`:

```text
/opt/homebrew/bin/timeout --signal=TERM --kill-after=10s 300s
  HOST_V -prod -enable-globals -nocache -keepc
  -cc /opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23
  -cflags -Werror=incompatible-pointer-types
  -path SETUP/source/tools|SETUP/source/tests/software-hosted-x11|SETUP/source/tests/software-hosted-x11/diagnostics|@vlib
  -o SETUP/bootstrap-01/prepare-current-target-input
  SETUP/source/tests/socket-peer-login/prepare-current-target-input.v
```

Use the existing coherent cleared caller environment, explicit canonical
MacOSX26.5 SDK, and private modules/cache/tmp paths. GNU timeout's initial
bootstrap has actual status/log and endpoint accounting; it does not claim
typed native cleanup. Do not launch it during the active compiler pause.
The subsequent fixed freeze route uses nativeguard's actual typed receipts.
Unknown CLI modes must refuse before mutation; source/API review, strict
bootstrap and applicable native-owner/refusal controls must pass first.

Freezing does not prove that the copied compiler uses only private source
inputs. The driver selects the copied executable's sibling vlib with coherent
caller markers and VEXE, but the binary also contains baked asset paths.
Positive relocation/embedded-data evidence and missing-private-library refusal
controls remain mandatory before compiler-consumer qualification. Default GC
may require an untracked Boehm archive; this proposed closure intentionally
qualifies only later explicit `-gc none` workflows until that gate passes.

Next, qualify a focused native-generators host build with `-gc none`, explicit
Apple clang/SDK and fixed module roots, then the production x86 sampler and
independent success/OOM/zeroing/clock/ABI fixtures. A separate compiler-bound
checker profile must retain all 18 frame and 29 peer mutations per architecture,
with independently reviewed actual candidate C. No full kernel or VM is
admitted by those host results.

For the future 512 MiB kernel projection, an isolated reviewed preservation
helper can replace generic `os.mv` fallback with same-device rename-only,
retaining all live/preserved outputs on any error. Meaningful real rename
failure controls and the qualified owner must pass before removing the old
80 MiB copy-fallback allowance. Historical controllers remain unchanged. The
failed build, all new sampler/checker work and future audit state must still
be included in the complete retry ledger.
