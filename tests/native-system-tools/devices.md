# Native storage, sound and PCI controllers

The maintained commands below compile and run V directly. Their guest workloads
and assertions stay unchanged. None runs a Python wrapper or object bridge.

| Command | Workload |
| --- | --- |
| `tests/block-storage/run` | Production AHCI/NVMe/VirtIO host fault models |
| `tests/fsync-scope/run` | Writable-advertised NBD rejecting writes; unrelated tmpfs sync isolation |
| `tests/virtio-ro/run` | Read-only mounts, shared-map/cache eviction, aliases and raw write rejection |
| `tests/dota2/export-run` | Package byte ranges through ARM guest pread and mmap |
| `tests/dota2/export-test` | Independent sparse ext2 and NBD host controls |
| `tests/sound/run_vm` | Original sound guest, WAV parsing, frequency/duration/dropout checks |
| `tests/pci-config/arm_vm` | Frozen boot inputs, strict ARM fixture, serial observation and retirement |
| `tools/dota2/ext2-export` | Metadata-only sparse ext2 builder and loopback NBD server |

The ext2 builder merges overlays, preserves links and modes, supplies indirect
blocks and superblock backups, and refuses oversized files and state beneath
an exported root. Source identities are checked before and after each read;
only device-number changes are tolerated. Files are opened read-only, without
following replacement symlinks. Its descriptor cache retains at most 64 files.
The server joins all workers before closing the export, preserves idle
transmission after negotiation, and rejects WRITE/TRIM/WRITE_ZEROES. The fsync
fixture alone advertises writable storage while retaining write rejection.

Storage boot media uses PCI and declares NBD before the unused MMIO disk,
preserving the original guest device names despite reversed MMIO slot probing.
The original failure prefixes include `FAIL:`; the fsync checkpoint
`FAILING-DISK-CONFIRMED` remains a success checkpoint. The 240-second storage,
300-second sound and 120-second PCI default deadlines remain. PCI requires
one second of settled markers, checks the final serial drain, and keeps its
five-second shutdown grace. The shared logged-child owner retains its existing
ten-second default and now reports the actual status after a forced reap.

Qualification on 2026-10-11 covers ARM, Rosetta x86 and ARM ASan/UBSan hosts.
All six command binaries, the block runner and two checkers build cold on each
profile. Independent host and complete CLI checks pass on all three profiles.
The CLI checks compile the unchanged payloads with the strict ARM SDK, exercise
real NBD negotiation/write rejection, immutable host hashes, guest failures,
WAV verdicts, PCI early exits, late/final-drain failure, deadlines, ignored TERM,
forced KILL and observer interruption. Extracted production driver fixtures pass
on all three profiles, including sanitizer builds. All eight public entrypoints
also pass cold compilation and help or their full fixture checks.

Real frozen-kernel ARM QEMU guests pass fsync isolation, the complete read-only
VirtIO workload, package range checks, sound guest/WAV checks and default PCI
Linux ABI startup. Package qualification uses a generated sparse 130 MiB VPK
fixture, with direct, single/double-indirect and 128 MiB boundary samples; it
does not establish commercial Dota gameplay. PCI opt-in kernel fixtures and
native SMP are not established by the default boot. No kernel was rebuilt and
no Python was run. The selected kernel SHA-256 is
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`.

Nine Python entry/binding files are retired (44,662 original bytes / 1,043
lines). The older exporter adapter remains for the unported game controller.
Historical borrowed-object query sources remain outside these maintained
commands. Local original hashes, build/check logs and guest receipts are under
`/Users/alex/.cache/vinix-python-zero-process-20261011/device-*`; private RAM
scratch avoids the shared host's disk pressure. Completed boot artifacts are
hashed before retirement. Initial disk-space failures and the two corrected
controller mismatches remain recorded alongside the final passing runs.
