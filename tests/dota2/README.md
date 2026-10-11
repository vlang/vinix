# Dota 2 compatibility tests

The native V `export-test` checks sparse ext2 layout and the loopback NBD
protocol with e2fsprogs and QEMU. `export-run --source DIR --state-dir DIR`
compiles the unchanged ARM payload and compares package byte ranges through
guest `pread` and `mmap`, including direct and indirect boundaries. These
commands use `tools/dota2/ext2host` directly.

`env-run` checks the private glibc runtime's concurrent environment access
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
tests/dota2/env-run \
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

`lavapipe-run` checks Lavapipe's compute descriptor-set binding, which Dota
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
tests/dota2/lavapipe-run \
  --fixed build/dota2-runtime/mesa/out/libvulkan_lvp.so \
  --control /path/to/debian/libvulkan_lvp.so \
  --kernel-dir=/path/to/built-aarch64-kernel \
  --work build/dota2-lavapipe-test/fresh-run
```

`--runtime-root` selects the private runtime that supplies glibc, the Vulkan
loader and the drivers' libraries, and `--vulkan-include` the headers from the
prepared Mesa source. Repeat `--control` to compare several unfixed drivers,
such as Debian's binary and an unpatched build from the same source.

`wake-op-run`, `run-mmap32` and `steam-smoke-run` also run native V directly.
Their controllers share `nativehost`, typed immutable file pins and the native
PTY/process owner. WAKE_OP still compares explicit translators and requires
`VINIX_PRUNE_BUILD=0`; preparation is the default and `--run` starts the guest.
The mapping command retains optional original C library/probe controls. Steam
retains its modes, repeatable target environment/preloads and loader options.
Both mapping and Steam accept `--prepare-only` for inspecting a private fixture.
The compressed evidence archive is retained; the ISO builder receives a separate
uncompressed boot copy. See [native qualification](native-controller.md).

`run` prepares and captures the real game through native V. `run-test` checks
its staging, read diagnostics, capture policy and process owners. The runner
retains `--prepare-only`, repeatable target environment/preloads/arguments,
optional translator staging, memory and capture timing controls. It reports
exit 1 for an observed startup failure and exit 2 for a capture awaiting review;
it leaves `rendering_verified` false. `--venus` needs the prepared host renderer
and KekVM bottle, patches a private QEMU through native `qemuhost` and owns a
stock-QEMU network bridge when the GPU bottle lacks slirp.

The native screenshot command preserves PNG/PPM output without Pillow;
ImageMagick supplies additional formats. See [game capture qualification](native-game.md).
