# LinuxKPI independent host fixtures

`run.sh` generates the independent fixtures and pthread scheduler model from
maintained V, links them against the production LinuxKPI objects and unchanged
upstream Linux helpers, then runs the complete workload and all seven sleep
boundary modes under ASan/UBSan. Each fixture retains its own public header and
native type namespace. Generated C is a temporary build artifact.

`hostmodel/` preserves the original page ownership, task pins, queue locks and
condition-variable lifecycle. `host_model_tls.S` supplies native per-thread
storage because the frozen V compiler ignores `thread_local` for its Vinix
target. The formatting and logging assembly captures the native variadic
arguments; their fixture bodies are V. `compile-native-host.py` builds the
same assertions against the actual ARM or x86 musl SDK, with `hostguest/` as
the child-process supervisor.

This change is committed at the user's request while **native x86 validation
remains pending**. It replaces `test.c` and 26 independent headers totaling
8,929 original lines from immutable revision
`9f47270ee3c6754312bc09fc74d8f77e2cfe2229`. It receives **zero completed
translation credit** until the required native comparison is resolved.

The frozen validation recorded in [host-fixture-validation.json](host-fixture-validation.json)
has the following results:

| Comparison | Recorded result |
| --- | --- |
| Complete V workload, actual Darwin ARM64 ASan/UBSan | PASS, including all seven boundary modes |
| Complete V workload, actual Darwin x86_64 ASan/UBSan | PASS, including all seven boundary modes |
| Immutable original C workload, actual Darwin x86_64 ASan/UBSan | PASS |
| Native ARM original C workload | PASS, including all seven boundary modes |
| Native ARM V workload | First attempt failed the unchanged bound-CPU assertion; identical image repeat PASS |
| Native x86 original C, four CPUs, `max`/TCG | Timed out at the unchanged 3,600-second allowance |
| Native x86 original C, four CPUs, `qemu64`/TCG | Child status 9 (SIGKILL); cause unknown |
| Native x86 V, four CPUs, `qemu64`/TCG | Original bound-CPU assertion, child status 6 (SIGABRT); cause unknown |
| Separate failure-only x86 diagnostic | SIGKILL before routing operands were printed; cause unknown; no validation credit |
| Fresh matched x86 original C on default kernel `a5ae7a96`, `qemu64`/TCG | Original first bound-CPU assertion; SIGABRT after 1,100.94 seconds |
| Fresh matched x86 V on that same kernel and configuration | SIGKILL after 907.04 seconds; both required PASS markers absent |

All original assertions, operation counts, deadlines, cleanup requirements and
seven modes (`reversed`, `huge`, `clock-horizon`, `absolute-overflow`, `state`,
`atomic`, `valid-horizon`) remain. The CPU and kernel configuration changes
between attempts are recorded; no earlier failure is claimed resolved. A
wait status alone establishes neither OOM nor a translation bug.

The fresh pair used the exact previously recorded canonical ELFs, four CPUs,
1,024 MiB, new guest states, all 26 fixture groups and seven boundary modes,
and the unchanged 3,600-second maximum. The C control now fails the same
expression that previously failed in V; the defect remains unlocated.
Sequential pre-failure observations found a zero OOM counter, which does not
establish the cause of SIGKILL. A source and actual supervisor-instruction
audit found no internal 900-second watchdog. Neither fresh run qualifies the
port. Receipts, captured boot inputs and failure logs are retained in
`host-native-default-pair-20261007/`; cache-only diagnostic rebuilds are
separate from these canonical controls and receive no qualification credit.

A separate cache-only original-C failure diagnostic ended after 437.62 seconds
(2026-10-07 08:11:55.957136–08:19:13.508734 UTC) with full-workload child
status 9 (SIGKILL), before any conditional CPU-mismatch operands were emitted.
Its verified boot kernel remains `a5ae7a96…`; the rebuilt diagnostic init is
`b5a16b58…`, distinct from both untouched canonical final23 controls.
All 26 groups, seven boundary modes, original assertions/counts/ownership and
the 3,600-second maximum remain unchanged. No OOM or complete runtime-limit
sample was collected in this run. The cause is unknown and this diagnostic
adds zero credit to the pending 8,929-line checkpoint.

The strict rebuild used frozen V/GCC/SDK inputs, cache-only native-header
namespace adapters and the existing core warning policy for shared upstream
header consumers. Generated compat/headercore C hashes match final23, but only
1,226 of 1,267 common functions match after relocation/symbol/string
normalization; all 41 remaining differences are retained. These include source
file strings, a jump-table relocation, instruction scheduling/padding and the
supervisor's array initialization; missing original temporary compiler flags
prevent a full binary-equivalence claim. Complete commands, compiler-visible
preprocessed inputs, patches and raw disassemblies are retained under
`host-native-default-pair-20261007/original-C-failure-diagnostic`; its
`native-run/validation.json` SHA256 is
`0bc6a77924ed8d4b28362b9474c7afedb5e78d82a6447a7ec5f1f1f6b0cdc058`.

The commit review matched all 96 owned input hashes to the passing dual-host
receipt and all 27 deleted Git blobs to the immutable original scope. Three
whitespace-only cleanups then generated byte-identical C for both target
architectures with the frozen compiler. The review also verified the recorded host/native logs and scoped whitespace, Python syntax
and shell syntax. These are preserved results on the frozen production
dependency snapshot, not a claim that the concurrently edited checkout was
rerun. Raw receipts and logs remain in
`/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/`, primarily
`host-whole-x86-clean/`, `host-native-final23/` and
`const-string-logger-abi/`. The migration documents record the wider campaign.

To run the maintained host suite with the frozen compiler:

```sh
V=/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/toolchain-v/v \
  ASAN_OPTIONS=abort_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
  tests/linuxkpi/run.sh
```

To generate an assertion-enabled native workload:

```sh
V=/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/toolchain-v/v \
  python3 tests/linuxkpi/compile-native-host.py /tmp/linuxkpi-host-arm --arch aarch64
V=/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/toolchain-v/v \
  python3 tests/linuxkpi/compile-native-host.py /tmp/linuxkpi-host-x86 --arch x86_64
```

Native compilation alone does not complete the required original-C/V guest
comparison. Keep the original failures, identical-image identities and equal
comparison budgets when continuing that work.

The separate native PID 1 is maintained in `initfixture/core_amd64.v`.
`run_vm.py` generates its freestanding build artifact and links the
instruction-only ELF entry in `initfixture/entry.S`, which supplies the native
stack alignment. The immutable original is
`2a5abc36175a5177828d86aad71667787eb68110:tests/linuxkpi/guest_init.c`
(28 lines, SHA256 `eb6ad04b78a6bfee92a4c32fe3aa2ae26a1158de21cd379da2a70430610f06e9`).
The port preserves eight 2,000,000-iteration volatile userspace intervals,
the syscall registers/barriers, all 21 verdict bytes and the borrowed 16-byte
nanosleep record. Strict freestanding and both genuine x86 musl compiler
builds passed without allocator imports. Complete original-C/V controls
passed all 42 markers and 19 exact memory equalities on the same recorded
kernel; both default boots passed too. This x86 fixture adds no new ARM,
host syscall sanitizer or production kernel-build claim. Local receipt:
`linuxkpi-init-stage-validation.json` in the campaign cache above.
