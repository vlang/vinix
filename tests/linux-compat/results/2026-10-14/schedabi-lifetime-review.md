Independent schedabi lifetime review: PASS

Reviewed the legacy scheduler argument guards, input-copy ordering and signed 32-bit PID/policy decoding against frozen baseline `108082c1e0513e87559e47fde420471ccc2f15f7`. The error-ordering fix is separately committed as `4ca8f7fa2`. The final repository source equals the private candidate and both production build inputs. Completed original/intermediate/final production C, final preflight5 C/ELFs, all p3 native and actual Linux reference captures, and both completed five-case native receipts were independently consumed. No lifetime blocker remains. General scheduler, desktop, application and multi-CPU QoS qualification are separate from this review.

The setters first validate negative/null scalar arguments, then synchronously copy exactly four bytes into a genuine stack `priority32` before target lookup. A failed or partial input copy returns EFAULT without consulting the partially filled scalar or mutating a target. The getter validates its negative/null arguments, resolves the target and copies its scalar priority through the existing synchronous user-copy path. Signed word decoding creates scalar locals and preserves the full-width user pointer. These changes introduce no direct allocator, free, array or interface-box calls. Usercopy's existing page resolution and copying remain unchanged; no kernel function retains one of these local addresses after returning.

Target resolution returns a TID and copied SchedParams, whose fields are all scalars. The proc lookup, permission and mutation functions retain their existing internal PID-table locks and MAC checks. No new thread pointer is carried across a released lock. Policy validation, permission checks, final installation, priority donation and queue code retain their original production C. Concurrent target reuse and complete permission/race behavior are not qualified by these self and absent-target tests.

The final fixture's generated C has seven explicit alloca sites, fixed C arrays and no malloc, memdup, dynamic-array mutator or bounded-index helper calls. Scheduling inputs/outputs, sentinel integers, wait status and sscanf fields are real C stack values. The two credential cohorts run sequentially in forked children; UID/GID changes affect only the child. Each child's probe of a terminated target waits for and reaps that child before using its former ID. No worker or asynchronous callback borrows fixture storage.

Each result pipe has its unused ends closed in parent and child. Counts is zero-initialized in the child, stays live through qualification and the synchronous result write, and is transferred using the same sizeof(Counts), 64 bytes, for write and read. A short read never exposes the uninitialized parent Counts to reporting. The parent closes its reader and waits for the cohort child before proceeding. Fatal setup paths exit through process cleanup; completed paths close their descriptors before returning or exiting.

The three-page mmap stays live throughout the matrix and storage measurement. It is initialized while writable, then its middle page becomes readonly and its last page inaccessible. Valid scratch pointers remain within their creating stack frames; intentionally invalid pointers are only passed to the syscall/libc query, never dereferenced by the fixture. The mapping is unmapped before Counts transfer, and no subsequent operation uses it. The slab observer closes on every nonfatal failure and success path. The checks preserve guarded stack bytes and the readonly page's observed four bytes; they do not claim arbitrary failed-copy prefixes or complete scheduling-state preservation.

Each credential cohort performs [876,1824,36,2] controls, totaling 5,476 per architecture. The decomposition is 4,600 kernel-facing/state checks plus 876 real ENOSYS checks for bundled musl's four legacy process-wrapper stubs. Raw syscalls perform setup and observations; libc priority-min/max calls exercise their genuine supported paths. The matrix covers zero/self/negative/minimum/maximum/reaped PID classes, five register-word patterns, nine parameter forms, Other/BATCH transitions, priority bounds, missing-target/input-fault precedence and invalid policy 8. Neither musl stub refusal nor an invalid-policy oracle assumption is counted as kernel support.

Independent V assertions require every CASES and FINAL row, reject duplicates or missing cohorts/kinds, and verify exact call/failure counts. Original kernels fail [124,1106,0,0] per cohort, or 2,460 per architecture. Error-only kernels fail [0,654,0,0], or 1,308 per architecture. Final native and actual Linux 6.12.51 references pass every row. The same final architecture-specific probe ELF is used by all three native phases, preflight5 and the actual Linux reference.

The error-only and final native cohorts each execute 32 warmups and 200 measured BATCH/OTHER, query/update and error cycles, with thirteen-second settling intervals around their snapshots. Independent checks require every one of 18 ARM / 14 x86 slab classes in both credential cohorts, exact live-count equality, unique size rows and both storage summaries. All classes are flat; large pages are 63/63 ARM and 160/160 x86. No baseline storage pass is asserted: its incorrect ordinary error rows prevent that measurement.

Independent complete-C comparisons remove exactly the prototypes and definitions of getparam/setparam/setscheduler to make original and intermediate C byte-identical on each architecture. Removing exactly the six legacy scheduler prototypes/definitions makes original/final and intermediate/final complete C byte-identical. All changed bodies independently reject allocator/free/array tokens. Thus user-copy, proc ownership, target locks, lifecycle, descriptor, allocation and queue implementations are unchanged in these production artifacts.

Final preview, preflight5 and every p3 native phase's fixture C are byte-identical. Source/ELF/ISO/staged-kernel receipt hashes were independently recomputed; both five-case decoded native profiles (schedabi/runtime/capabi/open/fcntlabi) have five zero-status entries with matching frozen sources. Both Linux references bind the same probe ELF, kernel, wrapper source/C/ELF, initramfs, serial adapter, transcript and controller source. Their receipts report passed=true, finished=true, forced=true and status=0: the successful probe pauses after its verified PASS, and the controller then stops QEMU. This is a semantic reference run, not guest self-shutdown qualification.

The first p1 native/Linux captures failed during setup because normal/restore used musl's ENOSYS stubs; they have no complete case rows. The p2 reference runs exposed policy 7's valid Linux SCHED_EXT priority bounds, producing 24 oracle errors per architecture. These captures and earlier warning/stage-only preflights are preparation diagnostics. The final invalid-policy-8 probe uses fresh p3 native phases and actual Linux references. The final preflight5 raw identity is exact, without helper-block normalization.

Independent inline V assertions were compiled without -prod. The deliberately false assertion exited 1 with `schedabi independent review assertion control`. Supplying the passing p3 Linux ARM capture to the same original-baseline count checker exited 1 at failures=0 versus failures=124. Passing source/C, count, storage, ELF and receipt checks exited 0. An initial overstrict reference assertion rejecting forced=true was corrected after checking the existing pause/controller termination protocol; it was not treated as a semantic baseline failure.

Qualification remains bounded to native unpledged musl ELF64 callers and these self/absent-target cases. Realtime/deadline transitions, reset-on-fork, capability/RLIMIT rules, SCHED_EXT, namespace/pledge decoding, concurrent target reuse, RR interval/attribute/affinity ABIs, GNU libc, translated and ELF32 paths remain open. AArch64 multi-CPU QoS remains unqualified. No broad section 15 completion gate is asserted.

SHA-256 pins were independently recomputed after the relevant producers completed. Paths are relative to `/Users/alex/.cache/vinix-linux-compat/schedabi-20261014`, except repository paths beginning with `kernel/` or `tests/`. Common rows require exact byte identity.

| File | SHA-256 |
| --- | --- |
| `kernel/syscall/table/gaps.v`, `candidate-gaps.v`, `kernel-{arm,x86}/kernel/syscall/table/gaps.v` | `838bf03a0110d5ec8f46b65cda1be48f547490c3efb7554684595e32f88a5cee` |
| `middle-gaps.v` | `819fdaa5ac4c0ac3bae1152e27240f6d51f6d69ca4d197902fb4012dc9e0f39f` |
| `tests/linux-compat/schedabifixture/core.v` | `de18a603b819a8534ec998e1229c6b6b5103bfe515bff8e81b81ee78b9c21d7d` |
| `tests/linux-compat/schedabi-reference.v` | `6d2b2dd8fd83b94bd14e41d5fc5e4fada162979a8446eee8dd6ed569bf0cc673` |
| `tests/linux-compat/schedabireferenceinit/core.v` | `a219c3690d7da16183887cda3394c3344b87c96c63e5cadb7091bed82f54c7ff` |
| `tests/linux-compat/run.v` | `5bebdf4cd10af0b4eb806235aadb639122b4f69b02b429e093617d3f1f0b2808` |
| `before-arm.c` | `3f55bd5f8a8e76a09cf8fff6da8fe7732f0e713b687fe79d0f2d378117581299` |
| `middle-arm.c` | `9a1a3aa646536a7e1f89e0704cf63ad8839665bb3f8daf5e389f8e40d17d7674` |
| `after-arm.c` | `92d51f0c2616627d00aca21444ed42914a5b27dd90703c1c8a79dcdd3a0d1cfb` |
| `before-x86.c` | `2696e616c7292edea5c0dd93f7180956dc46883f402188d2ff40725c92ec0b06` |
| `middle-x86.c` | `43e9f0254373adc4e4d89f4673e56dbb3d02311990f2df1faa3d0d4b9da65696` |
| `after-x86.c` | `cbf8cbe5449c53a7eb3840dabef48546f5a96b0edc7c6775446d66c317bc3372` |
| `preview-{arm,x86}.c`, `states/preflight5-schedabi-{arm,x86}/fixture.c`, `states/p3-{before,middle,after}-{arm,x86}/schedabi/fixture.c` | `8fff587a11dd1c2fe123b264c674428e7330f509e70451d37fd572ee0ea5c154` |
| `states/preflight5-schedabi-arm/init`, `states/p3-{before,middle,after}-arm/schedabi/init`, `states/p3-reference-arm/probe` | `aaf0c1175a0b32bee276fc84f5619c7c468643a97337fb4ee44b45900b81af18` |
| `states/preflight5-schedabi-x86/init`, `states/p3-{before,middle,after}-x86/schedabi/init`, `states/p3-reference-x86/probe` | `6e0d896226ce58749fefe9d9fa411596aa5a9f1581f88b92c469574f541b3a8a` |
| `states/p3-before-arm/kernel/bin/vinix` | `25ba9573c170eef24f2f1758192645128ffb59f780a45d4f81e688682c3d26b4` |
| `states/p3-middle-arm/kernel/bin/vinix` | `06fba5d67f4656311c91c5720337369796a9c80d202905645f74d193fc327727` |
| `states/p3-after-arm/kernel/bin/vinix`, `kernel-arm/kernel/bin/vinix` | `9a21ae1713c3f4764124971729dee9b8668f4a8bff3f82153260fb4ad6d3293f` |
| `states/p3-before-x86/kernel/bin/vinix` | `0df36abe4f0832084129afac3c559edb8cec19560e2589d564413e10688f2fc4` |
| `states/p3-middle-x86/kernel/bin/vinix` | `53faee496e6788654292ab1d7279c2377c92c182afa37329e94f771c1caa545d` |
| `states/p3-after-x86/kernel/bin/vinix`, `kernel-x86/kernel/bin/vinix` | `6984dc484e9793be57f21565849b2d5b3fcfa132ea1262388ca0725f16aa72cd` |
| `states/p3-before-arm/schedabi/serial.log` | `9c86fcf70eec66ec5b50c2fa0ef537436ae0be4c1ccd0b9a4c9497e9ea3feac4` |
| `states/p3-middle-arm/schedabi/serial.log` | `e53c594b7eeee05bc1ccca43442ae84081d8e14446b7d7f7b5791e6f189c87b0` |
| `states/p3-after-arm/schedabi/serial.log` | `1d3a6a58543c06913cc3ddf2c8a889842458deaaa4dd747d173aebc8c1d634d7` |
| `states/p3-before-x86/schedabi/serial.log` | `edba0a01d623a285d68f40bf29c24d87dae1b7da98f198b2e18655987cbf6f00` |
| `states/p3-middle-x86/schedabi/serial.log` | `eb49d6415120cd0a90df7cc77b2b219111144879e66dacf0b10e36a2b0c1c9c1` |
| `states/p3-after-x86/schedabi/serial.log` | `2e915e07cc814a90a3e7a7ac164a237bd5320b3d65ca90497240c582f2371ac7` |
| `states/p3-before-arm/receipt.json` | `085ac684aeb5f7871ef0249fa08016b08dcd80f929888d0509d8d997b3366b37` |
| `states/p3-middle-arm/receipt.json` | `a3def20957e29175bb4b922187e443e1e080cc6c222124409907b8283fbb213c` |
| `states/p3-after-arm/receipt.json` | `4ddd0d24e580f7673c79c2b27142933006d27a5df9b67fb8f5ea6c413edbeb9d` |
| `states/p3-before-x86/receipt.json` | `3eccf54ed59d5a4aff7528d96c93917e9da6144c3ea70a784098664de0161637` |
| `states/p3-middle-x86/receipt.json` | `774053984769cebe4c98eb90014777bf33f4f79c4f65b3d283c9dbc5a8f767ff` |
| `states/p3-after-x86/receipt.json` | `6853f5b2abea0d89841ff2ca67c097b888ea881e23b034a60714eafa80dcd6d4` |
| `states/p3-reference-arm/linux` | `c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f` |
| `states/p3-reference-x86/linux` | `ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4` |
| `states/p3-reference-arm/serial.log` | `f9f8f5159924d7ba8682656b4b32b52400f17441541bde78ed62e3098079611c` |
| `states/p3-reference-x86/serial.log` | `e68897d215344a34c1d4a91746b7c8c194888b912cf4872df9d02b25edb4c4ad` |
| `states/p3-reference-arm/receipt.json` | `8de9c91d0a4bcf939d7696cc1785bccd898dfd1d940940baaa592f3b22d7a45d` |
| `states/p3-reference-x86/receipt.json` | `42dcbce6a6e50d3f142e12ff4f387ff8273527a74ccb3de4c5ed3f802110d7f6` |
