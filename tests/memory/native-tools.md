# Native memory test controllers

`run-runtime`, its existing `run-runtime.sh` caller, and `test-big-io` invoke
maintained V commands. `memorytools` retains the existing independent V oracle
and syscall-model fixtures without changing their bodies. The two retired
Python sources are frozen by Git blob and SHA-256 in
[the translation receipt](native-translation.json). Original C oracles are
read from their pre-port commits as immutable data; Python is never executed.

The runtime build copies the production V memory primitives under private
export names and retains freestanding, aliasing and general-register-only
compiler flags. The unused Darwin x86 math header remains excluded solely to
keep the SDK's floating-point inline functions out of that translation unit.
Generated fixtures retain their two warning exceptions and PIC flag; original
C inputs keep their complete warning policy. Both object families reject
allocator imports before linking. Source, generated artifact, executable and
import receipts remain in each state directory.

Host runs preserve their 180-second runtime and 60-second per-fault bounds,
complete C/V status/stdout/stderr comparisons, every memory oracle domain and
all 22 literal large-I/O fault cases. Success requires the original measurement
counts; each injected fault must produce its original failure verdict. ASan and
UBSan remain enabled by default. Darwin's ASan rejects `detect_leaks=1` before
executing the oracle, so the native controller disables that unsupported option
on macOS; Linux keeps it enabled. The allocator-import guard still applies on
both platforms.

Guest builds preserve the serial constructor, static linking, PID 1 keep-alive,
architecture/compiler selection, no-network policy, verdicts and 3,600/240-second
allowances. They use the already native guest supervisor. `--build-only` adds a
way to qualify target artifacts without a kernel boot. Existing state directories
are rejected, including an explicitly empty state path, which denotes the
current directory. Temporary host work is removed and requested state retained.
Compiler subprocess groups are owned until descendant retirement and one reap.
An optional supervisor cancellation callback makes SIGTERM observable during
the active guest loop while preserving existing callers' default behavior.

Combining the cache signal scope with the guest module exposed a V compiler
name-resolution collision: `voidptr(interrupted)` selected the guest's integer
flag instead of the cache module's function. The uniquely named
`cachecli_signal_received` resolves to the actual callback. Qualification checks
the emitted SDK signal bindings and exercises real SIGINT/SIGTERM delivery.

Qualification runs nine initial and twelve final cold builds on ARM, Rosetta
x86 and ARM ASan/UBSan. Full C/V memory comparisons pass with 410,739 cases on
ARM's 16 KiB pages and 226,419 on x86's 4 KiB pages. All 22 large-I/O fault cases
pass on each profile. Final compiler/guest interrupt tests retire all descendants
and return 130/143, and existing-state/empty-path CLI checks pass. Cache units
and the unchanged guest-supervisor regression pass on every profile; two public
fronts compile cold and caller syntax is checked. Eight static AArch64/x86-64
C/V target executables pass machine, allocator-import and absent-interpreter
checks. This stage makes no fresh kernel, QEMU guest or hardware boot claim.

Run the owner/CLI fixture with `tests/memory/test-memory-tools NEW_STATE`, setting
`VINIX_MEMORY_TEST_C_BIGIO` to the immutable original `big_io_guest.c` input.
