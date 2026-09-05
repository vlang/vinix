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
make -f GNUmakefile kernel-kexts
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
`--walk` instead parses each segment with the record framing recovered from
`AGXHardwareKernelCommand::parseAndValidate`, which is how that framing is
checked against bytes the Metal driver actually produced.
It can also select a shared allocation by an observed JSON field:

```sh
./trace_diff.py build/agx_trace_resources.jsonl \
  --event resource_snapshot \
  --where resource_gpu_address=0x10000138000
```

`objc_layout` records class, method, and ivar metadata exposed by the local
Objective-C runtime. `extract_firmware.py` extracts only the matching G17C
images from the local recovery volume and emits their hashes, Mach-O UUIDs,
and virtual layouts. `extract_fileset.py` unwraps the local IMG4/LZFSE boot
kernel collection and compacts the kernel, AGXG17X, and firmware-buddy fileset
entries
into standalone Mach-Os suitable for `xcrun llvm-nm` and `xcrun llvm-objdump`.
`IOGPUFamily` is included because `AGXCommandQueue` inherits its device
binding, and with it the last two channel inputs, from `IOGPUCommandQueue`.
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
the mapped bootstrap register region and its G17 no-op producer, both
shared-object address graphs, the per-role ASC power-state records, the shared
runtime object's control fields and four startup producers, the initial shared
platform scalars/calibration, and the UAT handoff initialization using a
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
handshake,
and the recovered portions
of its shared/runtime objects, including their initial platform values and
runtime policy. Firmware channel
construction, the work-command ABI, and the userspace command producer still
need byte-accurate implementations before enabling T6050. The hardware
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
call (314 physical call sites and 235 distinct static values together with the
literal audit); manually assembled entries and their control-flow ordering remain.
Channel and scheduler-state construction no longer needs unknown inputs: the
per-queue `_AGFISchedulerState` element, the creating process ID and the app
GPU role are all recovered, so what remains for submission is the work command
format itself.

`generate_g17_power_model.py` evaluates the fixed-temperature four-`pow`
leakage factor from the pinned AGXG17X binary for every voltage in this
Mac17,6 DeviceTree. `make check-g17-power-model` verifies that the committed
kernel tables match both local inputs.
