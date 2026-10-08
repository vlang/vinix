The Android runner's image preparation and post-argument validation policy is
implemented here. `run-query.v` drives the synchronous stdlib bindings in
`_run_native.py`; `run.py` retains its public functions and argparse interface.

V owns overlay traversal and hardlink tracking, inherited library closure,
USTAR payload deduplication and streaming SHA-256, optional probe staging and
checksum publication, deployment field assembly, and main validation, path
resolution and prepare/run sequencing. Previously native ELF extraction,
split planning and deployment text generation are reused without additional
migration credit. Native policy also owns QMP/input/screenshot helpers and the
live foreground, serial and input worker loops. Python retains PTY creation,
thread/library primitives and the caller's interrupt/final-cleanup boundary.

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

`input.v` owns QMP handshake/response sequencing, character acknowledgement and
retry policy, pointer events, screenshot sequencing and VM shutdown escalation.
Socket, stream and Pillow manager/entered values remain separately retained by
stdlib bindings; the native policy exits them in their original nesting order.
Unexpected controller exit retires every retained manager in reverse order,
including outer managers when an inner exit raises. Threads and live serial
supervision remain unchanged Python in this stage.

Qualification from `74c18849` passed 98 complete frozen-original/native helper
pairs and eleven actual UNIX-QMP, interrupted blocked readline, production key
mapping and Pillow output pairs per ARM64, Rosetta x86_64 and ARM ASan/UBSan
profile. Tests compare complete command/event/sleep order, original exception
identity and context, nested close errors/suppression, distinct entered values,
WTF8 text, arbitrary-width pointer operands, nonfinite floats and exact retry
and escalation bounds. Clock conversion is qualified for native float clocks.
Six forced controller-exit controls verify outer resource retirement, eight
transport controls verify pipe/process cleanup, and all ten untouched real-PTY
interactive fixtures pass per profile and through cold installations on both
actual host ABIs. Evidence is under
`~/.cache/vinix-python-to-v/android-input-policy-20261008/`. The generic binding
addition is counted honestly: this small helper stage removes 3,894 original
Python bytes but only 98 net Python bytes before any later transport reuse.

The runner reuses `build-support/native_host.py` for its wire exchange and
process/pipe retirement, while retaining its private compiler installer,
captured-waitpid process class, original EOF text, error objects and outer
lock. Query processes use a private session so terminal Ctrl-C reaches the
caller and its original exception can unwind socket/stream managers; the
compiler installer keeps its previous process behavior. Resource fallback
continues to retire handles, archives and reverse-ordered contexts under the
transport's SIGINT guard. This consolidation receives zero additional
original Python port credit.

The pre-consolidation controls and frozen implementation corpora passed on
ARM64, Rosetta x86_64 and ARM ASan/UBSan: 539 preparation/main/split/file/manager/
result/VM-plan pairs, 98 helper pairs, twelve actual-library pairs (including
caller-PID and caller-process-group SIGINT at blocked QMP readline), 34 exact
native error-reconstruction/decoder-identity pairs, fourteen retirement
controls and ten unchanged real-PTY fixtures per profile. Cold private
installations also passed all ten fixtures on both actual host ABIs. Evidence
is under `~/.cache/vinix-python-to-v/android-run-transport-20261008/`.

Binary initialization alone is serialized. Independent keyboard/QMP/screenshot
calls retain separate controller pipes, error tables and resource owners, so a
key acknowledgement wait cannot hold up foreground capture past the original
input-thread deadline. This is a zero-credit concurrency correction.

Each ARM64, Rosetta x86_64 and ARM ASan/UBSan profile passed three paired
foreground-progress/error-identity controls, two nested keyboard/QMP pairs,
concurrent cold initialization with one actual compiler invocation, and two
failed/interrupted compiler retry controls with exact failed-owner cleanup.
The existing 649 workflow/helper/actual-library pairs, 34 error reconstruction
pairs, fourteen retirement controls and ten unchanged PTY fixtures also passed
per profile. Evidence is under
`~/.cache/vinix-python-to-v/android-helper-concurrency-20261008/`.

`supervisor.v` owns live serial polling and byte forwarding, acknowledgement
transcript extraction, input sequencing and foreground marker/deadline/join
policy. Each reader/input worker uses an independent controller. The parent
holds the shared bytearray, error/retry lists, Event and Thread objects; callbacks
mutate these original owners directly. The input join remains 25 seconds and the
reader join remains two seconds. The caller keeps its original PTY creation,
interactive interrupt fallback, screenshot and VM/descriptor/socket cleanup, so
an interrupt between native callbacks still follows the original boundary.
Worker exception boundaries retain OSError versus Exception routing and original
threading.excepthook behavior. The serial log's distinct manager/entered values
retire explicitly or through transport fallback.

Qualification against frozen source `2bd0606f` passed 54 exact serial/input/
observer pairs and 75 foreground/deadline/error pairs on ARM64, actual Rosetta
x86_64 and ARM ASan/UBSan. Five complete real-PTY pairs per profile cover more
than 1.2 MB drained during blocked keyboard input, OSError versus other thread
exception identity, and caller-group Ctrl-C before and after READY. Two abrupt
serial-owner retirement controls and two foreground EOF/constructor retirement
controls passed per profile. All existing 649 workflow/helper/library pairs,
34 error-reconstruction pairs, fourteen transport/resource retirement controls
and ten untouched interactive PTY fixtures passed against the final controllers;
cold private installations also passed all ten fixtures on both host ABIs.
Evidence is under `~/.cache/vinix-python-to-v/android-supervisor-20261008/`.
The stage ports 3,352 original Python bytes (66 policy lines), with 925 net
Python bytes removed after bindings. It adds no Android device or guest claim.

A zero-credit context replay correction restores the retained error's traceback
before invoking `__exit__`, as well as afterward. Managers again observe their
supplied traceback as `error.__traceback__`, while the original error remains
active for exit and suppression truth coercion. Python 3.9's internal
`sys.exc_info()[2]` can retain the replay frame; identical frame lists are not
claimed across the controller boundary.

ARM64, actual Rosetta x86_64 and ARM ASan/UBSan passed eighteen direct original/
production traceback relation, active-error and suppression/replacement pairs,
54 native worker/observer pairs with the same relation checked inside managers,
the existing file/manager/helper/library/decoder corpora, sixteen owner/transport
retirement controls and all ten unchanged interactive PTY fixtures. Evidence is
under `~/.cache/vinix-python-to-v/android-manager-traceback-20261009/`.
