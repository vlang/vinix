# Native game capture and screenshot tooling

`run` and `run-test` compile V directly. `nativehost` prepares the private game
root and owns the read-only NBD export; `guesthost` owns QEMU, serial capture,
deadlines and cleanup. `desktop/tools/screenshot.sh` now invokes native V,
encoding PNG and copying PPM without Pillow. Additional image formats use
ImageMagick. `build-support/venus/prepare-qemu` validates and signs a private
KekVM bottle through V. Seven Python entrypoints and bindings are retired:
40,602 original bytes / 1,030 lines. The screenshot shell's inline Python is
also retired, without counting it as a Python file.

Preparation preserves cached runtime refresh, software GL drivers, actual Valve
ELF validation, optional Vulkan query removal, dependency closure, translator
overlays, repeatable environment/preload/game arguments and pinned kernel bytes.
The Wine host and mapping probe are generated through V. Native compiler,
readelf, sysroot and userland overrides permit isolated guest SDKs. Invalid
arguments return 2; missing source files return 1 before creating the work tree.

Capture retains the first 30-second screenshot, configurable later intervals,
failure markers, two-second failure settling, final screenshot and process-group
retirement. An observed failure returns 1. A capture awaiting review returns 2;
`rendering_verified` remains false. Export diagnostics preserve the original
wire errors and request handles, bound retained failures to 32 and report after
workers join. The optional Venus path owns a stock-QEMU network bridge when
the GPU bottle lacks slirp and requires a prepared host renderer.

## Qualification

Pinned V 0.5.2 (`81be246`) passed 18 cold builds: game runner/test, screenshot
runner/test, existing Dota host checker and QEMU preparer, each on ARM, Rosetta
x86 and ARM ASan/UBSan. All three profiles passed the new and existing host
contracts. These cover read-only installation, source and symlink preservation,
cache refresh, stale helper removal, marker ordering, arbitrary decimal exit
statuses, argument/file-error classification, actual NBD success/EIO replies,
bounded diagnostic snapshots, idle-worker joins and flat descriptor counts.

All six complete controlled failure/capture CLI cases passed. Each prepared
the actual guest SDK payload, checked memory/CPU/read-only NBD/boot arguments,
decoded exact QMP screenshot pixels, inspected the report and retired QEMU.
Full CLI interrupts returned 130 and retired the controlled QEMU child on all
three profiles. An additional ARM Venus model checked its GPU argument and
failed verdict. These models establish controller behavior, not game rendering.

Screenshot tests exchanged QMP through real Unix sockets, including interleaved
events, error replies, EOF, malformed JSON and missing output. PNG/PPM and
uppercase PNG decoded to exact RGB bytes; BMP/GIF/TIFF round trips retained
those pixels, and JPEG retained geometry and its format. Descriptor counts
stayed flat. The game, screenshot and QEMU-preparer public fronts passed cold
compilation/help; shell syntax checks passed.

Synthetic Mach-O cases reject absent/multiple/overflowing symbols, invalid
headers/load commands/segments and unsupported instructions. Real private
KekVM copies prepared and ran `--version` on all three profiles; cached repeats
left the signed copies unchanged. The original bottle's SHA-256 stayed
unchanged. Eight actual stock-QEMU bridges retired their sockets, processes and
descriptors. The prepared renderer itself was not rebuilt.

The original and updated QMP modules passed protocol, event, error/EOF,
malformed reply, large-integer, pointer timing and interrupt checks. The broader
emulator suite fails at its N64 screenshot step with both modules, with the
same `QMP socket closed without a reply` error. That existing fixture failure
is retained; the complete emulator suite is not claimed to pass.

## Actual guest and limits

The native exporter built the real host game's Linux-overlay metadata:
7,055 files / 78,114,717,696 logical bytes, with manifest SHA-256
`c6c26a63dab8b2d64cd0bf6eae7d4a4cf439f4eb6febf407369c3ee1f4494ecf`.
Only game files were exported. No account data was copied.

An actual software-rendering ARM boot used frozen kernel SHA-256
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`.
It observed the game starting, read 106,980,864 export bytes in 8,854 requests
without read errors, and captured the guest through QMP. It correctly reported
`failed`, `VINIX-DOTA2-GAME-GONE` and game exit 139. The captured Dota window
was blank; the log reported `GLX is not supported`. This establishes actual
preparation, launch, reads, capture and failure reporting. It does not establish
game rendering, gameplay, login or a new successful Venus guest run.

Frozen originals, build/host/CLI logs, reports, source receipts and artifact
hashes are under `~/.cache/vinix-python-zero-process-20261011/game-*`.
Initial integration and host disk-space failures remain recorded separately
from corrected qualifying runs. An evidence-copy attempt after a controlled
model reused the guest work directory retained model logs; its three earlier
real screenshots remain identifiable. A second actual boot retained its fresh
logs, report and four reported captures before any further model run. It reached
the capture deadline without a game-start marker, read 3,556,864 bytes in 842
requests without read errors and returned `captured_for_review`, with rendering
unverified. This repeat also provides no successful game result. The qualification cache was
relocated to private RAM after verifying regular-file bytes and symlink targets;
large artifacts retained their original filesystem and inodes. No Python was
run, kernel rebuilt or language attributes changed.
