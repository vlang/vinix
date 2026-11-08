# Native Vox fonts, controls and favicons — 2026-11-08

The browser now publishes decoded tab and bookmark favicons through shared
surfaces, uses native Vinix buttons and navigation symbols, and leaves window
management to the desktop's title bar. Ordinary page text uses the compositor's
Roboto coverage renderer, with clipping and monospaced styles. The same Roboto
files supply layout metrics. Font sizes and weights follow Vinix's available
baked faces; the demo uses its 28px display, 18px heading and 13px body styles.

Validation passed on a fresh ARM64 Vinix guest without the diagnostic tracer:

- All 14 focused tests on the host and in the guest, including favicon alpha,
  icon/caption spacing, readable builtin symbols, clipping and arena lifetimes.
- The original browser's JavaScript DOM, click and wheel smoke checks.
- Visible original Wikipedia, Reddit, V and Hacker News bookmark icons, plus
  the local page's generated data-URL favicon in its tab.
- Actual native Reload and JavaScript-button clicks: Reload reset the page's
  status, then clicking its test button changed the DOM again.
- The evidence recorder accepted 14 live samples, no fatal guest markers and
  33,712 KiB of system used-memory growth over the final 45 seconds, including
  page/reload activity. This remains a functional guard, not leak qualification.
- Formatting verification and `git diff --check`.

Source base: Vinix `b5f59f2b937f7d31633427210105bfaa1dafd635` plus this change.
Capture-time heads were Vox `904279a38dfa0e8edb25a3896f9933c713770642` and UI2
`c807d7651970a92be01c759363625031629c655c`. The shared Vox tree changed during
the work; generated C, source overrides and recorded patches identify the
checked build more precisely than those heads alone. Source snapshot SHA-256:
`e346dce55e0ad5e566bdfff1785803a6cd0f12efe9380da2d316bc8de2d8290f`.

Executable SHA-256:
`082c20ffd4cedf57e7fa0fcd52af380daa68bb939887f437248d1bb876ba9a70`.
Generated C SHA-256:
`2a874d348f14110c2eadcbc549408f5cfbdad4e239c1312c97146113ccd12350`.
Screenshot SHA-256:
`e844393ef333d2ad1c444ed8a30e211206738c456ee38181fd04ee1bfc577ca4`.

Evidence is preserved in
`/Users/alex/.local/state/vinix-vox/validated-20261108-native-chrome-082c20ff/`.
Its complete `vox-native-evidence.tar.gz` has SHA-256
`a4f33b360bc601614b746fb2f35c9ee26c9daa421f7583b11a1cdbd9545cfc1c`.
`SHA256SUMS` also binds the PNG, receipt, successful compiler diagnostics and
earlier failure logs. The archive's source snapshot predates this report.

Generation succeeded under the memory guard with separate compiler diagnostics;
`finish-source` applied the normal completeness, allocator and ABI-header checks
before the native compile. An earlier automatic compiler retry failed and is
preserved. An earlier development binary also aborted once while input was sent
during boot; this was not reproduced in the traced or subsequent normal runs.
No crash-free or long-term performance qualification is claimed. The retained
PTY kernel and CPU rendering limitations remain as described in [the workflow](README.md).
