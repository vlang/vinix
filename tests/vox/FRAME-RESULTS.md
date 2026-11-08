# Vox client-side window frame — 2026-11-08

The Vinix UI2 backend now exposes `set_window_decorated(false)` before
`run_window`. Vox selects it and uses its own tab strip with native close,
minimize and maximize controls. Scoped actions address only that client window.
The compositor preserves invisible edge resizing, full-client input coordinates,
taskbar management and standard recovery chrome. Legacy/default clients keep
their decorations through the compatible version-11 hello extension.

Validation passed:

- 35 desktop tests across the client-frame, window-edge, window-action and
  title-bar suites, including all four themes and legacy/truncated negotiation.
- All 15 browser adapter tests on the host and in a fresh ARM64 Vinix guest,
  including the actual UI2 decoration-setting handshake over pipes.
- The original browser's JavaScript DOM, click and wheel smoke checks.
- Actual maximize/restore, tab-strip drag, horizontal/vertical edge resizing,
  minimize, taskbar restore, page JavaScript click and clean client-button close.
- Guarded browser and desktop builds, runtime inventory without X11 libraries,
  no fatal guest markers, and `git diff --check`. New desktop files pass vfmt.

The evidence checker accepted 15 memory samples; the final 45 seconds include
closing Vox and therefore show memory returning to the system. This is a
functional guard, not an idle-memory or leak qualification.

Source base: Vinix `6f58d7804e74d96ee485c49a044dc406fa3b322d` plus this change.
Capture-time heads: Vox `56fb63f672737ab6e0a0a233f881582f4381db4e`, UI2
`c807d7651970a92be01c759363625031629c655c`. The generated C, staged overrides,
source snapshot and patches in the bundle identify the shared-source build.
The retained PTY kernel and CPU renderer are unchanged.

SHA-256 identities:

- Browser: `76139e8ef188be9622dd52d074faaa2170457b3f9298f1624c9d54048b4fd714`
- Generated C: `a9a223923dd4d353e1e4dd2c517916ba8f396500449497a86ec66b626f0acf61`
- Desktop: `c79d4a20b7678a942f4dcf89726f82736e0c66312c3bcdc496259392ad7b8fc8`
- Running screenshot: `172c9cab2df4778a7033dedb7964b8bbe1f12ae6c235889843345ec4cc638fbf`

Evidence directory:
`/Users/alex/.local/state/vinix-vox/validated-20261108-client-frame-76139e8e/`.
Its complete `vox-native-evidence.tar.gz` has SHA-256
`32889010468b7f54dd599206d70e681ba60a7451922018454a3f29c6aae5aa59`.
`SHA256SUMS` also binds the running, maximized, minimized and closed screenshots,
receipt and build/check logs. The archived source snapshot predates this report.
