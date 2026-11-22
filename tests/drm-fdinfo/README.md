# DRM fdinfo lines

Run `v run tests/drm-fdinfo/run.v` to check the production formatting from
`kernel/drm/fdinfo.v` under address and undefined-behavior sanitizers.

It checks Linux's `drm_fdinfo_print_size()` units (a KiB or MiB suffix only
while the size divides evenly, never past MiB), the key order of
`drm_print_memory_stats()`, and the exact lines Asahi prints for a G13 client.
`DRM_FDINFO_SOURCE` selects another source for negative controls.

The guest checks open-order IDs by reading fdinfo in reverse. It also
checks dup, fork, descriptor-number reuse, ordinary files and `O_PATH`.

```sh
tests/kernel-gaps/run-native --source tests/drm-fdinfo/guestfixture/core.v \
  --kernel-dir kernel --arch aarch64 --expect 'VINIX DRM CLIENT IDS: PASS'
```

Repeat with `--arch x86_64` after building the x86-64 kernel. For a
cross-compiled ARM64 guest, set `VINIX_AARCH64_SYSROOT` to the musl sysroot.
`tests/procfs-fdinfo` covers generic fdinfo and allocation churn.
`tests/agx-file-close` checks what the AGX driver counts for a client.
