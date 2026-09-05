# AGX reverse-engineering tools

This directory contains read-only host tools used to replace guesses in the
Vinix AGX driver with observations from Apple hardware and software. It does
not contain or redistribute Apple firmware, kernel collections, or drivers.

`inspect_macos.py` collects a sanitized JSON hardware manifest from the `sgx`
Apple DeviceTree node, the active AGX accelerator, and the installed driver
Info.plist:

```sh
./inspect_macos.py
python3 -m unittest -v test_inspect_macos.py
```

Apple DeviceTree numeric data exposed by `ioreg -a` is native little-endian.
The Vinix flattened-device-tree parser, in contrast, correctly treats FDT
cells as big-endian. Keep that distinction when moving observed values into
the kernel.

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
initial-status callback has no such local wait. The ordinary request/ack
report also pins the AGX mask, `newData` metadata bit, state-match condition,
15-second fatal timeout, and its single persistent request write. The same
ApplePMGR check recovers the asymmetric ApplePTD read and write windows and
metadata transform. A UUID-pinned AppleT6050PMGR check proves that PTD RegMap
enum 8 maps to DeviceTree `reg[7]` once per die; the live DeviceTree resolves
that Device aperture to `0x84240000` and `0x4084240000`. It also proves both
PMP nubs have identical device/range tables, pins their die-strided shared
regions, and records the requested-die selection used by ordinary state
commands. A separate UUID-pinned
ApplePMP check recovers the
PMPv2 64-bit mailbox classes and proves that PM subtype 1 is specifically a
ping completion: it clears and wakes the ping's in-flight byte. The generated
report labels that result as neither global PMP nor AGX-dashboard readiness,
and likewise keeps ApplePMP's diagnostic `pmptool-config` writer separate
from ApplePMGR's device-state request. The report separates the SoC-device ID,
record index, dense virtual-state index, and SOC-DEV-PKT bit slice; those
values are not interchangeable. Its sanitized JSON report is written under
`build/`; raw Apple DeviceTree or executable bytes are never repository
inputs.
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
