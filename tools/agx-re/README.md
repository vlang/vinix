# AGX reverse-engineering tools

This directory contains read-only host tools used to replace guesses in the
Vinix AGX driver with observations from Apple hardware and software. It does
not contain or redistribute Apple firmware, kernel collections, or drivers.

`inspect_macos.py` collects a sanitized JSON hardware manifest from `arm-io`,
the `sgx` Apple DeviceTree node, the active GFX/PMP firmware wrappers, the AGX
accelerator, and the installed driver Info.plist:

```sh
./inspect_macos.py
python3 -m unittest -v test_inspect_macos.py
```

Apple DeviceTree numeric data exposed by `ioreg -a` is native little-endian.
The Vinix flattened-device-tree parser, in contrast, correctly treats FDT
cells as big-endian. Keep that distinction when moving observed values into
the kernel.

On the inspected M5 Max, `arm-io` reports one active die and live IORegistry
contains only `PMP0`, despite the signed boot DeviceTree containing both PMP0
and PMP1 hardware templates. The same machine has four GPU partitions, so
`num_mgpus` is not a die or PMP-wrapper count. Schema 3 records the platform
die count and warns unless it exactly matches the ordered active PMP roles.
It also records each live PMP firmware segment so a runtime-preload mapping
cannot be confused with properties present in the signed template.

The IOKit/IOGPU tracer records external-method selectors and the private
IOGPU command-buffer segments Apple's Metal driver produces for a matched
clear/triangle pair. With an explicit resource opt-in, it also snapshots only
CPU-visible allocations whose GPU virtual addresses occur in those segments.
It never maps an unknown GPU address or accesses GPU MMIO.

```sh
make -f GNUmakefile test
make -f GNUmakefile inspect
make -f GNUmakefile trace
make -f GNUmakefile trace-resources
make -f GNUmakefile layout
make -f GNUmakefile firmware
make -f GNUmakefile pmp-firmware
make -f GNUmakefile kernel-kexts
make -f GNUmakefile recover-t6050-power
make -f GNUmakefile recover-g17-abi
```

The normal trace is written to `build/agx_trace.jsonl`; the larger resource
trace goes to `build/agx_trace_resources.jsonl`. `AGX_TRACE_BYTES` caps each
snapshot at 64 KiB. These traces contain process-specific addresses and must
not be committed. Set `AGX_TRACE_ALL=1` only when calls on non-GPU IOKit
connections are relevant. Selectors `0x100` through `0x112` are annotated with
names recovered from the local
`AGXDeviceUserClient::getTargetAndMethodForIndex` table.

`trace_diff.py` defaults to comparing the clear and triangle command segments.
`--walk` instead parses each primary segment with the record and
primary-extension framing recovered from
`AGXHardwareKernelCommand::parseAndValidate`, and reports the gates and byte
lengths for the method's separate auxiliary stream. This is how the grammar is
checked against bytes the Metal driver actually produced without conflating
the two parser cursors.
It can also select a shared allocation by an observed JSON field:

```sh
./trace_diff.py build/agx_trace_resources.jsonl \
  --event resource_snapshot \
  --where resource_gpu_address=0x10000138000
```

`objc_layout` records class, method, and ivar metadata exposed by the local
Objective-C runtime. `extract_firmware.py` extracts only the matching G17C
images from the local recovery volume and emits their hashes, Mach-O UUIDs,
and virtual layouts. `extract_pmp_firmware.py` accepts the local bare recovery
IM4P or boot IMG4 form of `t6050pmp`, verifies its `pmpf` payload is an ARM64
PRELOAD Mach-O, and records its hash, UUID, virtual layout, symbol count, and
function-start-metadata boundary. `extract_fileset.py` unwraps the local IMG4/LZFSE boot
kernel collection and compacts the kernel, AGXG17X, firmware-buddy, and
AppleARMPlatform/PMGR/PMP power-owner fileset entries
into standalone Mach-Os suitable for `xcrun llvm-nm` and `xcrun llvm-objdump`.
`IOGPUFamily` is included because `AGXCommandQueue` inherits its device
binding, and with it the last two channel inputs, from `IOGPUCommandQueue`;
`IOSurface` identifies the cross-kext shared-event completion target.
`recover_t6050_power.py` independently parses the local IMG4/LZFSE boot
DeviceTree and resolves SGX's opaque power/clock handles against PMGR's device
records. It fails closed unless the installed T6050 image maps them, in order,
to `GFX_SGX` and `GFX_BUSY`, identifies both GFX ASC handles, and proves that
the AGX SoC-device record and device-state request/ack PTD ranges belong to the
`t6050pmp` RTKit nub. It also checks the UUID-pinned ApplePMGR binary for the
command-14/15 PTD-dashboard dispatch, its state/index bounds, exact host-built
selector maps, and the flag-`0x02` filter used by initial and dynamic state
notification. The report distinguishes the four flag-`0x10` GFX leaf records,
which do not emit PMP state commands, from the aggregate `GFX` proxy whose
selector `0x10` reaches the ordinary AGX request/ack path. It also proves that
dynamic transitions wait on the per-die `PMP-STATUS` PTD entry before device
status mutation, while explicitly reporting that the separately scheduled
initial-status callback has no such local wait. The ordinary transaction
proves why: it publishes its persistent request before sampling status and
returns without reading `PS-ACK` when status is zero; a nonzero status enters
the acknowledgement loop. The report also pins the AGX mask, `newData`
metadata bit, state-match condition, 15-second fatal timeout, and its single
persistent request write. The same
ApplePMGR check recovers the asymmetric ApplePTD read and write windows and
metadata transform. A UUID-pinned AppleT6050PMGR check proves that PTD RegMap
enum 8 maps to DeviceTree `reg[7]` once per die; the signed DeviceTree resolves
the two template apertures to `0x84240000` and `0x4084240000`. It also proves
both static PMP templates have identical device/range tables, pins their
die-strided shared regions, validates every die-strided wrapper register/IRQ/
gate binding, and records the requested-die selection used by ordinary state
commands. The live inspector separately determines which templates are active.
The UUID-pinned ApplePMPFirmware/RTBuddy pass additionally recovers the nine
mandatory 32-bit PMP patchbay inputs and the exact RTBuddy firmware-fixup
ordering. It also recovers how a patchbay is located at all -- the eight
candidate identity-block offsets, the `uuid` magic, the version-4/5 field
pairs, and the `{tag, length, value}` record walk -- and applies that format to
the extracted `t6050pmp` image, so `recover-t6050-power` now depends on
`pmp-firmware`. The recovery fails closed if the located records do not tile
their declared region exactly or if any mandatory tag is absent or not 32 bits
wide. Its `firmware-loaded` byte and IORegistry announcement are reported
as image-preparation bookkeeping, not as a PMP run-state or dashboard-ready
acknowledgement. The same UUID-pinned RTBuddy pass now follows the subsequent
managed boot path: status 4 precedes `startCPUWithOptions`, a protocol-12 Hello
advances to status 5, and only a successfully replied endpoint roll call
advances to transport-ready status 6. Both polling and blocking validation
paths are pinned, including timeout and terminal-failure behavior. Status 6 is
RTKit transport readiness, not ApplePMGR's separate `PMP-STATUS` or AGX
dashboard acknowledgement. The roll-call decoder also proves that the low
32-bit bitmap names wire endpoints in groups of 32. RTBuddy's generic service
label subtracts `0x1f`, so the live `PMP0Endpoint1` service is wire endpoint
`0x20`, not endpoint 1. The live inspector now checks that translation for
every active die without retaining registry identifiers. Vinix
mirrors the low-level contract with a dormant bounds-checked
paired reader and separate write portal. A nonblocking owner serializes one
transaction across the active dies and makes post-write failures sticky, but
it is not mapped until PMP service and firmware startup can be integrated
behind the G17 boot gate. A separate UUID-pinned
ApplePMP check recovers the
PMPv2 64-bit mailbox classes and proves that PM subtype 1 is specifically a
ping completion: it clears and wakes the ping's in-flight byte. The generated
report labels that result as neither global PMP nor AGX-dashboard readiness,
and likewise keeps ApplePMP's diagnostic `pmptool-config` writer separate
from ApplePMGR's device-state request. Together with a UUID-pinned RTBuddy
image, the same check proves that ApplePMP resolves wrapper `reg[3]` through
`ptd-update-reg-index`, obtains mapper index 1, and installs the endpoint
message and power callbacks only after those resources. That result is an
attachment contract, not a firmware-readiness signal. The report separates
the SoC-device ID, record index, dense virtual-state index, and SOC-DEV-PKT bit
slice; those values are not interchangeable. Its sanitized JSON report is
written under `build/`; raw Apple DeviceTree or executable bytes are never
repository inputs.
The UUID-pinned AppleA7IOP check independently proves that
`AppleWrapperMailbox` maps wrapper device-memory index 0, retains both its map
and virtual address, and performs 32-bit register loads using byte offsets.
It also ties the wrapper physical-address accessor to that same retained map.
The result identifies T6050 wrapper `reg[0]` as the mailbox/control Device-MMIO
aperture without treating resource ownership as CPU-start or IOP readiness.
The alternate `AppleA7IOP` class independently maps the same index and proves
that `sram-index` is forwarded as a provider power-domain selector rather than
a `reg[]` index. The UUID-pinned concrete `AppleASCWrapV6` subclass maps
wrapper `reg[1]` and proves it is the 64-bit IORVBAR aperture: firmware setup
writes the image address with lock bit 0, while the wrapper CPU run path uses
the 32-bit register at `reg[0]+0x44`. The same concrete binary proves that the
mailbox-v4 window starts at `reg[0]+0x8000`: control registers are at relative
offsets `0x110` and `0x114`, message items are at `0x800` and `0x830`, and
each item is two complete 64-bit words. The endpoint occupies the low byte of
the second word; status bits 16 and 17 mean full and empty, respectively.
Vinix's common ASC mailbox transport now preserves both 64-bit words instead
of truncating the second word to 32 bits. T6050 lacks `cpu-ctrl-filtered`, so
the base start path permits the concrete run/stop writes. These are register
contracts, not proof that PMP firmware reached RTKit or dashboard readiness;
wrapper `reg[2]` remains unlabeled. Vinix now has a dormant per-die transport
for the proven IORVBAR and run-control resources: it maps only wrapper
registers 0 and 1, verifies the IORVBAR lock after the 64-bit write, and
preserves Apple's two-access stop sequence. Probe does not construct it until
the firmware and RTBuddy owner is complete.

The wrapper firmware path now has an explicit ownership split too. Options
bit 1 bypasses mapping entirely. Otherwise `_hasiBootFirmware()` selects the
iBoot segment walker; that branch does not access IORVBAR, and the observed
PMP records are both skipped as already installed. Only the non-iBoot branch
requires IORVBAR's write-once lock to be set. Vinix's dormant writer now reads
before writing, accepts an already-locked register only when its full value is
an exact idempotent match, and exposes a read-only lock/run-state snapshot for
the eventual hardware admission sequence.

The same recovery now follows the preloaded PMP image through its mapper
boundary. The signed DeviceTree binds each PMP wrapper to mapper 0 of a
die-local `dart,t8110`; the two DART register pairs are separated by the T6050
die stride, use 16 KiB pages, and advertise active SIDs 0, 1, 2, 5, 6, 7, 8,
and 9. Six empty per-SID booleans (`bypass-2`, `-5`, `-6`, `-7`, `-8`, and
`-9`) leave SIDs 0 and 1 translated. The UUID-pinned AppleT8110DART image
proves that mapper index 0 selects a DART hardware instance rather than a SID,
formats those properties as `bypass-${SID}`, and records them in its bypass
bitset. UUID-pinned AppleA7IOP code inserts only 32-byte records whose flag bit
1 is clear. Both live PMP records have that bit set, so Apple deliberately
preserves their iBoot-installed translations rather than inserting them again.
The matching IODARTFamily image proves that a non-skipped direction 1 becomes
read-only protection 2 and direction 3 becomes read/write protection 3.
AppleT8110DART's ordinary full-page path passes exactly one 40-byte protected
mapping segment; its internal value 3 is the protection, not a segment count.
Partial byte ranges are also handed to the kernel PPL/SPTM mapper. Together
with the matching kernel entry this pins 16 KiB page conversion, four table
levels, valid bit 0, and T8110 physical-address decode, but does not disclose
the protected subpage encoder. This is sufficient to reject an old
T8020-style DART implementation, but not to take ownership of iBoot's roots or
enable PMP execution.

`recover_g17_abi.py` checks those binaries by UUID and independently recovers
the shared G17 bootstrap pointer offsets from firmware and
`AGXArmFirmware::initFirmwareData`, accelerator-ring layouts, the published
hardware-configuration allocation, host-written table layout and firmware
read map, its fixed address-space prefix, G17 no-op CSC allocation, two static
color-matrix banks, border-color-table stub, and fixed scalar defaults, the
G17C PIO relative-offset table and its 12 primary-aperture
firmware records, their physical alignment and GART-10 UAT publication path,
the primary and SRAM frequency-table sources and conversion and the relative
boost-frequency transfer table, the per-state SRAM power-scale row and zeroed
G17 static-power row, the two die-dependent linear power-transfer tables
and their power-matrix, leakage-bucket and fuse-aperture sources,
the fixed two-bank performance-state map, the native
CS/AFR auxiliary performance-state parser and firmware blocks,
exact per-role bootstrap-root bindings, its copied platform
block, the two root-page CPU/GPU mappings and their prepare/complete lifecycle,
the two-transport boot calls, per-role `0x81` root publication, six-bit AKF
message-type decode, and the one-shot type-9 `0x89` reply to both transports,
plus the version-pinned RTBuddy wrapper's independent `0x20` message and
`0x21` doorbell endpoint binding and role-aware receive forwarding,
the configured work-queue count's device override/fallback path, its expansion
to 1,280 channel command pointers, and the per-command-queue timestamp state's
self GPU address and use as every work channel's context cookie,
the mapped bootstrap register region and its G17 no-op producer, both
shared-object address graphs, the per-role ASC power-state records, the shared
runtime object's control fields and four startup producers, the initial shared
platform scalars/calibration, the fixed render payload's normalized copy map
and cross-field validation, and the UAT handoff initialization using a
deliberately small AArch64 decoder.
These tools write under the ignored `build/` directory; Apple binaries and
trace data are never repository inputs.

## Current M5 Max boundary

The inspected Mac17,6 identifies its GPU as `gpu,t6050` and uses
`AGXAcceleratorG17X` / `AGXMetalG17X`. The published configuration is G17C,
40 cores, four GPU partitions, 40 fragment units, 16 geometry processors, and
USC generation 3. Vinix now recognizes that topology.

See [G17_T6050.md](G17_T6050.md) for the versioned register, user-client, and
firmware observations recovered during this pass.

Hardware launch remains gated at the whole-ABI boundary. The narrower hardware
configuration gate is derived rather than asserted:
`fw.g17_hardware_config_gaps()` now reaches zero only because every field has a
producer, and `init_g17_firmware_data` still fails closed if that changes.
Vinix now has the native G17 UAT handoff,
two-role bootstrap roots, mapped allocation graph, firmware-only MMIO mappings,
separate GFX/GFX1 ASC and RTKit ownership, and the guarded dual-role root/ready
handshake. The eight-entry t6050 interrupt topology now selects Apple's
callback source 4, and Vinix can drain both validated 256-entry firmware event
rings, preserve all three effective host no-op event types, consume the
optional type-8 reliability and type-14 RT/CLPC observer notifications, and
translate the type-1 128-slot firing mask into fence-completion scans. It also
validates and consumes type-10 IOSurface shared-event completions because Vinix
has no IOSurface registry or producer for those Apple-only commands. The
recovered portions of its shared/runtime objects include their initial platform
values and runtime policy. The work-command ABI and userspace command producer
still need byte-accurate implementations before enabling T6050. The hardware
configuration is now complete, including the two die-dependent power rows.
Their three-word eFuse input is decoded in integer quarter-units and combined
with version-pinned Q24.40 leakage factors; integer binary32 helpers reproduce
Apple's rounding points without emitting kernel floating-point instructions.

The channel-command pools are recovered: the slot-ring block layout, capacity
selection, page-rounded backing geometry, allocation scan, and exact byte size
of all twelve named command types.
The four common packed fields written by `submitNopUnprepared` are also pinned
and have a template-preserving Vinix encoder. The 3D descriptor completion
path now pins address-to-slot reclamation back to the 3D pool and Vinix has a
checked equivalent.
The 3D command's register-list layout is recovered: four passes on a 0x720
stride, 0x700 stream bytes each, the 12-byte entry format, and the descriptor
summary array. The selector encoding is recovered and validated, but the selector sets are
not complete yet. The UUID-pinned backwards slice resolves every virtual encoder
call (314 physical call sites and 234 distinct static selectors together with the
literal audit). All ten inline forms are located too; two CL selectors remain
symbolic, while their value formulas are complete. Value provenance is
classified at every virtual call (209 constants
or direct descriptor loads plus 105 recovered expression trees), so all 314
call-value formulas are now represented. A complete machine-level emission CFG
also records possible ordering for all 324 virtual and inline sites, and all 21
ordering predicates have expression trees. The two runtime CL selectors keep
the finite static set open, but every selector formula is complete.
Channel and scheduler-state construction no longer needs unknown inputs: the
per-queue timestamp and `_AGFISchedulerState` elements, the 80-unit/1,280-entry
channel ring geometry, the creating process ID and the app GPU role are all
recovered and now have capability-specific, cache-correct DRM queue ownership
with reverse-order unwind. What remains for submission is porting the complete
register emission graph into the work-command encoder, implementing the four
remaining callback error/control event actions, and work-command reclamation.
The first parser-to-descriptor bridge is executable: the recovery pins the
retained render payload's `+0x2d0` common record, all 49 scatter-copy ranges,
eight masked flags, and the independently allocated `0xc40` base prefix; the
kernel applies that map only to staged, bounds-checked buffers. The selected
render object is the `0x15b0` `AGXTACommandDescriptor` subclass. The same
recovery pins its derived-to-base initialization chain and 17 unique nonzero
scalar defaults, which the kernel installs without copying Apple's host C++
object pointers or embedded synchronization state.
Boolean accounting is explicit in the generated JSON: the common helper has
eight one-to-one mask chains. Two parser-only masked fields occupy the same raw
record, making ten distinct raw sources if both stages are combined; a count
of nine is rejected as unsupported.
The adjacent straight-line TA passthrough is executable too: 33 direct copy
ranges and 23 masked flags span the selected object's base prefix and derived
tail through `+0x15a8`, with all source and destination bounds pinned to the
Apple binary. Resource-derived and computed fields still need native Vinix
producers before the descriptor can drive hardware submission.
The following normalized-command bridge is executable as well: eight direct
descriptor writes and one conditional device-bit write are recovered with
their raw-payload provenance. The fallback device bit is also traced through
the retained accelerator pointer to its explicit zero initializer. Its
nine-write total is reported as a separate stage and cannot be confused with
the common helper's eight masks.

`generate_g17_power_model.py` evaluates the fixed-temperature four-`pow`
leakage factor from the pinned AGXG17X binary for every voltage in this
Mac17,6 DeviceTree. `make check-g17-power-model` verifies that the committed
kernel tables match both local inputs.
