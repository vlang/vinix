# Native text-entry qualification

Signed native manifests may select `window_protocol:2` with display permission.
The service passes that installed protocol through the ordinary-account sandbox;
Software checks it before accepting a frame. The existing SDK/context/package
versions remain 1. Protocol 1 keeps its original encoding, 512-byte event limit
and reader. Protocol 2 adds single-line input fields capped at 256 UTF-8 bytes,
with distinct button/input IDs and five-field events including explicit empty
text replacements. Event lines are at most 2,048 bytes, below Vinix's 4,096-byte
atomic pipe-write bound.

Software edits only a clicked current-frame field. Enter commits the replacement;
Escape discards it; Ctrl+A and UTF-8 Backspace work locally. Invalid/control text
and oversized pastes preserve the old value. A new frame discards an unsent old
edit with a diagnostic. Frame sequences participate in protocol-2 UI action IDs,
so stale controls cannot send input to new frames. Package-manager actions stay
outside this namespace. Pending edits guard buttons, field changes and normal
close. Busy/closed pipes retain the draft and report failure without blocking or
signal-killing the desktop. Protocol failures clear focus and stop further input.

The SDK checks frame/event schemas, required/duplicate/escaped-duplicate keys,
UTF-8/control/size bounds, unknown versions, empty replacements and protocol
negotiation. `WindowFrame.accepts` binds events to protocol, sequence, identity
and control kind. EOF produces a negotiated close at sequence zero. Decoded
strings and partial failures retain their explicit ownership/retirement rules.

The [memo publisher example](../../examples/package-memo/README.md) builds static
V/musl applications on both architectures with SDK/V/musl redistribution notices.
It accepts bounded literal replacements and saves only through its Save button,
using a temporary file and rename in ordinary-account private data. Closing an
unsaved replacement keeps the last saved memo. Its manifest grants only display.

The 2026-10-13 qualification passes 34 host assertion runners, CLI/PTY/Software
fixtures, both target service stages, and SDK context/window allocation checks.
The final focused Software run covers the actual nonblocking full/closed-pipe
text-retention path using fixed-width C pipe descriptors. Codec assertions pass
ASan/UBSan with leak detection disabled and undefined behavior fatal. SDK and
broker loops each retain zero tracked bytes across 1,000 encode/decode/refusal
or fragmented-frame/focus/edit/discard/render/owned-tree-retirement cycles.

Desktop architecture checks and launcher assertions use an isolated checkout at
`aee171c08` plus these package changes, excluding simultaneous desktop work. They
reuse the retained qualified headless UI overlay and calculator examples from
[protocol-1 qualification](window-check.md). This validates the native broker/UI
code without modifying the live UI checkout. Compiler/generated-C notices remain
in the retained logs; this is not a warning-free claim.

Both real QEMU TCG guests freshly build the service, memo, guest init, account
manager and session runner. They use retained target kernels/native sandboxes,
verify nine admitted artifact hashes each and shut down cleanly. Required markers:

- `PACKAGE WINDOW INPUT signed-native ordinary-account UTF-8 literal-text frame-bound explicit-save PASS`
- `PACKAGE WINDOW INPUT empty-replacement rollback retained-data EOF-close policy-denial publisher-revocation PASS`

They install a signed offline memo package, check installed protocol 2, literal
Unicode/quotes/backslashes/shell-looking text, stale edits, wrong control kinds,
explicit save, private-data UID 1000, unsaved EOF close and saved empty replacement.
Uninstall removes registration and preserves data; rollback reopens it. Display
policy denial and publisher revocation refuse new launches. No X11 directory is
needed. AArch64 takes 11.4 seconds and x86_64 18.9 seconds. The x86_64 run selects
the retained Limine directory explicitly after the shared directory was unavailable.

Reproduce host checks using a qualified headless UI module and the reviewed V
compiler:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 CPATH=/path/to/vinix/desktop \
  VINIX_PACKAGE_TEST_UI2=/path/to/headless/modules \
  /tmp/distribution-check --direct-tests --cross
```

Build [the guest controller](window-check.v) with the repository and
`tests/hardware-platform` on the V module path. For each target, select input mode
and a new state directory:

```sh
VINIX_WINDOW_INPUT=1 VINIX_HWTEST_TCG=1 V=/path/to/v \
  VINIX_WINDOW_SANDBOX=/path/to/target/vinix-sandbox \
  VINIX_AMD64_LIMINE_DIR=/path/to/limine \
  /tmp/window-check --arch=x86_64 --kernel=/path/to/x86_64/kernel \
  --scenario=packages-window-input --state-dir=/tmp/new-window-input-state
```

Recorded results: [AArch64 receipt](results/2026-10-13/native-window-input-aarch64.json),
[serial](results/2026-10-13/native-window-input-aarch64.serial.txt),
[QMP](results/2026-10-13/native-window-input-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-13/native-window-input-x86_64.json),
[serial](results/2026-10-13/native-window-input-x86_64.serial.txt),
[QMP](results/2026-10-13/native-window-input-x86_64.qmp.txt),
[host summary](results/2026-10-13/native-window-input-host.txt) and
[toolchain/source ledger](results/2026-10-13/native-window-input-toolchain.json).

The guest workflow validates the signed isolated application and stream; host
fixtures exercise the actual broker/UI tree. This does not qualify a physical
display/screenshot, full ordinary-user desktop login, arbitrary graphics, audio,
clipboard, foreign graphical runtimes or public publisher enrollment. Catalog
migration and the wider roadmap acceptance gate remain open.
