# Native Dota guest controllers

`env-run`, `lavapipe-run`, `wake-op-run`, `run-mmap32` and `steam-smoke-run`
compile their V mains and call `nativehost` directly. They retire eight Python
entry points and bindings: 26,828 bytes / 615 lines. The shared game, Vulkan,
preparation and package-builder adapters remain for their existing callers.

The controllers retain the guest C/ASM inputs, compiler flags, native child
watchdogs, marker requirements, comparison ordering and host deadlines. Runtime
pins resolve links and record size and SHA-256; a changed pin fails installation.
Environment and Lavapipe verdict numbers preserve Unicode decimal digits and
arbitrary precision in JSON. WAKE_OP retains its explicit translator comparison;
mapping retains the optional original C controls. Steam retains its cached
private clone, target environment, preloads, loader flags and four modes.

Every guest uses the shared native PTY/process owner. Successful and failed
verdicts both retire and reap QEMU. Preparation preserves its compressed archive;
the native ISO producer gets a separate uncompressed boot copy. The original
Python commands were read and frozen by hash; none was modified or executed.

## Qualification

V 0.5.2 (`81be246`), pinned privately, passed 18 cold builds: five commands and
`check-native.v` on ARM, Rosetta x86 and ARM ASan/UBSan. All three profiles passed
the independent host contracts and CLI argument controls. The checks include
read-only replacement, source preservation, symlink retirement, ELF bounds and
architecture rejection, runtime candidate order, 200 pin/copy/error iterations
with a flat descriptor count, independent glibc and Lavapipe serial fixtures,
wrong stores, watchdogs, reordered cases, missing markers and huge JSON integers.

All five complete commands passed controlled serial success and failure cases
on all three profiles. Preparation used the actual guest SDK/compiler and pinned
runtime files. The controlled QEMU child recorded its command and PID; each
case checked the original memory/CPU policy, PCI boot device and child retirement.
All five public shell fronts also passed compilation and `--help`.
An interrupt delivered after the controlled QEMU child started returned status
130 and retired that child on ARM, Rosetta x86 and ASan/UBSan.

Real AArch64 guests used retained runtimes and frozen kernels, without rebuilding
the kernel or changing guest source files. The paired glibc environment test
passed its old SIGSEGV control and all 32 rounds on the fixed runtime. WAKE_OP
passed its old EFAULT/permission controls and all new cases. The translated
mapping test passed both the native V pair and the frozen original C library
and probe comparisons (`c-c`, `c-v`, `v-v`). Steam's actual Valve library passed
the `load` mode and exit-zero markers. This does not establish Steam login,
Steam API initialization in other modes, game execution or rendering.

The first Lavapipe run used kernel
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`.
All fixed-driver modes passed, but three negative controls reported exit 1
despite a translated SIGSEGV diagnostic. The strict verdict correctly rejected
that run. The original fixture's frozen kernel is
`63ed08e26058355f4c0f02e9d1cee06fe1ef82f43b405a9350bbd331b3c28ac0`;
its full rerun passed. Both controls reproduced SIGSEGV in the three null modes,
both ordinary bindings passed, and all four fixed modes stored through set 2.
The failed newer-kernel comparison remains recorded separately. This verifies
compute descriptor binding; it does not establish game rendering.

Private qualification receipts, logs, compiler commands and artifact hashes are
under `~/.cache/vinix-python-zero-process-20261011/dota-*`. Completed large private
images are retired after preserving their hashes and small evidence files.
Initial compressed-tar integration failures remain recorded alongside the
corrected runs. No Python was run during qualification.
