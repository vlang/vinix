# Native paired glibc environment controller

`environment.v` owns the paired fixture's input validation, compiler commands,
pinned files, archive, boot environment, provenance and guest result policy.
`inputs.v` owns the bounded ELF inspection, runtime lookup and streamed digest
loops. The existing environment verdict parser and independent C workloads are
unchanged. The Python frontend retains its public signatures, constants and
argument parsing, including errors that must work without a V compiler.

The library bridge reuses the committed Dota game and kernel-gap owner tables.
Actual Path, hash, iterator, module, Namespace and parser objects remain in the
importing process. A zero-argument reader callback retains the entered stream and performs deferred
attribute access, while the caller's sentinel iterator performs its library
comparison; V owns the hash loop. A generic lazy producer transports V-owned
runtime candidate policy while preserving caller overrides of `next`. Managers remain distinct from their entered values and are consumed
before explicit exit. The importing owner preserves cleanup suppression,
exception identity and the saved traceback property, and unwinds entered
managers only after the native controller has been reaped. Existing PTY
ownership remains with the nested public kernel-gap boot helper.

Qualification compares the frozen original with ARM64, x86-64 and ARM64
ASan/UBSan controllers: 60 complete workflows, 28 helper cases, six public
signatures, 12 rich-operation, constructor-shadow, retained callback and lazy iterator controls, 15 manager/error controls and 200 actual file retirements per
profile. Both host ABIs also install the query with mode 0700 and compare six
CLI errors/help cases, including with an unavailable compiler.

The actual frozen and native prepared ARM guests passed the same unchanged
paired control on four CPUs and 2 GiB RAM. glibc 2.36 exited with SIGSEGV 11;
glibc 2.41 completed all 32 rounds and 32,000 writes with successful concurrent
checks and native exit zero. Host and per-variant deadlines remain 240 and
110 seconds. This verifies environment synchronization with the retained
kernel and translator; it does not claim a fresh kernel build, game execution,
rendering or physical GPU operation. Local immutable receipts and logs are in
`~/.cache/vinix-python-to-v/dota-environment-guest-20261009/`.
