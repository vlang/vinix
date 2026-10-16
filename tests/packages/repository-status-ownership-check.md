# Owned strict repository observations

`repository_status(root)` now transfers independently decoded architecture and
repository fields and the owned replay-history result into `RepositoryStatus`.
V callers retire these returned observations with `.close()`; repeated close of
one owner resets it safely. Caller-built documents can borrow fields and retain
their caller-managed lifetime. The CLI closes `repo-list` results after emitting
the existing human or JSON output.

The private reader owns configuration explicitly. After successful transfer it
retires unused policy/launch-account fields; a cache/history failure retires the
whole configuration. The public reader retires its directory path on every
return. Snapshot and migration scratch keep their existing cleanup contracts.
Wire fields, ordering and bytes remain unchanged.

Reader locks still precede configuration access whenever durable state exists.
A fresh listing creates no package store. Strict listing still refuses damaged
cache/history, unsafe coordination and an active writer; configuration-only
discovery retains its separate scope. Listing can derive authenticated expired
legacy floors without publishing history, preserves newer retained floors and
requires valid signatures and exact same-sequence digests. Existing recovery of
a disabled curve-invalid key requires the exact retained identity/digest/sequence;
it does not re-enroll that key. Enrollment, revocation and transaction behavior
remain unchanged.

The pre-change ten-call probe retained **25,430 bytes** for fresh reads and for
retained-history reads, after retiring result fields. Ten malformed-cache and ten
malformed-history refusals each retained **38,280 bytes**, after retiring returned
errors. Original production source, fixture, executable, generated C and failing
output are retained and pinned.

The final fixture requires zero retained bytes over 1,000 calls in each of those
four cases; 1,000 empty/growing 64-record observations on both metadata targets;
and twelve 1,000-cycle configuration/cache/history schema, alias, FIFO and
missing/unsafe/busy lock refusal scenarios. Restoring trusted metadata permits
retry. Refusals preserve partial downloads and staged recovery data; missing and
unsafe locks take precedence over malformed configuration. Both observations
remain independent after retiring one owner and replacing source files. The
existing bounded presentation decoder reproduces their exact wire bytes.

The combined valid 4,096-repository/4,096-history case runs outside the tracker's
16,384-live-record table; its owned strings legitimately exceed that capacity.
It still runs natively, under ASan/UBSan and in both architecture guests.

Authenticated paths retain a separate existing signed-index decoder allocation.
An expanded probe first failed the attempted zero-retention assertion with
**64 one-byte allocations across 64 legacy migrations**. An isolated V probe of
`decode_signed_index` and `verify_index`, without status/configuration handling,
reproduces those 64 bytes; `remember_index` retains zero. Final status checks warm
the signed-index metadata cache, then permit at most one byte per decode across
64-cycle migration/newer-floor/equivocation/retired-key cases and require every
retained allocation to be exactly one byte. Signature refusals before decoding
retain zero. This is an explicit dependency limit, not a whole-status zero-byte
claim; raw failed output, source, probe and final measurements are retained.

The subsequent [bounded signed-index decoder](index-decode-check.md) removes
that dependency allocation. The maintained status fixture now requires zero on
every authenticated path without warming a generic decoder cache. The results
below retain this earlier qualification's original scope and measurements.

The maintained repository guest suite adds this fixture to configuration-only
discovery and protocol checks. Host qualification includes administration,
coordination, history recovery, signed CLI maintenance and sanitizers. System-root
lifetimes, other administrative APIs, the signed-index decoder allocation,
production publisher enrollment, catalog migration, graphical login/display
integration and wider foreign-runtime acceptance remain outside this increment.

## Recorded results, 2026-10-16

All **34 focused compile/run checks** passed: ten core and one protocol pairs, one native tracked-allocation pair, two ASan/UBSan pairs including administration lifetimes, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and seven verified artifact hashes each: AArch64 **106.2 seconds**, x86_64 **166.5 seconds**. These functional deadlines are not performance qualification.

- [baseline regression](results/2026-10-16/repository-status-baseline.txt)
- [host results](results/2026-10-16/repository-status-host.json)
- [host summary](results/2026-10-16/repository-status-host.txt)
- [core assertions](results/2026-10-16/repository-status-core.txt)
- [tracked strict observation allocations](results/2026-10-16/repository-status-memory.txt)
- [sanitizers](results/2026-10-16/repository-status-asan.txt)
- [signed CLI](results/2026-10-16/repository-status-cli.txt)
- [initial assertion and isolated index probe](results/2026-10-16/repository-status-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/repository-status-toolchain.json)
- [aarch64 receipt](results/2026-10-16/repository-status-aarch64.json)
- [aarch64 report](results/2026-10-16/repository-status-aarch64.txt)
- [aarch64 serial](results/2026-10-16/repository-status-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/repository-status-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/repository-status-x86_64.json)
- [x86_64 report](results/2026-10-16/repository-status-x86_64.txt)
- [x86_64 serial](results/2026-10-16/repository-status-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/repository-status-x86_64.qmp.txt)
