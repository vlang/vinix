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

The metadata-only IOKit tracer records which external-method selectors and
buffer sizes Apple's Metal driver uses while rendering an off-screen triangle.
It does not dump command buffers or memory contents.

```sh
make -f GNUmakefile test
make -f GNUmakefile inspect
make -f GNUmakefile trace
```

The trace is written to `build/agx_trace.jsonl`. Set `AGX_TRACE_ALL=1` only if
calls on non-GPU IOKit connections are also relevant. By default only sizes
are recorded. `AGX_TRACE_BYTES=256 make -f GNUmakefile trace` also records a
capped hexadecimal prefix of each input/output buffer for ABI analysis; those
traces may contain process-specific addresses and should not be committed.
Selectors `0x100` through `0x112` are annotated with names recovered from the
local `AGXDeviceUserClient::getTargetAndMethodForIndex` table.

## Current M5 Max boundary

The inspected Mac17,6 identifies its GPU as `gpu,t6050` and uses
`AGXAcceleratorG17X` / `AGXMetalG17X`. The published configuration is G17C,
40 cores, four GPU partitions, 40 fragment units, 16 geometry processors, and
USC generation 3. Vinix now recognizes that topology.

See [G17_T6050.md](G17_T6050.md) for the versioned register, user-client, and
firmware observations recovered during this pass.

Hardware launch remains gated because Vinix currently implements only the
macOS 12.3-era G13 firmware structures. Before enabling T6050 writes, the G17
firmware InitData, RTKit endpoints, channel layouts, UAT/DART format, power
handoff, and work-command ABI all need byte-accurate implementations.
