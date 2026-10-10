# Native Apple boot compiler commands

`apple-boot/compile-v OUTPUT [--host]` generates the freestanding loader's C
translation unit directly from V. The host profile renames the six memory and
string exports so sanitizer/libc implementations retain their symbols. The
command rejects integer printf macros before removing the unused inttypes
include. Temporary trees are removed after compilation and on errors.

`apple-boot/tests/compile-fixture converter|boot|helpers OUTPUT [--arch arm64|amd64]`
uses the native module producer. Architecture defaults to that of the host
executable. Both maintained commands use `build-support/run-v-tool.sh` and need
no Python runtime; loader make rules invoke them directly.

```sh
v -cc cc test apple-boot/hostcompiler
make -C apple-boot
python3 apple-boot/tests/run-v-core.py
```

Qualification compared complete generated C bytes with the old Python drivers
for both loader profiles and all three fixtures on both target architectures.
ARM and Rosetta x86 host executables matched, including their architecture
defaults. Compiler-failure and printf-guard cases preserved output/error
behavior and removed private scratch trees. The actual AArch64 loader
cross-build passed, and host checks matched all 78 C/V ABI fields and found no
allocator imports in the loader core.

The remaining Python host test suite reaches an existing strict-build failure:
the current compiler emits undeclared `memdup` calls in the boot fixture. The
original driver produces identical C and fails the same compilation. This
stage does not claim that suite passed or establish a new guest boot.
