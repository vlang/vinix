# Native compatibility tooling

The commands below compile V directly. Their generators, compiler
recipes, independent C controls, archive assembly and guest supervision have
no Python runtime dependency.

The [process and inspection guest commands](process-guests.md) also provide
native SMP, scheduler, TLB, memory-retention, listen-backlog, resource/procfs
comparisons and genuine dynamic-musl ARM signal-return workflows.

The [regression, protection and loader commands](regression-tools.md) cover
CPU/job/SysV completion policies, directory/procfs retention, stack canaries,
genuine ELF interpreters, production greetings and uname staging.

The [opt-in kernel commands](optin-tools.md) also provide native guarded-stack,
CPU mitigation, SMT topology and isolated-worktree ACPI workflows.

The [resource-group and speculation commands](policy-guests.md) provide native
encrypted-swap staging and the independent 6,144-case production policy oracle.

The [filesystem commands](filesystem-tools.md) provide native resource
accounting, read-ahead and sparse-file power-cut/restart workflows.

```sh
build-support/steam/compile-v-robust OUTPUT [--i386] [--host]
tests/steam/test-robust-list [--output-dir FRESH-DIR] [--native]
tests/steam/run-robust-vm --work FRESH-DIR --kernel-dir DIR
build-support/x86-translation/compile-v-office OUTPUT [--cc COMPILER]
tests/office-compat/run [--state-dir FRESH-DIR]
tests/office-compat/run-vm --state-dir FRESH-DIR --kernel-dir DIR --fixtures DIR
tests/net-random/run [--state-dir FRESH-DIR] [--original-reference FILE]
build-support/n64/test-bridge [--build-dir DIR] [--archive FILE] [--rom FILE]
build-support/security-tools/compile-v-core {mac|sandbox|audit} OUTPUT [--arch arm64|amd64] [-d DEFINE]
build-support/security-tools/stage --arch aarch64|x86_64 --staging DIR [--cc COMPILER]
build-support/storage-tools/stage --arch aarch64|x86_64 --staging DIR [--cc COMPILER]
build-support/xorg-server/compile-v-host {winehost|xinputcore} OUTPUT [--arch arm64|amd64] [--no-main]
tests/storage-volumes/host
tests/storage-volumes/run [--arch aarch64|amd64] [--state-dir FRESH-DIR]
tests/x11-input/run [--baseline ORIGINAL-C] [--state-dir FRESH-DIR]
tests/x11-input/run-vm --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR
tests/wine-host/run-vm --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR
tests/security-mac/host-run.sh [--source ORIGINAL-C] [--keep-dir FRESH-DIR]
tests/application-sandbox/test-host.sh [--source ORIGINAL-C] [--keep-dir FRESH-DIR]
tests/security-audit/collector-run.sh [--source ORIGINAL-C] [--keep-dir FRESH-DIR]
```

Steam retains the original diagnostic declarations derived from its V imports,
pointer/layout assertions, syscall remaps, immutable C revision and sanitizer
comparisons of both output streams. `--native` links the actual libc-free
i386 and x86_64 executables. Office retains the host goldens, all 33 sorted
Windows64 exports, actual SDK type/calling-convention checks and both PE fixture
executables; `validation.json` records their hashes and exit-73 contract.

The randomness runner retains its production source hashes, independent C
oracle option, allocator-import guard, 180-second host deadline and
3,600-second guest budget. Its original sanitizer setting requested
LeakSanitizer on macOS, where Apple's runtime rejects that option. The native
runner enables ASan/UBSan there with `detect_leaks=0`, while supported hosts
retain `detect_leaks=1`. `VINIX_NET_RANDOM_ASAN_OPTIONS` overrides this setting.
This qualification makes no LeakSanitizer claim on macOS.

Explicit test workspaces must be fresh and remain available after a failure.
Default temporary workspaces are retired on success and failure. Steam and
Office guest commands add `--build-only`; randomness adds it for `--arch`
builds. Runtime file copies follow source links and preserve permissions and
timestamps. Steam accepts `--native-root` and `--translator-root`; Office uses
the existing staged Wine runtime and gathers its ELF dependencies transitively.

Steam and Office snapshot the requested ARM kernel and create an uncompressed
ustar archive for the existing pinned ISO builder. They directly own QEMU,
its private variables image and QMP socket through the
[qualified native supervisor](../../tests/native-guest-tools/README.md).
Both retain 1,024 MB, two CPUs, disabled networking, original init scripts,
failure markers and timeout defaults. Receipts record kernel, archive, runtime
file and ISO hashes, launch arguments and guest verdicts. The kernel is never
rebuilt by these commands. The N64 corresponding-source bundle carries the
native fronts, module producer and transitive helper/embedded-fixture sources,
preserving their relative symlinks. Desktop cache keys include the new Office
producer and its dependencies.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan controller builds pass both Steam host
differentials, actual i386/x86_64 links, Office sanitizer goldens and all 33
exports, and the randomness C/V sanitizer differential. Real ARM QEMU boots
pass all four original/V Steam executables and both Office Windows64 fixtures
through Wine. Real ARM and x86 randomness guests pass. The N64 bridge passes
on ARM and the sanitizer controller with the existing ARM host archive and
local homebrew ROM, including callback/variadic boundaries, replacement,
frames, save, reset and cleanup. No x86 N64 archive or new kernel build is
claimed.

`check-tooling.v CONTROLLER` checks declaration/ABI parsing, binary runtime
stat copying, public CLI failures, preservation of existing workspaces and
12 failed-build temporary-owner retirements. Run resource checks separately
for each controller because they inspect shared `/tmp` prefixes. Cold fronts
are checked outside the checkout; the corresponding-source N64 front is also
qualified from a copied source tree. Local evidence is under
`/tmp/vinix-compat-*`. No Python was executed, fixture predicate weakened or
language classification override added.

Security and volume staging retain compiler precedence, target checks, strict
static builds and ABI assertions. Both atomically publish executable files in
the destination directory and retire failed temporary owners. The existing
`storage-tools/stage.v` entry delegates to this implementation, including its
health record size/offset checks. Security staging retains the supervised
collector and mode-700 audit log directory, rejecting a final directory symlink.
The older Python generator import interfaces remain for callers awaiting ports.

All three security host commands retain the independent V fixtures, optional
unchanged C controls, original ASan/UBSan flags, MAC variadic assembly, audit
allocator guard and non-root denial. Commands, inputs and separate output
streams remain available in retained evidence directories. X11 keeps its six
frozen SHA-256 traces, separate C/V stream comparisons, FNV guest goldens and
allocator-import rejection. Its raw keyboard settings now explicitly borrow
stack storage for `tcsetattr`, avoiding an implicit `memdup` emitted by the
current V compiler. Wine's guest entry is V; the original protocol fixture
remains unchanged. Both X11 suites build and pass in actual ARM and x86 guests.

The volume host keeps the original fifteen V templates and unchanged volume
assertions, adding the production health dependency and independent health
access/fault checks. Its guest keeps the original C fixture, sparse 16 MiB
disk, partition layout, physical sentinels and complete-line verdict regex.
It kills QEMU directly with SIGKILL before disk inspection. The real ARM guest
passes all retention classes and physical sentinels. The prepared x86 kernel
rejects the unchanged status ioctl with ENOTTY; its guest executable matches
the original compiler recipe byte for byte. No assertion is relaxed.

`check-security.v CONTROLLER PROFILE` retrieves immutable original fixtures
with their relative header trees, compares both sanitizer output streams and
checks every receipt input hash. `check-stage.v CONTROLLER` verifies twelve
CLIs, invalid compilers/staging paths, workspace preservation and twelve failed
stage-owner retirements. Run resource checks separately. `stage_test.v` checks
atomic replacement/failure cleanup and actual disk bytes. `check-volume.v`
checks partial/malformed verdicts, raw large/binary PTY output, power cuts,
SIGINT, deadlines and 100 FD/PID retirements on each host profile.

Fresh ARM, x86 and sanitizer controllers pass those host checks. Security and
volume staging build both musl targets from committed production sources at
`5e431bdcdfbfd46564a90841fcd401b473a87cad`. Concurrent volume CLI edits caused
strict compiler errors during qualification; those edits were left untouched,
and the successful builds use a copied source tree with a source-hash receipt.
Evidence is under `/tmp/vinix-stage-clean-*`, `/tmp/vinix-security-*`,
`/tmp/vinix-volume-*`, `/tmp/vinix-xinput-*` and `/tmp/vinix-wine-*`.
