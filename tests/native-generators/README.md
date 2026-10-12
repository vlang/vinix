# Native fixture and benchmark generators

The public commands compile and run V directly:

| Command | Producer |
| --- | --- |
| `build-support/compile-v-module` | `hosttest.generate_module`, exported ABI header and scalar metadata APIs |
| `build-support/security-tools/compile-v-core` | `compathost`, security module staging and native ABI assertions |
| `build-support/xorg-server/compile-v-host` | `compathost`, Wine/XInput staging |
| `tests/kernel-gaps/compile-v-fixture` | `generators`, serial or selected Linux ABI module |
| `tests/linuxkpi/compile-v-core` | `generators`, production compatibility core with host export aliases |
| `tests/linuxkpi/compile-v-host` | `hostfixturebuild`, independent host fixture staging |
| `tests/alloc-bench/compile-v-bench` | `generators`, benchmark, ABI header and source/compiler manifest |
| `tests/alloc-bench/compile-v-sampler` | `generators`, freestanding sampler and optional exported ABI header |
| `tests/alloc-bench/compile-v-kmod-info` | `generators`, compiler-derived static kmod descriptor |
| `tests/alloc-bench/test-kmod-info` | `generators`, independent C/V Mach-O data comparison |

`generators.compile_fixture` provides the original object compiler API. It
filters linker options before adding the two generated-code warning exceptions,
PIC and the source include directory. Sampler ARM generation requires the
fixture clock at the command line. An omitted compatibility-core architecture
retains the compiler's default; explicit invalid or empty architectures fail.

The kmod producer accepts one compiler aggregate initializer and two literal
64-byte array copies. It rejects remaining constructor work or runtime calls.
The object check reads data without executing it and bounds every load command,
section, symbol, string and relocation range. It compares all 196 bytes,
four-byte alignment, external symbols and both callback relocations on x86-64
and ARM64, and rejects nonempty executable or constructor sections.

Commands own compiler process groups, preserve separate compiler output streams,
and retire the leader and descendants before removing private project trees.
SIGINT and SIGTERM return 130 and 143. Compiler stdout is bounded at 64 MiB;
the shared command owner retains up to 64 KiB of stderr. Existing destination
files and the original source-copy/compiler policies remain the producer's
responsibility. The metadata check requires a new state directory.

Run the host qualification with an immutable pre-port C descriptor:

```sh
build-support/run-v-tool.sh tests/native-generators/test-generators.v \
  /path/to/new/state /path/to/immutable/macos-kext-info.c arm64 plain
build-support/run-v-tool.sh tests/native-generators/test-generators.v \
  --failures /path/to/new/failure-state /path/to/immutable/macos-kext-info.c
```

Qualification freezes ten original Python files (25,780 bytes / 531 lines) at
`edde5b8d` and records their Git blobs and SHA-256 hashes in
`native-translation.json`. The immutable C descriptor is recovered from
`ad0ba5d0^:tests/alloc-bench/macos-kext-info.c` as data. Python is never run.

Twelve qualified cold builds pass on ARM, Rosetta x86 and ARM ASan/UBSan.
They cover strict benchmark compilation and all six quick workloads, source and
header manifests, serial object compilation with linker arguments filtered,
compatibility-core aliases, exported sampler headers and allocator import
guards. The independent sampler retains its success, three-phase OOM and
zeroing rollback, invalid clock and kext callback assertions. Complete kmod
data comparisons, malformed metadata/object guards, CLI failures, protected
state and ten interrupt/descendant retirement cases pass per profile. Final
compiler failures preserve both output streams and remove temporary projects
for all five generators and the native object checker.

All ten public fronts pass cold help builds and shell syntax checks. Thirteen
complete public generator workflows pass, including default compatibility
architecture, independent host staging, all three security cores, Wine fixture
mode and XInput. This adds 23 public cold builds. The private originals,
qualification V helpers and logs are retained at
`~/.cache/vinix-generators-native-20261012`.

This stage qualifies the generator commands and APIs. Remaining benchmark and
LinuxKPI controllers are still being migrated. No new kernel, guest boot,
Darwin GCC benchmark campaign or kext execution is claimed.
