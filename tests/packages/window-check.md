# Native window protocol qualification

Signed native manifests can opt into `window_protocol:1` and declared display
permission. Software selects `run-window` from installed metadata, including
Start/Quick Launch/document requests, and renders bounded labels, buttons and
rectangles within its own window. The ordinary-account package service retains
trust, policy, payload checks and its generation lease. Window mode grants no
X11 socket, Unix/TTY promise or hardware display/input device.

The SDK uses complete format-1 display-list frames and frame-bound button/close
events over standard streams. Input writes are bounded below PIPE_BUF and use a
nonblocking pipe; busy or closed input cannot block or signal-kill Software.
Action IDs are namespaced internally. Only a current button's ID can be sent;
an app-owned `software.confirm` ID cannot confirm a package operation. Normal
close waits for the application and its service. Forced broker retirement closes
streams without killing the lease holder; the SDK translates EOF to close.

The schema reader rejects unknown/duplicate/escaped-duplicate keys, missing
fields, trailing input/commas, invalid integer types/overflow, malformed strings,
invalid UTF-8/Unicode surrogate pairs, unsupported versions/kinds, dimensions,
element counts and bounds. It owns every decoded field and retires partial data
on failure. Encoding uses an explicitly owned append buffer. This avoids the
pinned JSON codec's measured allocations on each repeated call. A protocol
failure freezes presentation and prevents further malformed-frame decoding.

Host assertions cover both target launch plans, required native/display metadata,
publisher/policy denial, absent X11/TTY/device grants, session handoff, zero-field
omission preserving legacy manifest bytes, and installed versus pending window
metadata. Codec assertions cover round trips, ownership, schema failures, escaped
keys and Unicode. The actual Software fixture checks fragmented frames, overflow,
namespaced UI trees, literal service arguments, clicks, close acknowledgement,
EOF retirement, a full pipe, and a closed pipe. SDK and broker heap checks each
run 1,000 update/encode/decode/render/refusal/retirement cycles and retain zero
tracked bytes. The codec assertion runner passes ASan/UBSan with leak detection
disabled and undefined behavior fatal.

The [signed counter example](../../examples/package-counter/README.md) builds
static V/musl payloads for both architectures and retains SDK/V/musl notices.
Both real guest workflows install the signed native app, run it through the
ordinary account, accept one click and reject its stale replay, acknowledge close,
and persist the count in that account's private data. They then uninstall its
registration, retain data, roll back, close through EOF, and refuse new launches
after display-policy denial or publisher revocation. There is no X11 directory.
Required guest markers:

- `PACKAGE WINDOW signed-native ordinary-account no-hardware-grants click stale-input close private-data PASS`
- `PACKAGE WINDOW rollback retained-data EOF-close policy-denial publisher-revocation PASS`

Reproduce the host checks with the pinned compiler, generated desktop assets,
headless UI overlay, and a UI source directory containing calculator examples:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 CPATH=/path/to/vinix/desktop \
  VINIX_PACKAGE_TEST_UI2=/path/to/headless/modules \
  VINIX_PACKAGE_TEST_DESKTOP=/path/to/generated/desktop-assets \
  VINIX_UI2_SOURCE=/path/to/qualified/ui-source \
  /tmp/distribution-check --direct-tests --cross --desktop
```

[The guest controller](window-check.v) requires `VINIX_HWTEST_TCG=1`, a matching
retained native sandbox through `VINIX_WINDOW_SANDBOX`, the target kernel, and a
new `--state-dir`. It freshly builds the counter/service/init/account/session
programs and hashes admitted inputs before boot. Kernels/sandboxes are retained.

The 2026-10-13 host run passes 33 assertion runners, SDK context/window heap,
CLI/PTY/Software fixtures and both target service builds. Final desktop checks
use a detached checkout at `9b01dbca2` plus the owned changes, excluding another
session's unfinished framebuffer files. They use the retained qualified headless
UI overlay with calculator examples; the staging input restores the original
VmlApp receiver spelling before the existing staging rename. This avoids the
live UI2 headless-adapter mismatch and keeps other sessions' source untouched.
The codec ASan/UBSan run and the focused installed/pending metadata check pass.
Both QEMU TCG guests pass with clean shutdown: 33.4 seconds on AArch64 and
44.4 seconds on x86_64, within the 300-second deadline.

[Host evidence](results/2026-10-13/native-window-host.txt) and
[compiler/source/artifact ledger](results/2026-10-13/native-window-toolchain.json)
retain passing markers and scope. Guest receipts, serial and QMP:

- [AArch64 receipt](results/2026-10-13/native-window-aarch64.json),
  [serial](results/2026-10-13/native-window-aarch64.serial.txt) and
  [QMP](results/2026-10-13/native-window-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/native-window-x86_64.json),
  [serial](results/2026-10-13/native-window-x86_64.serial.txt) and
  [QMP](results/2026-10-13/native-window-x86_64.qmp.txt).

The ledger verifies nine hashes per guest. Full logs, generated C, binaries,
validation checkout and staging helpers remain under `build/package-window-work`.
Existing compiler notices/warnings remain in those logs.

This initial public interface supports label/button/rectangle applications.
It does not qualify text entry, arbitrary raster/GPU graphics, clipboard,
file pickers, audio, graphical Linux/Wine/Apple runtimes, a complete ordinary-user
desktop login, physical hardware or public publisher enrollment. The guest
checks exercise the real isolated app and stream contract; host fixtures check
the actual broker/UI tree. They do not constitute a new desktop screenshot or
physical display qualification. Roadmap 14 remains open.
