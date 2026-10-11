# Native compatibility tooling

The eight commands below compile V directly. Their generators, compiler
recipes, independent C controls, archive assembly and guest supervision have
no Python runtime dependency.

```sh
build-support/steam/compile-v-robust OUTPUT [--i386] [--host]
tests/steam/test-robust-list [--output-dir FRESH-DIR] [--native]
tests/steam/run-robust-vm --work FRESH-DIR --kernel-dir DIR
build-support/x86-translation/compile-v-office OUTPUT [--cc COMPILER]
tests/office-compat/run [--state-dir FRESH-DIR]
tests/office-compat/run-vm --state-dir FRESH-DIR --kernel-dir DIR --fixtures DIR
tests/net-random/run [--state-dir FRESH-DIR] [--original-reference FILE]
build-support/n64/test-bridge [--build-dir DIR] [--archive FILE] [--rom FILE]
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
