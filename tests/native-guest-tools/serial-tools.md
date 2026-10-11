# Native serial and instruction-budget tools

This stage removes six Python files: **18,962 original bytes / 334 lines**.
`compile-init`, `tests/init-policy/compile-guest`, `tests/init-policy/run-vm`,
`tests/process-churn/run`, `tests/memlock/run-vm` and `tests/n64/rsp-budget`
compile and invoke V. The memlock and realtime shell drivers invoke their native
controllers. No Python, Python bridge or package server runs in these paths.

The original realtime import API remains while its remaining callers migrate;
its source receives no removal credit in this stage. Emulator build controllers
and their Python builders remain separate pending work.

## Contracts

The standalone init producer retains the complete source copy, four host export
renames, original freestanding V flags, policy/Wi-Fi/echo defines, Unicode PRI
guard, include removal and exact ARM signal/time layout assertions. The guest
producer retains its three mode defines and both target architectures.

The init guest command builds shell/full/desktop in that order with the original
freestanding and musl flags. Both maintained V and optional original C programs
keep their original installation paths, markers, 600-second per-policy default
and failure checks. Archive construction now uses the already-qualified native
USTAR command with macOS metadata disabled. `--build-only` retains the builds.

Churn retains all seven modes, 300-operation cohorts (200 for directories),
its exact third-cohort markers and 1800-second default. Exec requires the
prepared desktop archive/module ISO and 12 GiB ARM memory; directories require
ARM and the physical ext2 home. Other ARM modes use 2 GiB. The original x86
security transport uses 1 GiB regardless of its unused mutable memory constant;
that command policy is retained. `--state-dir` retains a fresh run, and
`--build-only` requires it. Allocator measurements require a tracked kernel.

Memlock retains all seven feature markers and the final pass, exactly once,
with the security runner's two-second settling policy on both architectures.
Realtime retains all ten features, the final pass, immediate monitor exit,
ten-second exit grace and natural zero-status requirement. New standalone
controllers use prepared kernels; they do not rebuild the shared checkout.

ARM base images and replacement PID 1 remain separate Limine modules. Private
ISO configuration retains external module-CD order and the ext2 command line;
existing ext2 disks and EFI variables survive reuse. Guest execution changes
only the child working directory. Parent cwd and literal Unix path bytes are
preserved. Typed CLI errors do not mistake a filesystem ENOENT for bad syntax.

RSP recompiles the stamped core source/flags, renames its logging symbol,
resolves its relative includes and links the independent V budget fixture.
Its default remains three seconds for sixteen instructions. Fractional
deadlines, merged binary output, nonzero status and the completion marker are
checked. Native CLI deadlines must be finite and positive.

Compiler and wrapper commands have scoped SIGINT/SIGPIPE handlers and private
process groups. Cancellation kills/reaps the command and retires descendants;
nested commands retain pending interrupts between build steps. Captured build
diagnostics retain stdout/stderr bytes and are replayed when the step ends.
Existing unscoped, two-stream and integer-deadline capture APIs retain their
direct-child behavior and timeout messages.

## Qualification (2026-10-11)

- Eight fresh command builds pass on ARM, Rosetta x86 and ASan/UBSan.
- All 24 original init option combinations produce byte-identical C on each
  profile; all three syscall-recorder host policy runs pass.
- Eleven supported churn SDK builds per profile pass, and six strict init
  fixture SDK objects and ELF links pass on ARM and genuine x86 musl GCC.
- The actual patched RSP passes under all controller profiles. Separate
  native ARM and x86 core/fixture/executable Mach-O headers are checked; both
  instruction-budget runs pass. The original prepared host stamp is preserved.
- Merged invalid/binary bytes, full pipes, fractional EOF timeouts, twenty
  FD/PID cycles per profile, descendant retirement, nested SIGINT, actual
  producer/churn/RSP cancellation and default scratch cleanup pass.
- CLI guards, seven cold native fronts from `/tmp`, child cwd and failed
  chdir checks pass. The 12 GiB module-CD recipe and unchanged disk/EFI bytes
  on state reuse pass; a populated exec cohort is not claimed.
- All three actual ARM init policy guests pass for both maintained V and
  original C applications. ARM memlock passes all seven groups.

Guest failures remain failures. The prepared ARM pipe guest completes all
three 300-operation cohorts and then reports `FAIL failures=4`; its untracked
kernel has no allocation-tracking interfaces. The older x86 kernel fails the
unchanged memlock assertions. The ARM realtime guest fails its first scheduler
check, and the native controller rejects it. No workload, threshold, allocator
allowance or kernel source was changed to obtain a pass. ASan leak detection
is disabled on macOS; these results do not claim LeakSanitizer or hardware
qualification.

Prepared kernel SHA-256 values remain:

- ARM: `8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`
- x86: `38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`

Receipts, frozen original Python bytes (read only), native comparison helpers,
prepared host/core stamps, SDK artifacts and `serial-*.log` are under
`~/.cache/vinix-python-zero-process-20261011/`. Short guest states are recorded
in the logs under `/tmp/vinix-ip-*`, `/tmp/vinix-pc-*` and
`/tmp/vinix-module-recipe-*`. No Python was executed for this stage.
