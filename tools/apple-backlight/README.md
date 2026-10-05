# Apple DCP internal-panel backlight

Vinix has a real, opt-in backlight transport for base M1/t8103 machines. It
boots DCP through RTKit, completes the versioned IOMFB shared-memory handshake,
preserves m1n1's inherited framebuffer and locked display-DART mappings, and
submits brightness-only swaps. Once firmware publishes the internal backlight
service and `Brightness_Scale`, the driver creates `/dev/apple-panel-bl` for the
desktop Display settings page.

The driver remains disabled by default because DCP takeover is hardware-facing
and has not been exercised from this checkout on a physical machine. Enable it
with `vinix.apple_dcp=1`, or deploy a desktop image with:

```sh
./deploy-m1-efi.sh --desktop-initramfs --apple-dcp /path/to/mounted/esp
```

The current transport intentionally supports only t8103 internal panels and
the 12.3 and 13.3/13.5-compatible IOMFB layouts advertised by the m1n1 device
tree. It does not modeset, replace the boot framebuffer, probe external
displays, or provide a software-dimming fallback.

## What is implemented

`kernel/modules/gpu/dcp/backlight/core/core.v` is native V with no heap allocation,
MMIO, firmware messaging, or floating point. It provides:

- Asahi's packed calibration-table interpolation for 2–509 nits, further bounded
  by the actual panel maximum supplied by the backend. No hardcoded M1 maximum
  is treated as discovered hardware information. Zero is not an off command;
  panel blanking belongs to the display power-management path.
- Little-endian, unaligned-safe updates of **only** `bl_unk`, `bl_value` and
  `bl_power` in the verified 12.3 and 13.3 wire-layout families. Unknown layouts
  and short buffers fail without modifying the buffer. The host tests derive
  the offsets independently from packed reference structures.
- Strict whole-write decimal parsing, bounded inputs and range checking.
- Coalesced requests, at most one active brightness transaction, unique retry
  tokens, rejection of stale/duplicate completions, retained requests after
  failure and suspend, and no change to the inherited brightness on attachment.
- Separate requested and firmware-reported brightness. A successful submission
  never invents an actual measurement. Property 15 is divided by the nonzero
  `Brightness_Scale` supplied by the transport.

`kernel/modules/gpu/dcp/backlight/backlight.v` adapts the core to Vinix's resource
and devtmpfs interfaces. The real t8103 transport registers it only after a
successful firmware handshake. It creates a mode-0600 character device, invokes
the scheduling hook outside its state lock, supports offset-aware text reads,
and refuses writes while offline. The resource and callback context have boot
lifetime. Registration is boot-time, single-threaded, for one internal panel;
it is not hotplug support.

The core is platform-independent and tested directly with V. State is stored
inline in the resource; there is no opaque C allocation or custom C ABI.

`kernel/modules/gpu/dcp/backlight_transport.v` provides the hardware backend. It
discovers both DCP and PIODMA DARTs from DT relationships, adopts locked m1n1
page tables, installs reserved firmware mappings, services RTKit buffers and
IOMFB callbacks, validates firmware-requested MMIO mappings, and runs a polling
worker so a brightness write does not depend on compositor activity. Any
protocol error poisons the session and takes the character device offline.

## Hardware status and scope

The linked ARM64 kernel builds, and the platform-independent protocol/layout
tests pass. Physical M1 validation is still required for brightness changes,
readback, idle updates, failure handling, and resume. On a successful boot the
kernel prints:

```text
dcp-backlight: /dev/apple-panel-bl online (max ... nits, scale ...)
```

If that line is absent, retain the preceding `dcp-backlight:`, `dart:`, and
`rtkit[dcp-backlight]:` messages; they identify whether DT discovery, DART
handoff, RTKit boot, or the IOMFB callback handshake failed.

There is no PWM/GPIO fallback and no software dimming masquerading as hardware
brightness. External-display handoff explicitly keeps this internal-panel DCP
path disabled.

## Driver contract

After identifying the internal panel, selecting a verified wire layout,
matching the backlight service, and obtaining the panel maximum and
`Brightness_Scale`, the transport calls:

```v
register_panel(layout, maximum, scale, initial_raw, initial_known,
    context, notify) ?&Backlight
```

`notify` must queue nonblocking work, including when no other frame is pending.
It is called without the backlight lock. All V adapter methods run in task
context; interrupt handlers must enqueue work instead of taking its task lock.
The worker must avoid losing a notification arriving while a swap is in flight:
after every completion, check/prepare again until there is no pending update.
Do not spin indefinitely on a firmware failure.

For each actual swap, call `prepare_swap` with the real versioned swap structure
at the start of the full RPC input buffer. A zero token means no brightness
update. For a nonzero token, keep that exact token with the RPC completion and
call `complete_swap(token, accepted)` only after validating the endpoint,
context, request identity, response size and firmware status. Never interpret
successful mailbox transmission as firmware acceptance.

A timeout faults/quiesces the transport before reuse of a command channel or
shared buffer. The backlight core's software retry token is not a substitute
for that protocol-level recovery. Keep DMA buffers mapped/alive until the
firmware is stopped or its use of the buffers is definitively finished.

Call `publish_nits` only for decoded property-15 messages from the active
firmware session. Drop callbacks from earlier sessions, including old property
notifications (unlike completions, the property payload has no backlight token).
The firmware reports actual values; they can legitimately lie outside the
writable calibration range and must not be replaced by the requested value.

Call `set_online(false)` before suspend, reset or fault. It rejects new writes,
invalidates actual readback and cancels active software tokens while retaining
the user's desired value. After transport recovery, call `set_online(true)` and
schedule a new swap. Do not reinitialise the V state on resume, which would reset
the monotonically increasing transaction-token namespace. The layout and scale
must remain unchanged for this device lifetime; firmware upgrades require a new
boot/validated attachment rather than silently reusing an old layout.

## Userspace interface

With the opt-in driver online, the device ABI is:

```sh
cat /dev/apple-panel-bl
printf '100\n' > /dev/apple-panel-bl  # absolute nits, NOT percent
```

A read has the following shape (illustrative numbers):

```text
requested_nits=100
actual_nits=99
min_nits=2
max_nits=400
pending=0
online=1
```

`requested_nits` is `unknown` until the first user request. `actual_nits` is
`unknown` until a firmware report or a trusted initial report is available.
`pending=0` means the current request has a successful firmware response, not
that an exact luminance has been measured. Actual nits can differ due to
quantisation. A write accepts one complete decimal value with an optional
single trailing newline; it reports that the request was queued. Signs,
whitespace, NUL bytes, multiple values, off commands and values above the
advertised maximum are rejected. Separate writes are separate requests.
Reads snapshot current state per read operation, not per open file descriptor.

## Run the tests

From the repository root, without kernel dependencies:

```sh
V=/path/to/v sh tools/apple-backlight/test.sh
V=/path/to/v sh desktop/tools/test-settings.sh
```

`VFLAGS` can choose the compiler, C backend or sanitizers for generated code.
V is required; missing tools are errors rather than skipped validation.
`tools/apple-backlight/core_test.v` is staged beside the real core and run by V.

Eight groups cover all 508 supported nit values, golden calibration transitions,
all single-byte parser suffixes, packed V reference structs and every short-buffer
length, unchanged non-backlight bytes, atomic initialization, pending requests,
coalescing, failed transactions, stale/duplicate completions, recovery, unknown
readback, capacity bounds and token/generation overflow. The desktop tests also
round-trip commands and snapshots through this actual V core.

Both the Vinix-pinned V 0.4.10 and the V 0.5.2 bootstrap run the core/client
tests. The current ui2 checkout needs the newer compiler for UI/full desktop
builds. A complete native desktop build and linked ARM64 kernel build have
passed. This is not a physical-hardware test.

## Source provenance

Primary sources inspected on 2026-09-06:

- Vinix `kernel/modules/gpu/dcp/iomfb.v`, blob
  `3e1d3f9d264fccd685d099a1a31ddb13a9011147`, and `dcp.v`, blob
  `3dc10b5d1f7beb7c45bef237dede8170bb8f719f` at the original implementation base `cf9d952376ca96af721a182b3604a07742717050`.
- Asahi Linux `drivers/gpu/drm/apple/dcp_backlight.c`, blob
  `9eb0c7d4eb5345178f802e55dc8e8a3dbdbea8cd`: calibration tables/interpolation.
- Asahi Linux `drivers/gpu/drm/apple/iomfb_template.h`, blob
  `8efab49cc53d08964a5da5476fb99c050923aaa2`: packed wire layouts.
- Asahi Linux `drivers/gpu/drm/apple/iomfb_template.c`, blob
  `cf40e273a2f43cd6576857f45e89a9edb4e5c841`: backlight-service matching,
  `bl_unk=1`, `bl_value=dac`, `bl_power=0x40`, property/scale handling.
- Asahi Linux `drivers/gpu/drm/apple/iomfb.h`, blob
  `7903fad4040677d971c1691657e56a3e3e5ee831`: message fields and property 15.
- Asahi Linux `drivers/gpu/drm/apple/iomfb.c`, `iomfb_v12_3.c` and
  `iomfb_v13_3.c`: shared-memory channel layout, nested RPC/callback handling,
  boot sequencing and versioned callback tables.
- Asahi Linux `drivers/iommu/apple-dart.c` and m1n1 `src/dart.c`/`src/kboot.c`:
  t8103 PTE encoding, locked-DART handoff and reserved display mappings.
- Vinix `kernel/modules/dev/pointerdev/pointerdev.v`, blob
  `67c3eab401ff4c071543101e4ff90efd7b847030`: resource method signatures.

Upstream source locations:

```text
https://github.com/vlang/vinix/tree/cf9d952376ca96af721a182b3604a07742717050
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/dcp_backlight.c
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/iomfb_template.h
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/iomfb_template.c
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/iomfb.h
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/iomfb.c
https://github.com/AsahiLinux/linux/blob/asahi/drivers/iommu/apple-dart.c
https://github.com/AsahiLinux/m1n1/blob/main/src/dart.c
https://github.com/AsahiLinux/m1n1/blob/main/src/kboot.c
```

The V core and tests are offered under GPL-2.0-only OR MIT, retaining the
Asahi contributor notice. The V adapter is GPL-2.0-or-later, consistent with
Vinix. The MIT option's text is in `LICENSE.MIT` in this directory.
