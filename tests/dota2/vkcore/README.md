# Native translated Vulkan guest controller

`vulkan-run.py` keeps argparse, imports, constants and public helper signatures.
This module owns copy-layer conflict policy, native library closure traversal,
translator validation, prepared-root refresh, software GL retention, complete
archive/environment/command construction, PTY read deadlines and retirement,
XWD validation, color diversity, provenance and the final guest verdict.
`decode_capture` already uses the native transcript parser and is unchanged;
it receives zero new translation credit here. The Vulkan init script and guest
programs remain independent and unchanged.

`_vulkan_vm_native.py` borrows the committed kernel-gap library bridge and host
transport. Actual Path objects, argparse values, public overrides, iterators,
exceptions, files and tarfile calls remain in the importing Python process.
V controls their policy and order. No Python implementation source is sent to
V or placed in data strings. Normal calls compile through the existing V tool
installer; `VINIX_VULKAN_VM_QUERY` optionally selects a prepared controller.
Host V uses its normal GC; this stage changes no kernel allocation path.

Each synchronous query retains borrowed inputs and returned library objects
until completion. File/archive managers retain entered values separately;
explicit exit consumes their owner before calling `__exit__`. Failed entry
registers no owner, and fallback context retirement follows controller reap.
Saved exception identity and traceback properties are supplied under an active
exception frame, with deliberate manager traceback mutations preserved.
Python 3.9's active traceback can include an internal replay frame; identical
frame lists are not an interface claim.

The boot operation alone owns its PTY child and master descriptor. It preserves
the original absolute deadline, binary transcript, marker checks, SIGTERM and
five-second kill fallback, and cleanup error precedence. It additionally
retires the original leaked child/descriptor after invalid post-fork timeout
arithmetic and stop failures, without changing the primary error. Emergency
reaping handles the original stopped-but-unreaped kill race, and failed child
exec exits directly. SIGINT is masked only during retirement and enabled again
for screenshot/report work. Nested bridge calls transfer the actual queued
interrupt and restore their predecessor's masking state, preventing a signal
from disappearing inside a nested context. These narrow shared ABI and
lifetime corrections receive zero new algorithm credit.

Qualification is recorded under the machine-local cache
`/Users/alex/.cache/vinix-python-to-v/dota-vulkan-guest-20261009/`.
Frozen original and native implementations passed ARM, x86 and ASan/UBSan
checks for seven public signatures, seventeen helper cases, sixteen prepared
root variants and 104 complete workflows. Controls cover actual file-manager
entry/exit, cleanup suppression, overriding errors, traceback mutation,
nested and retirement interrupts, invalid deadlines and repeated real PTY
ownership. The complete previous kernel-gap and Lavapipe host gates were rerun
against the shared bridge additions. Both host ABIs passed cold mode-0700
installation and four exact argparse controls. Ownership received an
independent peer review. Earlier compiler/setup and fixture-hook failures
remain separate from the final passing evidence.

The frozen and native full runners also passed fresh prepared-input ARM QEMU
work states with the original 600-second deadline, four CPUs and 8 GiB RAM.
Both enumerated translated Lavapipe, rendered 3,000 frames in X11 and captured
an actual XWD/PNG scene above the unchanged eight-color threshold. The scenes
have different cube phases, so pixel/color-count equality is not claimed.
Kernel, translator, ICD and runtime generation hashes match. The retained ARM
kernel hash is
`a921a67817a8b7658fa115cafb569814f458cc96b71eb71eb343cde22bd66a57`.
This is prepared-binary rendering evidence; it is not a fresh kernel build,
a physical GPU test, a Venus result or Dota game execution.
