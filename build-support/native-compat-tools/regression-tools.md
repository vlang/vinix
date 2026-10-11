# Native regression, protection and loader tooling

Eight former Python entry points now invoke V directly. The ELF host shell
entry also delegates its production extraction and test assembly to V:

```sh
tests/kernel-cpu/run [--repo DIR] [--kernel DIR] [--timeout SECONDS] [--smp N] [--log FILE]
tests/kernel-job-control/run [--fork-only] [--cycles-only] [--teardown-only] [--detached-churn]
tests/kernel-sysvmsg/run [--repo DIR] [--kernel DIR] [--timeout SECONDS] [--smp N] [--log FILE]
tests/kernel-retention/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR --guest-state-dir PREFIX [--build-only]
tests/stack-protector/run [--state-dir FRESH-DIR]
tests/elf-text/run --arch aarch64|x86_64 --kernel-dir DIR [--state-dir DIR] [--source C] [--build-only]
tests/elf-text/run-host.sh [--state-dir FRESH-DIR]
tests/userland-demo/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR [--build-only]
tests/uname/run [--sysroot DIR] [--timeout SECONDS] [--kernel-dir DIR] [--state-dir FRESH-DIR] [--build-only]
```

CPU, job-control and SysV retain their exact strict ARM Alpine linker recipes,
four CPUs, 2048 MiB, default 180-second budgets and unchanged C probes. Their
optional `--state-dir` and `--build-only` retain reviewable inputs/executables.
Job-control retains all four independent boolean defines. The native supervisor
keeps fractional deadlines and stops on DONE, panic or fatal output. It sends
TERM to the process group, waits up to ten seconds, then kills and reaps it.
The first `DONE failures=` capture must be the literal `0`, and a late CHECK
failure still fails. Their original final predicate ignores the child's exit
status and does not independently reject panic text after a valid completion.
Selected serial lines and the caller's live full log remain, including after
interrupts. The log descriptor is closed on every exit and cannot pass through
exec to the child. The original base
shell archive is retained; only its init is replaced. Networking is disabled
for these isolated regression guests. Invalid deadlines must be finite and
positive; invalid CPU counts are rejected before launch.

Retention keeps its immutable C revision, exact original compiler flags,
allocator guard, two separate programs and 180-second outer budgets. It
requires two cohorts of 18 ARM or 14 x86 class rows, zero retained objects and
bytes, and two zero large-page rows, then compares the raw C/V rows. Arbitrary
width counters are tested without narrowing. The two `Heap` records now lend
their stack addresses to synchronous snapshot reads. No reader stores either
address, and both records outlive their measurements and comparisons. Generated
C confirms stack values with no `memdup`; the object has no allocator imports.
The workload, diagnostics and numerical predicates remain unchanged.

Stack protection still generates the genuine production guard with its entropy
and panic adapters, links independent protected V frames, rejects allocation
imports and verifies the exact LLVM function attribute groups. Initialization,
main and ABI wrappers remain unprotected; the volatile frame is protected and
non-inlined. Both 1,000 normal initialization/return cycles and the child panic
ABI are exercised. Compiler, architecture and warning flags remain selectable
through the original environment variables.

ELF host checks extract the same production constants, structures and functions
and retain the original resource/range/lock fixture bodies and both native test
suites. The guest keeps both real textrel encodings, an actual dynamic PIE,
the selected genuine loader, relative libc link and strict user-access command
line. ARM still links the real shared loader explicitly rather than accepting
a static PIE. Both success markers, three failure markers and the 240-second
budget remain. Default ELF evidence directories remain available, as before.

Greeting tests rename only the three maintained V module/entry names. Their
bodies run against the same exact host stdout golden under ASan/UBSan and link
into both static native targets. Uname stages the unchanged command over an
absolute BusyBox symlink, checks that BusyBox bytes stay intact and the relative
usr/bin link resolves correctly, then boots the same shell assertions. It keeps
512 MiB, the 120-second budget and three failure markers. Other explicit test
directories must be fresh; default private directories retire on all exits.

`check-regression-build.v CONTROLLER PROFILE CACHE` independently checks ten
native target builds, immutable C bytes, ELF machine IDs, real PIE dynamic and
interpreter headers, exact host greetings and byte-identical recipe replays.
`V`, `VINIX_PROCESS_TEST_ARM_KERNEL` and `VINIX_PROCESS_TEST_X86_KERNEL` select
qualification inputs. `regression_test.v` covers original completion captures,
large/negative counters and LLVM protection rules. `check-regression.v` covers
fractional deadlines, incomplete/late output, nonzero child exits, TERM/KILL
escalation, live/interrupted log retention, thirty FD/PID retirement cycles and
all public CLI errors.
`check-regression-fronts.v` checks all eight fronts outside the checkout.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan controllers pass all ten target builds,
native units, stack-protector host checks and supervisor resource checks.
Both ELF host suites pass on ARM and x86. macOS ASan uses `detect_leaks=0`;
no LeakSanitizer claim is made. Evidence is retained under
`/Users/alex/.cache/vinix-python-zero-process-20261011`.

Real ARM guests pass the independent C/V retention pair with identical rows,
fork-only job-control on the genuine base shell image, ELF text/PIE/interpreter
checks and uname. Production greetings pass on both architectures. Kernel
SHA-256 values remain the prepared ARM
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`
and x86 `38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`.
The x86 ELF guest fails the unchanged text-protection assertion at line 27 with
errno zero for both immutable original C and V probes. The x86 retention C
control also reports existing retained allocations and fails its final check;
its paired controller stops before the V run, preserving the original order.
The independently booted V retention probe also fails its unchanged final
check. Both report 2 retained 48-byte objects during directory enumeration and
2,802 during procfs reads; their successful ARM pair remains flat.
No marker or retention predicate is weakened. New kernel builds, hardware,
full job-control, CPU timer and SysV guest qualifications are not claimed.
No Python executes and no language attributes change.
