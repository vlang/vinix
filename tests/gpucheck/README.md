# gpucheck in QEMU

```sh
VINIX_AARCH64_SYSROOT=... tests/gpucheck/run --kernel-dir KERNEL \
    --root STAGED_ROOT --state NEW_DIR [--timeout SECONDS]
```

`tools/gpucheck` collects the M1 GPU's acceptance evidence from one boot
(see `docs/m1-agx-bringup.md`). It cannot pass without an Apple GPU. This test
checks that in QEMU, which has none, it runs every step and reports each
thing that is missing.

The runner builds `gpucheck` with `tools/gpucheck/build.v` into the initramfs
beside `guest.c`. It attaches `STAGED_ROOT`, Omarchy's Mesa root as
`tests/omarchy-mesa/stage.v` stages it, as a read-only ext2 disk. The init
mounts the disk and runs `gpucheck --root` on it, then checks the report in
`/root`. The report must give exit status 1 and name these problems:

- the GPU driver is missing from the boot log;
- there is no asahi render node;
- the triangle smoke test is not installed;
- Honeykrisp finds no Apple GPU;
- EGL renders on llvmpipe;
- `peglgears` draws frames but holds no asahi memory in its fdinfo.

It must also make all five mounts in the root and undo them afterwards.

`GPUCHECK_SOURCE` builds another `gpucheck.v`, for negative controls. One that
never unmounts, and one that does not flag llvmpipe, each fail one check.
