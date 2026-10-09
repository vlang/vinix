# Native Dota guest controllers

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

The streamed digest also compares a sparse 512 MiB file with the frozen
Python implementation. Both retain about 2.1 MiB at peak. Previous blocks
retire after the next block arrives; the last block survives stream exit and
digest creation. Generator cleanup runs before stream exit under the actual
saved exception. These ownership corrections receive no additional
translation credit.

`steam_inputs.v`, `steam_main.v` and `steam_pty.v` own the Steam loader fixture's
input validation, source cache, preloads, compiler and archive commands,
environment, serial loop, process retirement and result publication. Public
argument parsing and the independent C loader remain unchanged. Temporary
whole-file hash inputs retire after each digest. Serial steps release owners
while keeping the latest raw block through log exit, process retirement and
result publication; the accumulated transcript remains owned.

Steam qualification compares 74 complete frozen workflows, four actual PTY
cleanup controls and 100 repeated successful PTY retirements on ARM64, x86-64
and ARM64 ASan/UBSan. A 32 MiB serial workload retains at most two raw blocks
and matches the original transcript peak. Both host ABIs also compare public
signatures, fresh query installation and CLI errors with an unavailable
compiler. The original 600-second guest and five-second retirement deadlines
are unchanged. Invalid post-fork deadlines and stop failures now retire owned
resources; an earlier stop error still overrides a subsequent close error.
The completed close-failure branch preserves the original open descriptor,
which is measured and retired by the qualification observer.

The actual frozen and native prepared ARM guests both pass Valve library
loading on four CPUs and 4 GiB RAM. This covers loading, with no API
initialization, game, rendering, fresh kernel build or physical GPU claim.
Two earlier package-server startup deadline failures remain in the evidence;
the passing pair uses the same verified, prebuilt package query. Receipts and
logs are in `~/.cache/vinix-python-to-v/dota-steam-guest-20261009/`.
