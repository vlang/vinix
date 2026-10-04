# Dota 2 compatibility tests

`env-run.py` checks the private glibc runtime's concurrent environment access
through Vinix's native AArch64 QEMU translator. It adapts GNU libc's
[`tst-getenv-thread.c`](https://github.com/bminor/glibc/blob/glibc-2.41/stdlib/tst-getenv-thread.c):
two readers repeatedly check a constant variable and a missing variable while
one writer adds 1,000 fixed test names. There are 32 finite rounds, a 90-second
test deadline, a 110-second native child watchdog and a 240-second host timeout.
No inherited environment values are printed.

Supply an unfixed glibc root and a root containing the upstream fix (glibc 2.41).
Each root must contain its libc and matching loader. The runner copies those
two files only, resolves symlinks, and records their sizes and SHA-256 hashes.
Both links must produce the same test ELF. Both processes use the same kernel,
translator and 2 GiB/four-CPU guest, with no compatibility preloads. The negative
control must terminate with its original SIGSEGV; the fixed runtime must finish
every round and exit successfully.

```sh
python3 tests/dota2/env-run.py \
  --old-glibc-root=/path/to/bookworm-runtime \
  --new-glibc-root=/path/to/fixed-glibc-root \
  --kernel-dir=/path/to/built-aarch64-kernel \
  --translator=build/dota2-qemu/staging/usr/bin/qemu-x86_64 \
  --work=build/dota2-env-test/fresh-run
```

Add `--prepare-only` to build and inspect the fixture without starting QEMU.
`--native-cc` selects the AArch64 compiler; it defaults to the cross-compiler
wrapper prepared in `build/dota2-qemu/aarch64-cc`. Every run requires a fresh
work directory and writes `provenance.json`. A booted run also writes
`results.json` and `serial.log`.
A pair which passes on both runtimes fails this regression because the
negative control did not reproduce the defect. This test verifies libc
compatibility; it does not establish Dota's environment writer or gameplay.

`lavapipe-run.py` checks Lavapipe's compute descriptor-set binding, which Dota
reached while loading a local map. With `VK_EXT_graphics_pipeline_library`
enabled, a program may bind `VK_NULL_HANDLE` sets and its independent-set
pipeline layouts may omit set layouts. `lavapipe-null-sets.c` binds storage
buffers in sets 0 and 2 around set 1 and dispatches a hand-assembled SPIR-V
shader that stores a marker through set 2. Its four modes bind every set,
bind a null set 1, omit set 1's layout, and bind set 2 in a later call past
the omitted layout. The marker must reach set 2's buffer and nothing else.

Every driver runs the same probe, Vulkan loader, glibc, translator and kernel
in one boot. Each `--control` must pass the ordinary binding and terminate with
`SIGSEGV` in the three null modes; the `--fixed` driver must pass all four.

```sh
python3 tests/dota2/lavapipe-run.py \
  --fixed build/dota2-runtime/mesa/out/libvulkan_lvp.so \
  --control /path/to/debian/libvulkan_lvp.so \
  --kernel-dir=/path/to/built-aarch64-kernel \
  --work build/dota2-lavapipe-test/fresh-run
```

`--runtime-root` selects the private runtime that supplies glibc, the Vulkan
loader and the drivers' libraries, and `--vulkan-include` the headers from the
prepared Mesa source. Repeat `--control` to compare several unfixed drivers,
such as Debian's binary and an unpatched build from the same source.
