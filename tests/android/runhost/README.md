The Android runner's image preparation and post-argument validation policy is
implemented here. `run-query.v` drives the synchronous stdlib bindings in
`_run_native.py`; `run.py` retains its public functions and argparse interface.

V owns overlay traversal and hardlink tracking, inherited library closure,
USTAR payload deduplication and streaming SHA-256, optional probe staging and
checksum publication, deployment field assembly, and main validation, path
resolution and prepare/run sequencing. Previously native ELF extraction,
split planning and deployment text generation are reused without additional
migration credit. The live PTY supervisor and QMP helpers are still Python.

`result.v` owns complete post-session probe verification, marker and failure
precedence, optional preflight identities, result fields, JSON/status publication
and exit status. The transcript remains an owned byte snapshot: exact-line and
substring marker checks retain their original distinctions. CPython bindings
retain byte decoding, arbitrary-width integer conversion and JSON encoding;
V owns selection, validation and all result policy.

Python binds pathlib/shutil/tarfile operations, process execution, imports,
original caller functions and mutable Namespace/inode collections. The bridge
passes owned snapshots through the shared tagged transport, preserving wide
integers, non-finite float types and lone surrogates. No borrowed C storage
crosses a callback. Newly initialized checksum collections retain their object
identity while entries are appended or replaced.

Input streams and archives have explicit context-manager owners. V retires
inner read streams before archives and forwards the retained original error
object to `__exit__`, including suppression and later-error precedence. This
preserves TarFile's distinct successful and failed USTAR finalization. The
parent retains owners until retirement and closes them after an unexpected
controller exit. SIGINT is masked across nested pipe, bounded child retirement
and owner cleanup, then the prior handler is restored. A timed-out controller
is killed and reaped without replacing its returned result; other wait errors
retain their original exception. Private compiler scratch is removed on error
or interpreter exit.

Qualification against the frozen complete original `run.py` at
`9878439f2a2bbb920aab8dbd6af38f535a426f19` passed on actual ARM64 and Rosetta
x86_64 hosts, and with an ARM ASan/UBSan controller, using V 0.5.2
`6d549c2f095d5e3e97963e55a2ebf1dc2810db46`. Each profile passed:

- 22 whole image-preparation workflow/error pairs, with exact compiler argv,
  overlay bytes/modes/symlinks/hardlinks, partial state and caller mutations;
- 49 whole-main return/error, output, constraint precedence and Namespace pairs;
- 140 whole split workflow pairs covering JSON types, non-finite values, lone
  surrogates, shell quoting, 102 launcher indices and partial filesystem errors;
- 14 layer/dependency/archive pairs, including exact raw tar bytes, read/close
  precedence and original exception context;
- all 10 unchanged independent interactive PTY tests;
- seven original/native CLI pairs, help without a compiler and cold private
  source-closure installation with interpreter-exit retirement;
- eight forced controller/pipe/wait/stream retirement controls.

Independent fixed stdlib timestamps make archive bytes comparable; the original
algorithms and assertions remain unchanged. Qualification data is machine-local
under `~/.cache/vinix-python-to-v/android-run-orchestration-20261008/`.
This host stage does not claim a new kernel/QEMU/Android application boot.

The result follow-up at original source `4d5b5e18` passed 239 paired controls on
ARM64, Rosetta x86_64 and ARM ASan/UBSan. These compare complete raw JSON and
field order, probe/failure precedence, malformed serial UTF-8, Unicode and lone
surrogates, 100-digit queue exit statuses, zip truncation, wide/non-finite fields,
missing/malformed caller attributes and original library exception identities.
All ten unchanged interactive PTY tests passed on both original host ABIs and
all three new profiles, including cold private installation inside the VM mocks
on both ABIs. Eight forced controller retirement controls passed per profile;
three compiler-error/interrupt/scratch retirement controls passed on both ABIs.

Private controller reaping uses captured waitpid/monotonic primitives and
Event.wait, preserving Popen's waitpid lock and the five-second retirement bound
while VM waitpid/sleep mocks continue to apply only to the VM operations.
Successful context-manager exits ignore their return object, as Python `with`
does; a separate zero-credit follow-up passed 18 file/manager controls per
profile, including suppression, distinct entered handles and truth-result
exception context. The result evidence is under
`~/.cache/vinix-python-to-v/android-run-result-20261008/`.

`vm.v` owns pre-fork kernel snapshot sequencing, materialized-overlay payload
accounting, boot disk sizing, environment updates and QEMU runner arguments.
Its environment, argv and arbitrary-width integer values are GC-owned copies;
the original PTY/thread ownership begins only after the plan returns. The
remaining supervisor and input/reader loops are unchanged Python.

Qualification from source `35c6681c` passed 57 complete original/native plan
pairs per ARM64, Rosetta x86_64 and ARM ASan/UBSan profile: exact environment,
argv, stat/platform call order, kernel snapshot bytes/modes, partial failure
state and original exception identity. Controls cover 100-digit payload sizes,
MiB/512-MiB boundaries, overlay hardlinks and symlinks, inherited environment,
platform/display choices, missing inputs/attributes and blocked snapshots.
All ten unchanged interactive tests and cold source-closure installations also
passed on both native host ABIs. Evidence is machine-local under
`~/.cache/vinix-python-to-v/android-vm-plan-20261008/`.
