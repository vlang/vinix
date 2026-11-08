# Full Vox window with PNG navigation icons — 2026-11-08

Captured the complete browser window on the ARM64 Vinix desktop, including
the classic tab strip, PNG navigation icons from Vox `97c58579f`, bookmarks,
rendered welcome page and resident-RAM status. The page's JavaScript button
received a real guest pointer click. The screenshot is a QEMU framebuffer
capture, without compositing or replacing the toolbar.

The current compiler emits vlib's retained Brotli no-op helper under its V
name instead of its declared export name. The browser C build now aliases the
C spelling to that same helper when the generated source requires it. This
keeps vlib's MemorySanitizer selection intact and records the compatibility
flag in `vox.o.flags` so an incompatible cached object cannot be reused.

Validation: guarded native link, all 18 focused tests on the host and in a
fresh Vinix guest, original DOM/click/wheel smoke checks, and `git diff --check`.
The evidence checker accepted 17 live memory samples and 2,016 KiB of system
used-memory growth over the final 45 seconds; this is a functional guard.
The existing compositor and retained PTY kernel are reused. The canonical Vox
checkout was used for the cross-build; the generated C identifies the exact input
more precisely than its concurrently changing HEAD.

SHA-256 identities:

- Browser: `c2e188896caa522b834cc2567d8ed2d634cba86c402fab1803f93f9a0afd459b`
- Generated C: `eae2d64173282d87a070ad5264cc4a476dbda0a71f8c3d34610b98028bcd6026`
- Full screenshot: `36c7c517c336e7edd9ae2a8e192553996f36f59a1cae0fbd56d9f587bbe78849`

Evidence directory:
`/Users/alex/.local/state/vinix-vox/validated-20261108-navigation-window-c2e18889/`.
It contains the full screenshot, complete runtime evidence archive, receipt,
build/test logs and `SHA256SUMS`. The archived source predates this report.
The complete evidence archive has SHA-256
`19567287dc787133ea4f7c3ee1c160f8d3e5d5b3402960dcd30803322541eddc`.
