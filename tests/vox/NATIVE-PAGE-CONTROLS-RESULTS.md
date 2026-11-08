# Native page text and buttons — 2026-11-08

Page text now uses the layout baseline and the selected Vinix font atlas's
ascent. This puts link underlines below the glyphs while preserving the
browser's decoration geometry. Default HTML button bezels use the compositor's
native UI2 button renderer, with clipped bounds and reusable storage. Captions,
layout and DOM input remain with the browser. CSS backgrounds, borders, radii,
images and `appearance:none` retain web painting.

Validation: all 20 focused adapter tests passed on the host and in a fresh ARM64
Vinix guest. The browser smoke checks cover default, submit and disabled
buttons, CSS overrides, and retained hover/focus/DOM-mutation painting under
both LibWeb and Chromium font rendering policies. The Chromium UA's resting
colour override and shared hover/disabled colours are all recognised. The
existing JavaScript and wheel smoke checks also passed. A real guest pointer
click changed the welcome page's status to “JavaScript click received on
Vinix”; the button stayed native after that interaction. `git diff --check`
passed.

The evidence checker accepted six live process-memory samples. System used
memory fell by 7,536 KiB over the final 45 seconds, passing the existing
128 MiB growth guard. This is a functional memory check.

The build uses Vinix base `766450252194a60047d6e0782fdd2eb816279f47` plus
the archived source changes. The canonical Vox checkout supplies the browser;
its concurrently changing HEAD is recorded in the receipt, while the generated
C and executable hashes identify the tested input. The existing compositor
and retained PTY kernel are reused. This is a native UI2 run without X11.

SHA-256 identities:

- Browser: `8d8d32a72483867c206886fbfda0928c8585118df8384dc8dadeb9e87b373f33`
- Generated C: `67040a5c25608eb701d7b17facc50c22bc2d61642247f9579ba1975abeb9e900`
- Full screenshot: `95fd95377700313e43cdd41da25a6fad16564256443b84f3b52fc724d2a693a3`

Evidence directory:
`/Users/alex/.local/state/vinix-vox/validated-20261108-page-controls-8d8d32a7/`.
It preserves the full screenshot, focused-button screenshot, runtime evidence
archive, receipt, build/test logs and checksums. The archive includes the exact
patched paint transport and generated native font metrics. Its SHA-256 is
`d26606f94b6cb6c4e23af1a2febb73294267ee12007686313204d0190a5eaf77`.
