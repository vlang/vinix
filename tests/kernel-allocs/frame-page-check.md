# Allocation tracker frame-page checks

Host checks and both-architecture `ALLOC_TRACK=1` build checks pass against
isolated baseline `9acefa77bee69247c837e97987a2377536aa41cc`, with the recorded
source patch and added helper. This report does not qualify a guest run.
This test-tooling change does not include the four production kernel source
changes. Their tested source patch and helper remain in the external bundle,
with hashes below; the production changes remain held pending guest allocation
and desktop measurements.

The old walker accepted an aligned high address without proving it mapped.
The reported x86 panic attempted `fp[1]` with `fp=0xffffffffffffff00`.
The new shared walker accepts only aligned, complete 16-byte frames inside
the adapter's own live frame's 4KiB page, above the architecture minimum,
and follows only strictly increasing frame pointers. Its initial frame is
trusted assembly-owned stack storage, not an arbitrary supplied pointer.
Both kernel architectures map at 4KiB granularity (`memory/virtual.v`,
`vmap_arm64.v`, `vmap_amd64.v`); no mapping lookup, allocation, lock or stack
metadata publication is needed. Traces intentionally stop at page boundaries,
which can reduce call-site attribution. Assembly entries and panic walkers
are unchanged. Target call-site usefulness still needs guest validation.

Final `host-03` passed normal, `-prod`, and ASan/UBSan profiles with
`-gc none -manualfree`. Each executed the actual shared module: 15 explicit
frame cases (including a real `PROT_NONE` guard, the panic pointer, cycle,
alignment, straddling frame, mapped neighbour, and ten-frame cap) plus 10,000
calls with a checked checksum. Live malloc blocks/bytes stayed
202/12592 in normal and production, and 216/13061 under sanitizers. All
three retained generated walker bodies are identical: fixed arrays and
`memmove`/`memcpy`, with no allocation call. No test uses assertion side effects.
Observed optimized host03 ARM assembly also proves the measured loop was
not hoisted: `w23=0x2710`, helper call at `0x100002fbc`, decrement at
`0x100002fc8`, and back-edge `0x100002fcc -> 0x100002fb4`. No barrier or
production optimization change was needed for the tested compiler.

Complete raw state, including two earlier diagnostic failures, retained C,
sources, argv, subprocess status/cleanup, df/du samples, source/tool/library
before/after hashes, and literal logs:
`/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-page-20261026`.
Its complete regular-file inventory `bundle.sha256` has SHA256
`d148564a8f4a7a3e2c699d0ff884a8679455f8be2234a7ce86a3229b37ea8a64`.
The first attempt compiled but refused a missing expected C location; the
second bootstrap refused an Option-propagation typo. Final tooling retains
C from a private compiler temporary directory. Entire added state was
16.3MiB including the sparse worktree and assembly supplement, below 40MiB.
The separate read-only assembly supplement is
`/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-page-20261026-assembly-01`;
its complete `bundle.sha256` SHA256 is
`9e46d532bb86796c2b899ca15541fa9e5bcff5bc10ccbffa4da4613e78802a50`.
It retains `LLVM23/bin/llvm-objdump -d host-03/prod` output and byte-identical
before/after objdump/ELF SHA256 observations. The exact canonical tool is
`/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-objdump`.

Tested helper SHA256:
`be2b4cee4283cc4c5275cd5a1cb668a12ab2e08300c18a15b4731ca185dad48d`;
tested callsite SHA256:
`23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e`.
The complete before/after selected-input maps are identical, SHA256
`a77aa488128bf08e7b6691c410b1a3f8e086b56d36815602f03ebe5a696e42b3`.

Reproduce on macOS by compiling `frame-page-host-check.v` with the pinned
V `build/package-https-runtime-work/toolchain/v` and canonical LLVM23 clang,
then invoke `frame-page-host-check ROOT NEW-OUT`. Use a dedicated parent for
NEW-OUT; the runner counts that whole parent plus the sparse worktree against
40MiB, requires completed `df -k` >=2GiB at admission and >=1GiB before each
subprocess. `frame-page-host-check seal STATE` inventories regular evidence
files once. Exact compiler/caller environment and argv are retained. This is
an observed host build: V libraries are hashed before/after; clang and host
SDK execute in place. It is not a hermetic or portable toolchain bundle.
Process-group cleanup assumes trusted host processes, without a hostile
concurrent PID/PGID identity guarantee.

The maintained `frame-page-build-check.v` subsequently built x86_64 and
AArch64 kernels sequentially in `build-03`, with `ALLOC_TRACK=1`, `PROD=true`,
`KERNEL_LINK_RANDOMIZE=0`, `-j2`, and `LIMINE_MP=0`/`1` respectively. LinuxKPI,
PCI/ACPI test modes and stack-guard test mode were explicitly disabled.
Literal make/compiler/linker argv, build logs, exit status, ELF headers,
symbols, generated C, objects and complete selected-input/output maps are at
`/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026`.
Both make processes exited zero; the runner reaped each leader and verified
its process group absent. Both ELFs have the expected machine and enabled
allocation-tracker symbol. No image was assembled and no VM was started.

This build exposed three implicit mutable-parameter pointer casts rejected
by the captured ff75 V compiler. The separate portability correction makes
the borrowed addresses explicit in `kernel/file/locks.v` and
`kernel/memory/slab.v`. The actual generated `set_record_lock` owner is
`(u64)(handle)`; both slab links use `(u64)(hdr)`. These match the prior
successful compiler's pointer operations, without a struct dereference,
copy, boxing, allocation or lifetime change. Independent ownership review
covered both source paths and the actual generated C. Host walker source
and callsite hashes above are unchanged.

Each architecture passed the generated-C checker for the actual complete
guard/read/break sequence and tracker callsite, direct borrowed Handle
identity, and exact slab insertion body. Each also rejected 18 mutated C
controls: weakened bounds/cap/monotonic comparison, wrong read/callsite,
struct-value casts, inverted page comparison, removed breaks, and each bound
moved below the first read. This is structural evidence for the captured
compiler's output, not a verifier for arbitrary C. It does not measure
kernel ops/churn allocation behavior.

Final build receipt `build-03/qualification.json` SHA256:
`d55f589500e3b8a3791aa651bf3ee20e375cbcec28bc1c671f0340137136cb85`.
ELF SHA256s: x86_64
`ca807b0d800c4f5ff13b8ca1e12dad4af022a49851f54f239af8d99ef969636e`,
AArch64 `d03a7547ab1f8d0b63ac451d32df22ac01d685e16276e7868d90dfe375249e27`.
Generated-C SHA256s: x86_64
`1c7dc1b491c9e8f7debcb8bf68978614d5ca54f923c0c77ca19788fc556c920e`,
AArch64 `801386ebfd522f30030476d63ace8685af743d732e007b2612202242f377892c`.
The before and both after selected-input maps are byte-identical, SHA256
`cabe0f7cb48e64c70e3e74519a531473ad39b9283a58ff1bf669360f75bac608`.
The external `build-03/source.patch` tracked-source patch SHA256 is
`bbf47e280990b368fdd38a8917770de3024df078254a13aa116372e421fd7e25`;
the added helper is pinned separately by its hash above. Tested pointer
source SHA256s are locks
`74067cb8deb1f7d41bfc1deeee51af94b48ece3761078c179ed06a90d7a6a1b6`
and slab `5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4`.
Per-architecture retained-artifact map SHA256s are x86_64
`61e0d743612a369dae5edb05106a5181c8b8be6efd4a0d7f9a04aa62e607729b`
and AArch64 `d0391f633e3ef678fad79a0a657b3cc227561dd24c420f4a35af98aa7af04f0f`.

The exact private V executable, complete vlib/thirdparty tree, dependency
directories and literal symlinks, compiler runtime, project sources, selected
tool executables and relevant environment are pinned before/after. V executable SHA256 is
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`;
LLVM23 clang SHA256 is
`4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8`.
The existing private V toolchain executes in place, with its own vlib and
compiler runtime. Host CLT compiler/linker, resource headers and SDK metadata
are also pinned, but the entire host SDK is not retained. The historical
runner does not inventory LLVM/LLD's loaded dylib closure or intermediate
Homebrew `opt` symlinks. These checks therefore do not establish a complete
mutable tool closure or a hermetic toolchain bundle.
Keep the `ld.lld` spelling: LLD chooses its ELF flavor from argv[0].

Reproduce by compiling the maintained build runner with the pinned private
V/clang and `-gc none -manualfree -keepc`, then invoke it with a fresh absolute
output directory under a dedicated parent. `bootstrap-05/build.argv.json`
and `build.environment.json` retain the exact bootstrap invocation and caller
environment; `build-03.invocation.json` binds the actual runner executable
and source. Runner source SHA256 is
`ebaaab43b70f9ae05559cc13ebcca6411e2423ce77aa95153a40a8dfd143949f`.
The runner requires the isolated baseline and declared source/dependency
set, checks actual `df -k` >=2GiB at each architecture's admission and >=1GiB
while building, and observes the whole dedicated state parent plus worktree
against 512MiB. Final observed size was about 147MiB. These are sampled
limits, not filesystem quotas. Process-group identity has the same trusted
host limitation as the host checker. The historical runners use unbounded
`os.exec` for inventory and budget probes; the build loop's 15-minute deadline
is not a hard wall-clock bound if one of those probes stalls. The separate
matched-source runner adds bounded subprocess checks and dylib closure
inventory for subsequent qualification; it does not retrofit this evidence.

All failed attempts remain intact. `build-01` refused an unresolved sparse
symbolcore link during input inventory, before make; the runner now refuses
unresolved/cyclic links and the tracked target was materialized. `build-02`
preserves the actual x86 compiler refusal of the three implicit struct
casts. `bootstrap-04` preserves the runner-only reserved-local-name refusal
before make, fixed by renaming the local. Earlier bootstraps are retained.
No compiler flags, ABI checks or kernel assertions were relaxed on retry.

The complete retained kernel-state directory, including every failed bootstrap
and build attempt, has a separate typed checksum inventory at
`/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/complete/inventory.json`,
SHA256 `e8612e004f2191ee94bc6a021258df7ef2805d8b0dfdefabbb5726ca953862df`.
The maintained `frame-page-seal.v` performs two complete scans and a post-write
check; a separate final check passed. It records every regular file's bytes,
literal symlink targets and directory metadata. Symlinks are never traversed:
external dependency referents remain covered by the selected-input records,
not copied into this bundle. This is a quiescent trusted-host inventory, not
a hostile namespace guarantee or an archive/extraction qualification.

Sealer source SHA256 is
`8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4`;
its actual binary SHA256 is
`fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6`.
Its nine explicit controls passed, including equal-size byte mutation,
missing/extra files, changed link/mode, special-file refusal and exclusive
or nested-output refusal. The separate `seal-02` directory retains its source,
binary, generated C, literal argv, logs, input pins and `qualification.json`;
these sealer files are outside the raw-state inventory. `seal-01` preserves
the unexecuted draft review. Sealer `qualification.json` SHA256 is
`0214aa50bd9663fecf2da4ce9351b97c491d1869ee499dd129f7380183037171`.
Total observed state, both sealer attempts and
worktree was about 157MiB after sealing, below the same 512MiB bound.

Allocation-site checks, ops/churn/cache and desktop idle/apps/drag validation
remain queued. Do not infer their results from host or build-only checks.
