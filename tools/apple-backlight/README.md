# Apple DCP backlight: experimental, incomplete integration

**This implementation does not yet enable brightness adjustment on an M1 MacBook Air.**
It provides the backlight state machine, calibration, firmware-layout encoding,
and a Vinix character-device adapter. The current Vinix DCP implementation does
not provide the real IOMFB shared-memory RPC transport needed to use them.
The adapter is deliberately **not registered or imported by the existing DCP
initialiser**, so this implementation does not create `/dev/apple-panel-bl` on boot.

The implementation and tests are now entirely V. The adapter retains the
existing registration contract and does not alter boot defaults or turn on DCP.

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
and devtmpfs interfaces. Registration is an explicit call by a working DCP
backend. It creates a mode-0600 character device, invokes the scheduling hook
outside its state lock, supports offset-aware text reads, and refuses writes
while offline. The resource and callback context have boot lifetime. Registration
is boot-time, single-threaded, for one internal panel; it is not hotplug support.

The core is platform-independent and tested directly with V. State is stored
inline in the resource; there is no opaque C allocation or custom C ABI.

## What remains before this can change your screen

The following prerequisites remain; they are not merely optional hardware
verification:

1. A real IOMFB transport: shared-memory setup, DMA mappings/cache visibility,
   reversed-fourcc packet headers, command/callback context stacks, dispatch of
   RTKit system messages, correlated responses and bounded timeouts. The current
   `iomfb.v` sends simplified message types in bits 55:48; the upstream protocol
   uses a different mailbox format and shared-memory packets. Adding another
   simplified message would not implement brightness.
2. A working DCP takeover/lifecycle: discovery of the correct mailbox and IOMMU
   through device-tree relationships, preservation of existing mappings and
   scanout, firmware-version selection, initialization callbacks (including
   backlight-service matching), panel capabilities and brightness-scale data.
3. Real `swap_start`/`swap_submit` integration, including a brightness-only swap
   when the console/compositor is idle, and publication of actual-brightness
   callbacks. The existing `IomfbSwapDesc` is **not** a wire `dcp_swap` and must
   never be passed to `prepare_swap`.
4. An ARM64 kernel build and real M1 Air testing of brightness changes, errors,
   idle updates and resume. The full ARM64 kernel has passed V-to-C generation with this adapter,
   but a linked boot image and hardware behavior are not validated here.

Do not enable `vinix.apple_dcp=1` merely to try this implementation. It does not repair the
existing experimental DCP bring-up. There is no new brightness boot flag, no
PWM/GPIO fallback and no software dimming masquerading as a backlight driver.

## Backend integration contract

After an independently working backend has identified the M1 Air internal panel,
selected a verified wire layout, matched the backlight service, and obtained the
panel maximum and `Brightness_Scale`, it may call:

```v
// Implemented API; currently no upstream caller exists.
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

## Userspace interface, AFTER backend integration only

The following commands are the intended implemented device ABI, **not commands
that will work on current Vinix merely by adding this code**:

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
builds. A complete native desktop build and ARM64 kernel V-to-C generation
have passed. This is not a linked/booted Vinix kernel or a hardware test.

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
- Vinix `kernel/modules/dev/pointerdev/pointerdev.v`, blob
  `67c3eab401ff4c071543101e4ff90efd7b847030`: resource method signatures.

Upstream source locations:

```text
https://github.com/vlang/vinix/tree/cf9d952376ca96af721a182b3604a07742717050
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/dcp_backlight.c
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/iomfb_template.h
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/iomfb_template.c
https://github.com/AsahiLinux/linux/blob/asahi/drivers/gpu/drm/apple/iomfb.h
```

The V core and tests are offered under GPL-2.0-only OR MIT, retaining the
Asahi contributor notice. The V adapter is GPL-2.0-or-later, consistent with
Vinix. The MIT option's text is in `LICENSE.MIT` in this directory.
