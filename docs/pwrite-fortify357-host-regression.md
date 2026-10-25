# Fortified positional writes: host and ARM64 proof

Maps356's retained `libAppDataSearch.so` imports `__pwrite_chk@LIBC_N`; its private loader lacks the corresponding `bionic___pwrite_chk` export. That run remains `startup_failed`. The translation linker searches the `bionic_` namespace, so the fix belongs in `build-support/android/wsloader/fortify.v`, which generates the loader linked as `usr/lib/art/native-ws/libdl_bio.so.0`.

The two wrappers provide `__pwrite_chk` and its `__pwrite64_chk` companion with the ARM64 LP64 ABI. They abort for counts above `SSIZE_MAX` or source capacity and otherwise return the host `pwrite` result directly. The contract was checked against official AOSP bionic revision `a1bc57f84cf3d05ec20a25e0126ecdcc4847fa5b`: [fortify.cpp](https://android.googlesource.com/platform/bionic/+/a1bc57f84cf3d05ec20a25e0126ecdcc4847fa5b/libc/bionic/fortify.cpp), [bionic_fortify.h](https://android.googlesource.com/platform/bionic/+/a1bc57f84cf3d05ec20a25e0126ecdcc4847fa5b/libc/private/bionic_fortify.h).

Validation completed with exit 0:

- Existing and final host tests; an independent fresh host build/run also passed. Cases cover both aliases, capacity boundaries, zero/null, unchanged file position, offsets above 4 GiB, forwarded errno, and observed `SIGABRT` without returning after invalid counts.
- Production ARM64 loader C generation and object compilation; symbol inspection proves both global wrapper functions and the unresolved host `pwrite` import.
- V generation of the complete assetprobe succeeded. Its exact libc fixture compiled separately to an ARM64 object retaining raw pread/pwrite imports; this is compile/import proof, not full assetprobe or guest execution. The full object attempt required its separately generated TLS header.
- `tests/native-android-ws/pwrite-fortify-host-proof.v` checked official source, frozen inputs, loader symbols and raw fixture imports, then sealed 61 files.

Evidence is external at `/Users/alex/.local/state/vinix/android/pwrite-fortify357-host-2026-10-26`; `sha256.json` is `ac847e5693bcbe02563c753086555f623d68206cf4689d3cf28bb7555e989bfe`. It retains source, commands, logs, earlier failed attempts, generated artifacts and downloaded official sources. Source baseline is `a8721ba11b691df980eb7a96309f7351efc6f550`. The unchanged `tests/linuxkpi/generate_module.v` was compared with that revision and frozen with SHA256 `3a6a4402a3cd68f3a4acc2db6563e78b8191d41fd85a9b9c78882073c1b81a67`. Root independently read all 61 files using `build-bundle-check290` (exit 0); adjacent receipt: `pwrite-fortify357-root-readback-2026-10-26.json`.

Key SHA256 pins:

| Artifact | SHA256 |
| --- | --- |
| Official fortify.cpp | `2205c94ceb0128d8d1b594c0eef0759010960ceb64fee53ff408e3dd2e29141b` |
| Official bionic_fortify.h | `57b5ff8810c0e0deacc6d50e17c7c64a6557420f75ab8039eb7fcf9b3644b1eb` |
| Generated android-loader.c | `c2b68385b0b262dc1992d36308ad731b5ac659217443cf4a0c694106ffcb441d` |
| ARM64 android-loader.o | `47bd104a9021f7e55884af1ec45b68e02d343c2779831af1b3c5388a6aa54157` |
| ARM64 libc-probe.o | `3d2d5ac042895bc9766eea5cbaa051e53e76b8a82414a6405361bb3a05d270f1` |

The other fortified imports are covered by the existing pread wrapper and pinned bionic_translation source (`ee37eb21c91409fe0eed833d0a5a0aa6b931bb7b`). An available base libc exports them, but its checksum was not qualified against Maps356's retained boot base. No full native rebuild or Maps replay used this fix; frozen Native351 and framework353 inputs were unchanged. Successful loading of this background library still requires a replay with the rebuilt loader.
