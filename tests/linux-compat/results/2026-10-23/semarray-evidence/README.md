# Native semaphore array control qualification

GETALL exports exactly the set's unsigned-short values; SETALL imports and
validates the entire array before committing all values and operation PIDs,
then progresses eligible waiters. Both ignore semnum. Invalid pointers return
EFAULT, values above 32767 return ERANGE, and invalid IDs return EINVAL before
pointer handling. A set removed during unlocked SETALL import returns EIDRM.

| Native ELF64 target | Original Vinix | Corrected Vinix | Linux 6.12.51, identical probe ELF | Maintained regressions |
| --- | --- | --- | --- | --- |
| AArch64, 4 vCPUs | 457 checks, 304 failures | 457 checks, 0 failures | 457 checks, 0 failures | semarray 457, sempid 261, semword 276, semabi 175; all pass |
| x86-64, 4 vCPUs | 457 checks, 304 failures | 457 checks, 0 failures | 457 checks, 0 failures | semarray 457, sempid 261, semword 276, semabi 175; all pass |

The 457-check V fixture covers set sizes 1, 4 and 32, initial zeros, exact
copy lengths and guard elements, ignored negative/extreme semnum values,
zero/maximum values, each invalid array index, fault-before-range error
precedence, protected/page-crossing buffers, read-only input/output,
unchanged values and PIDs on refusal, same-value SETALL by another process,
and queued decrement vectors and zero waits. Failed SETALL leaves a waiter
blocked; successful SETALL commits the whole array before progressing it.
Baseline fallback SETVAL calls allow the original kernels to finish and
produce full failing summaries rather than hanging on unsupported commands.

Production kernels were built in separate worktrees from isolated candidate
`25a48efae23ed887ecd45559d7ec8b929e224809`, directly based on
`004aaa782d989515399ccdcd9e94b81094337dcb`. Semaphore source SHA-256:
`22b78bee6e8bbab1e3a84f45ab74574f81c6e5779b223ae6b02c4d3aebcd562c`.
Each build's input hashes agree before/after. The original kernels are the
previous per-index-PID qualified binaries. The identical static musl probe
ELF is used on original Vinix, corrected Vinix and Linux for each target.

Generated-C review confirms two 64-byte stack buffers and no new allocation
or lifetime. GETALL snapshots under the IPC lock and copies out after unlock.
SETALL copies and range-checks outside the lock, then looks up its monotonic,
non-reused ID again before dereferencing the set. All values and PIDs are
stored under the lock before queue progress. No ownership/free path changes.

Audit with V, without `-prod`:

```sh
v -o /tmp/semarray-evidence tests/linux-compat/semarray-evidence.v
/tmp/semarray-evidence --self-test
/tmp/semarray-evidence check tests/linux-compat/results/2026-10-23/semarray-evidence
```

The checker binds all retained hashes, ELF architectures, compile/build
receipts, unchanged build inputs, native/original/reference probe identities,
exact success/failure summaries, maintained regressions and generated-C
review. Its nine negative controls pass. The Linux result parser separately
passes two positive and nine negative controls. Initial unsuccessful fixture
compilations and review-tool compilation remain retained with their statuses.
Large boot media and external tools have explicit SHA-256 pins in the
manifest; retained binaries, generated C, serial logs and command receipts
permit inspection without those private paths. The completion directory
records the successful final audit and manifest/checker identity.

This qualifies GETALL/SETALL for the existing native 32-semaphore subset.
SEM_UNDO, IPC permissions/namespaces, IPC_STAT/IPC_SET and other unimplemented
commands, timestamps, removal-during-usercopy races, GNU libc and translated
or 32-bit paths are not qualified here. The broader libc, application
installation/sandbox and foreign-runtime roadmap gates remain open.
