# DRM fdinfo lines

Run `v run tests/drm-fdinfo/run.v`. The runner compiles the production
formatting and client numbering from `kernel/drm/fdinfo.v` into a host module
and runs it under address/undefined-behavior sanitizers. Only the description
lookup, which needs the kernel's file and resource types, is left out; the
`procfs-fdinfo` guest test covers it.

It checks Linux's `drm_fdinfo_print_size()` units (a KiB or MiB suffix only
while the size divides evenly, never past MiB), the key order of
`drm_print_memory_stats()`, the exact lines Asahi prints for a G13 client, and
that client numbers are unique, stable while a description is open, and new
after its address is reused. `DRM_FDINFO_SOURCE` selects another source, for
negative controls.

`tests/drm-wire` checks that closing a DRM description forgets its number, and
`tests/agx-file-close` checks what the AGX driver counts for a client.
