# Vox RAM readout and classic bar — 2026-11-08

The Vinix overlay now supplies Vox's missing Linux memory sampler. The footer
reads current process resident pages from `/proc/self/statm` and multiplies by
the runtime page size. The guest uses 16 KiB pages. Parsing rejects malformed
and overflowing counters, and the read buffer is freed after each sample.

The adapter preserves Vox's curved tab outlines, gray strip, trapezoid new-tab
button and red/yellow/green window buttons from the supplied reference. The
plain tab-close mark uses the compositor glyph for reliable font coverage.
Vinix still handles the scoped window actions; the outer frame stays hidden.
Page fonts, favicons and native toolbar/bookmark controls remain available.

Validation passed:

- All 18 focused tests on the host and in a fresh ARM64 Vinix guest, including
  resident-page conversion, invalid/overflow input, live sampling, tab shoulders,
  window colors/actions and the unboxed close mark.
- Original JavaScript DOM, click and wheel smoke tests, plus an actual page click.
- Actual new-tab and tab-close clicks, maximize/restore, minimize/taskbar restore,
  tab-strip dragging and horizontal/vertical edge resizing.
- Eight live process-counter samples, no fatal guest markers, and the existing
  128 MiB memory guard: used memory decreased 13,136 KiB over the final 45 seconds.
  This is functional validation, not long-term leak qualification.
- Guarded cross-builds, generated-source identity checks, runtime inventory without
  X11 libraries, sampler vfmt verification and `git diff --check`.

Source base: Vinix `9e63dd605ce41428e86e56ed30da9cfd65e24d4d` plus this change.
The final browser uses the isolated Vox archive at
`f3c82806a80aa77a89adf55fc06fafd601d531be`, selected with `VINIX_VOX_SOURCE`.
The shared checkout's later HEAD in `receipt.tsv` is capture-time context.
Earlier shared-source compilation failures are retained separately. UI2 is
`c807d7651970a92be01c759363625031629c655c`; the previous desktop and PTY kernel
are reused. No shared Vox/UI2 source was modified.

SHA-256 identities:

- Browser: `e7126427973818979d203980bdf6f6b34e336beebc1da759c3c57f44b68405f5`
- Generated C: `86880d47c1342ea014c092eca299f6ea2eaa971ca44a4417a175b42640bc34b7`
- Screenshot: `27093869565975f45e384650dafb28efb1c191f6943cdf5844d67d0961d62a0e`
- Vox input archive: `0a4a787679525689679a6b3a754850e1a8752d756818973e605ee8eb38ed69a8`

Evidence directory:
`/Users/alex/.local/state/vinix-vox/validated-20261108-ram-classic-e7126427/`.
Its complete `vox-native-evidence.tar.gz` has SHA-256
`42c3bca5bd283399b3f138c3988778ecdc911ae22bdbda756f9c8276193a5aad`.
`SHA256SUMS` also binds the input source archive, reference image, running and
two-tab screenshots, receipt and logs. The archived port source predates this report.
