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
apple-boot/tests/run-v-core
```

Qualification compared complete generated C bytes with the old Python drivers
for both loader profiles and all three fixtures on both target architectures.
ARM and Rosetta x86 host executables matched, including their architecture
defaults. Compiler-failure and printf-guard cases preserved output/error
behavior and removed private scratch trees. The actual AArch64 loader
cross-build passed, and host checks matched all 78 C/V ABI fields and found no
allocator imports in the loader core.

The original compiler stage encountered undeclared `memdup` calls in three
large boot-fixture records. The native host-tool stage gives this one-shot
fixture explicit static storage, keeps every assertion and verifies the
results against the frozen C goldens. See [native host-tool qualification](../native-tools.md).
