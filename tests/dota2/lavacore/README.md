# Native Lavapipe comparison controller

`lavapipe-run.py` retains argparse, imports, constants and the public helper
signatures. This module owns hashing iteration, ELF validation and pinning,
private-runtime dependency traversal, fixture construction, compiler commands,
provenance, guest invocation and the complete paired-driver verdict policy.
The independent `lavapipe-native-wait.c` and `lavapipe-null-sets.c` guest fixtures
are unchanged. No game execution is claimed by this fixture.

`_lavapipe_native.py` borrows the shared kernel-gap library bridge and the
committed native-host transport. Actual Path objects, public helper overrides,
argparse objects, iterators, exceptions, compiler and tarfile calls remain in
the importing Python process. V controls their ordering and policy. No Python
implementation source is sent to V or placed in data strings. The optional
`VINIX_LAVAPIPE_QUERY` override selects a prepared controller; ordinary calls
compile through `build-support/run-v-tool.sh` and install a private mode-0700
binary. Host V uses its normal GC; no kernel allocation path changes here.

Each synchronous call retains all borrowed inputs and returned library objects
until the controller finishes. Entered file/archive values are distinct from
their retained context managers. Explicit exit clears the manager owner before
calling `__exit__`; failed entry does not register it. A broken controller is
reaped before fallback context retirement. Saved errors and their actual
traceback properties are restored before error callbacks and after replay,
while preserving deliberate manager traceback changes, so cleanup suppression, overriding errors and identity are preserved. Python 3.9
active `sys.exc_info()[2]` includes an internal replay frame; exact traceback
frame lists are not an interface claim. Nested public guest boot calls own
their own PTY child and descriptor; this controller borrows those results.

The small shared bridge additions (optional transport, native exception
construction, error classification, exported V bindings and the traceback
property correction) have zero new algorithm credit. The previous kernel-gap
receipt stays immutable and its complete host gates were rerun against the
updated source.

Qualification is recorded in the machine-local cache
`/Users/alex/.cache/vinix-python-to-v/dota-guest-workflow-20261008/qualification.json`.
The frozen original and native controller passed on ARM, x86 and ASan/UBSan:
7 public signatures, 255 verdicts, 53 digest/ELF/pin cases, 2 cyclic or missing
library closures, 3 dependency-output cases, 56 complete workflows and 19 file
manager/error/interrupt cases. One hundred repeated file owners and one hundred
shared whole PTY owners returned to their exact descriptor baselines. The
unchanged 12 kernel-gap tests passed for original and native profiles. Both
host ABIs passed cold installation and 4 exact CLI controls. Ownership received
an independent peer review.

The frozen and native full Lavapipe workflows also built the unchanged native
waiter and x86 probe and ran fresh prepared-input ARM QEMU guests on four CPUs.
Their 12 driver/mode observations and verdicts match: each of two controls
passes ordinary binding and receives SIGSEGV in the three null-set modes; the
fixed driver passes all four modes. Kernel, translator, drivers, runtime
closure and generated ELF hashes match. The prepared ARM kernel hash is
`63ed08e26058355f4c0f02e9d1cee06fe1ef82f43b405a9350bbd331b3c28ac0`.
This is prepared-binary evidence, not a fresh kernel build, hardware result,
rendering check or Dota game run. Compiler/setup and stdout parity failures
from early drafts remain recorded separately from passing gates.
