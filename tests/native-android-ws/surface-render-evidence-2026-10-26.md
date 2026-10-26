# Native framebuffer address regression

The maintained `check-surface-render.v` extracts the production `ws_render`
function and `WsSurface` layout. It retains the real pointer arithmetic, pixel
writes and C atomics, with deterministic JNI and TLS adapters. Actual
`mmap`/`mprotect` guard pages surround the framebuffers; a prefix canary and
complete checks of both buffers detect unintended writes within the mapping.

Host validation passed all 46 cases: hostile header geometry and buffer sizes,
active indices through `0xffffffff`, either reader-held buffer, sequence wrap,
JNI failures and rejected traversal. Each of three negative mutations failed:
unmasked active index, shared-header buffer size and removed reader protection.
The two address mutations attempted writes into protected/unmapped storage.
This is a host contract check, without ART, concurrent-reader or guest coverage.

Complete retained bundle:
`/Users/alex/.local/state/vinix/android/surface-render-check-2026-10-26-r2`.
Its `sha256.json` inventories the source snapshots, generated fixture, executable,
compile log, command receipts and all four run logs. The `build.json` hash is
`d281bfce9cd7f6006de2b987c9ffeee7b0bdea38abec6fab2733989557dc68f9`.

The checkout revision was `a6542b435879539480eaf46ef9cdafa470d4b451` with
the independently edited renderer pinned by its complete source hash
`e6effc4952fdc870bc88005df875d983fdca8addb7ad0f5ef2bb3c3abcd5087b`.
The checker source hash was
`d00cc889247078ed44e73239425ea5e73867da71634d3ee724e2daf700f06425`.

Reproduce with a fresh external output directory:

```sh
VINIX_V_COMPILER=/Users/alex/code/v/v /Users/alex/code/v/v run \
  tests/native-android-ws/check-surface-render.v /absolute/new/output-directory
```
