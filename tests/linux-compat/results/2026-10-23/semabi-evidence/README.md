# Native semaphore argument ABI

Qualified subset: native AArch64 and x86-64 ELF64, static musl, SMP Vinix
guests (four CPUs on AArch64, two on x86-64). Linux references use 6.12.51 and the identical probe ELF for each
architecture.

| Architecture | Original Vinix | Corrected Vinix | Linux reference | Queue/storage regression | Maintained runner |
| --- | --- | --- | --- | --- | --- |
| AArch64 | 175 checks, 90 failures | 175, 0 failures | 175, 0 failures | 11,163, 0 failures | 175, 0 failures |
| x86-64 | 175 checks, 90 failures | 175, 0 failures | 175, 0 failures | 11,163, 0 failures | 175, 0 failures |

The count uses its unsigned low 32 bits; SETVAL uses its signed low 32 bits.
Controls exercise upper register words, invalid and removed IDs, bad and
guard-page-crossing vectors, empty/excessive counts, ignored unknown flags,
timeout import/validation order and absence of mutation after refusal. Error
precedence describes the measured Linux version. Each queue regression also
retains all four warmed storage cohorts: every slab class and big-heap page
count stays flat over 200 measured cycles, after 200 warmup cycles. The strict
storage auditor checks lifecycle and signal totals as well as the final verdict.

Raw evidence:

- AArch64: [original serial](arm/baseline/serial.log), [corrected serial](arm/native/serial.log), [Linux serial](arm/reference/serial.log), [queue/storage serial](arm/wait/serial.log), [maintained runner receipt](arm/maintained/receipt.json), [maintained serial](arm/maintained/semabi/serial.log).
- x86-64: [original serial](x86/baseline/serial.log), [corrected serial](x86/native/serial.log), [Linux serial](x86/reference/serial.log), [queue/storage serial](x86/wait/serial.log), [maintained runner receipt](x86/maintained/receipt.json), [maintained serial](x86/maintained/semabi/serial.log).
- Production build receipts: [AArch64](arm/build/receipt.json), [x86-64](x86/build/receipt.json). The immutable before/after maps pin the kernel, compiler, build support and dependencies.
- [Source change](source/change.diff), [source identity](source/identity.json), [generated C review](review/generated-review.json), [artifact and external-pin manifest](manifest.json).
- [AArch64 strict storage audit](attempts/storage-audit2-arm.log), [x86-64 strict storage audit](attempts/storage-audit2-x86.log).

Compile `tests/linux-compat/semabi-evidence.v` with V without `-prod`, run
`--self-test`, then `check` with this directory. It rehashes the manifest and
links compilation, architecture-specific ELFs, successful builds, expected
original failures, unchanged Linux probes, corrected runs and maintained-runner
receipts. The checker requires exact, unique summaries and rejects mismatches,
panic text and wrong-architecture ELFs. The retained `tooling/semwait-evidence`
binary and `tooling/semwait-evidence.v` audit the storage serials with
`audit-storage arm|x86 full LOG`.

The isolated candidate is `51451adf1564de86e531b1de5a70f558d9bdb9b3`, based on
`033b04639076b7e8982504322c64443f167afd20`. Semaphore source SHA-256 is
`a2236eea20c6a0bf53aee5dc41db4f06d03b582459c3eaf892d0bd937f32c9da`.
Generated C confirms explicit 32-bit casts and stack timeout/vector storage.
Queue ownership and teardown are unchanged; their separate lifetime, allocation,
forced-exit and desktop qualification is retained in
[the wait-queue record](../semwait-evidence/README.md).

The attempts directory retains command statuses and logs, including a wider-cast
draft stopped during compilation and the initial maintained AArch64 attempt
refused by a private compiler wrapper's state-directory restriction, followed
by a QEMU UNIX-socket path-length refusal. These are
separate from the successful fresh attempts. Earlier setup logs are retained;
not every abandoned state directory is copied. Large boot media and external
toolchains are omitted with explicit historical content pins. Private V helper
sources and selected executables/generated C are retained to explain the commands.

Vinix still limits vectors to 32 operations and returns E2BIG above that bound.
SEM_UNDO is accepted without undo adjustments; IPC permissions, namespaces,
per-index GETPID, GNU libc, translated and 32-bit paths remain unqualified.
This record does not qualify concurrent work in the shared checkout or close
the broader libc, application installation/sandbox or foreign-runtime gates.
