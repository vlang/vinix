# Proposed current paired-kernel build

This is a one-attempt admission plan, not a build result or authorization.
The observer host qualification is recorded in `current-integration-observer-check.md`.
Root must review this complete ledger and explicitly assign the heavy lane
before either kernel compiler starts. No VM or image writer may share that
lane. All resource measurements and input pins must be rechecked at launch.

## Fixed inputs and argv

W is `/Users/alex/code/vinix/build/package-peer-frame-current-20261105-worktree`,
detached at `ffe3a39016fe89ff494cf59fa1126aca8a76dee5`.
R is `/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01`;
S is R-seal-01; P is R/observer-host-01. D is the held
`/Users/alex/code/vinix/build/package-peer-login-atomic-fresh-worktree`.
The fifth charged root is `.git/worktrees/package-peer-frame-current-20261105-worktree`
under the main repository. Source-only copies and all host refusals remain.

W must retain exactly the six reviewed tracked edits, the new frame helper,
and the four-file nested controller closure. Shared uncommitted main changes
are excluded. Kernel input hashes are:

| Path under kernel | SHA256 |
| --- | --- |
| `alloctrack/frame_page.v` | `be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d` |
| `alloctrack/track_d_alloc_track.v` | `1948b5f6d2bc30dae9ca50bc5726ee47937d56bcb05869891ceb9e644e4fa698` |
| `file/locks.v` | `74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6` |
| `memory/slab.v` | `5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4` |
| `socket/public/public.v` | `19b4b0a8fceaf0bbb78957d69025e7a6e8d805b1557d5f9c924067f82a3e372a` |
| `socket/socket.v` | `98588cce3eb94e72a89baf181178b92ea4de2a2b304d139c0f79af2571c7c3a8` |
| `socket/unix/unix.v` | `fec45e9c6f5ac12c615b3e8790ae0307ba809381e3a36cc36c220feb37951261` |

The controller is R/host-bootstrap-01/controller/guarded-build-check,
SHA256 `d9d2153f831990a5a2ed20398e09b254b6c24dae77864a4a95fcea1f92c04820`;
its nested source is `46be2985c371399c6f1b6081fc58340cce9a67d20baf3bca1fc2efac4e2ccc31`.
The observer is P/profile-bootstrap-03/fresh-frame-observer,
SHA256 `2370cecc2092c730573dcfcd2afaf2a32182333e9640d2207dd7bb2d3cd98958`;
its source is `1ba210bceeeea5fccb59cd384eece815506826d4c7c3116b18862812f36945ae`.
It retains the fixed CLI mode `--build-frame-01`, now selecting both candidate
architectures. Its literal controller argv is `[CONTROLLER, R + '/build-01']`.
Require that output and observer build-state names to be fresh.

The target compiler remains
`/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v`,
SHA256 `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
The corrected host toolchain is separate. Do not replace the target toolchain
or relax exact generated-C guards merely because current-source compilation
or output differs. Current target compiler compatibility is unproved.

The unchanged controller constructs these common make arguments:

```text
/usr/bin/make -C W/kernel -j2 ALLOC_TRACK=1 PROD=true
LINUXKPI=0 PCI_CONFIG_TEST=0 PCI_TOPOLOGY_TEST=0 ACPI_SYNC_TEST=0
STACK_GUARD_TEST=0 KERNEL_LINK_RANDOMIZE=0 VFLAGS=-nocache
V=/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v
CC=/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23
AR=/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-ar
LD_X86_64=/opt/homebrew/Cellar/lld/23.1.0/bin/ld.lld
LD_AARCH64=/opt/homebrew/Cellar/lld/23.1.0/bin/ld.lld
```

First add `ARCH=x86_64 LIMINE_MP=0`, then `ARCH=aarch64 LIMINE_MP=1`.
Preserve the literal `ld.lld` spelling. Both builds stay sequential. The
controller creates its five declared dependency links and private cc-runtime
copy, records its coherent cleared environment/private caches and complete
source/tool/dependency maps, and preserves each architecture before the next.
All dependency destinations and kernel transient outputs must still be absent
at launch; undeclared untracked kernel sources refuse admission.

## Measured baseline and explicit margins

Read-only sizing compared the held and current source snapshots: each has
900 kernel V files. Summed per-file apparent sizes were 8,147/8,150 KiB;
allocated sizes were 9,836/9,936 KiB. All 152 current-base kernel changes are V
files (2,073 insertions, 1,969 deletions); the kernel Makefile and tracked C/ASM
inputs did not change between those bases. Current V expansion sizes are unknown.
The allowances below do not assume the old blob size will remain unchanged.
Declared dependency referents and generator inputs must be pinned at admission;
their old bytes are not inferred from that tracked-source comparison alone.

Historical build-03 rounded observations:

| Group | Count | Allocated KiB | Apparent KiB |
| --- | --- | ---: | ---: |
| Generated C | 2 blobs and 1 sampler | 20,328 | 20,323 |
| V objects | 2 blob objects | 43,060 | 43,058 |
| Other native objects/dependency trees | 120 C, 31 ASM, 2 nanoprintf, 1 sampler objects | 6,744 | 6,077 |
| Kernel ELF | 2 | 32,544 | 70,414 |
| Complete runtime trees | 320 objects, 2 archives, copied sources/deps | 6,028 | 2,922 |
| Input/artifact maps | 3 input and 2 artifact maps | 12,220 | 12,218 |
| Other source, logs, symbols, symlinks, scratch and receipts | — | 2,076 | 2,703 |
| Complete retained build | — | 123,000 | 157,715 |

The x86/ARM blobs were 9,498/10,787 KiB apparent; their objects were
19,852/23,206 KiB; ELF files were 30,744/39,670 KiB. Complete obj directories
were 32,985/37,396 KiB apparent. The pair used 117.837/127.036 seconds of make
time; the native watch recorded 306 samples. These are historical observations,
not current qualification or a runtime promise. The existing 1,100-second
entry-through-PASS wall is retained without resetting preflight or final clocks.

Use the following allowance for each space measure independently:

| Projected category | MiB | Basis |
| --- | ---: | --- |
| D/W/Git administration, source receipts, private runtime | 32 | Fixed roots plus measured 1,144/589 KiB private runtime copy |
| All retained host work, refusals and remaining host qualification | 64 | Entire cumulative ceiling, not only latest successful attempt |
| Two generated blobs | 32 | 16 each against historical 9.3/10.5 MiB |
| Two blob objects | 64 | 32 each against historical 19.4/22.7 MiB |
| Two kernel ELF files | 96 | 48 each against historical 30.0/38.7 MiB apparent |
| Other native objects/dependency trees | 12 | Historical 6.6 MiB allocated |
| Both complete runtime trees | 8 | Historical 5.9 MiB allocated |
| Build maps, inventories, source/receipt metadata and build journal | 20 | Historical maps 11.9 MiB, plus journal/metadata |
| Sampler C, symlinks and small generation metadata | 4 | Explicit separate allowance |
| Preservation copy fallback | 80 | Largest projected obj mirror and materialized source trees |
| Compiler/sed scratch | 16 | One extra projected generated-C-sized scratch |
| Combined retained logs | 32 | Existing native combined-log ceiling |
| Future full inventory and audit journals/receipts | 24 | Separate later phases |
| Contingency | 16 | Explicit margin |
| Measured projection | 500 | 512,000 KiB |
| Reserved final tail | 1 | 1,024 KiB inside the cap |
| Inclusive projection | 501 | 513,024 KiB; 11 MiB below 512 MiB |

The live observer keeps its unchanged 511 MiB measured ceiling; the final
1 MiB remains reserved. These are sampled namespace limits, not a quota or
proof of every possible filesystem/compiler failure. Per-category values are
admission assumptions, not new guards added to the historical controller.

The pinned `preserve_outputs()` sequentially uses `os.mv` for obj, bin and
the architecture runtime. W and R share device 16777230. Normal rename creates
no second retained object set: live W and retained R objects belong to one
union above. Pinned os.mv can fall back on any rename failure to cp_all/remove;
cp_all resolves symlinks. The 80 MiB provision covers one largest projected
non-vsrc obj mirror (16 C + 32 blob-object + 6 native + 2 small MiB = 56), plus
two 12 MiB materialized source trees. Runtime/ELF fallback is smaller. No
rename-success assumption removes that fallback from the ledger.

Final host endpoints were 35,516/34,212 KiB including both space refusals and
the failed broad-match generator. All current D/W/R/S/Git roots measured
63,788/57,027 KiB. The ledger nevertheless charges the full 64 MiB host
allowance. Dependency referents outside the growing roots are read-only pinned
inputs; only their declared link nodes and the private runtime copy enter W.

## Execution and remaining gates

Before launch root must approve the ledger and assign the lane. Recheck actual
2 GiB free admission, allocated/apparent rounded totals and the final reserve,
source/closure hashes, complete input proof, dependency freshness and exact
qualified executable identities. Use the observer's closed build route and
its captured environment; do not run make as a separate unobserved substitute.

Require actual controller/native outer zero, both architecture markers, actual
generated C plus all 18 frame and 29 peer mutation refusals per architecture,
ELF/symbol checks, unchanged complete inputs and both inner cleanup receipts.
An outer owner does not prove separately owned make-group cleanup.

This admits one candidate attempt only. A retained failure, changed source or
larger measured artifact invalidates this ledger for retry; preserve evidence
and obtain a fresh inclusive projection. Never remove failed output, weaken a
checker or widen the cap to make a retry fit. If the conservative projection
cannot fit at actual admission, report the budget blocker instead of launching.

After a successful build, review actual outputs/resource receipts and freeze R.
Original full seal, separate check and root-independent check must write outside
R in fresh audited states. Native peer-login, exact allocation/performance and
desktop gates remain; historical old-base qualification does not qualify this
current snapshot or later main revisions. Production integration remains open.
