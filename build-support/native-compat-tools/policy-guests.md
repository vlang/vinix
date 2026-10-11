# Native resource-group and speculation tooling

Two Python runners are replaced with direct V commands:

```sh
tests/resource-groups/run --arch aarch64|x86_64 [--kernel-dir DIR] [--state-dir DIR] [--timeout SECONDS] [--memory MIB] [--smp N] [--build-only]
tests/speculation-policy/run [--host-arch arm64|amd64] [--state-dir FRESH-DIR] [--original-reference C]
tests/speculation-policy/run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR --guest-state-dir DIR [--build-only]
```

Resource groups retains the unchanged C guest, exact compiler/linker recipe,
serial fixture, four CPUs, 1,024 MiB and 240-second default. Its evidence
directory remains reusable and retained, including on failure. Each invocation
recreates only its own sparse 256 MiB swap disk. The full 4 KiB Linux version-one
header has the original little-endian values, reserved zero bytes and
`SWAPSPACE2` signature. Receipts record compiler arguments, source, executable,
kernel and archive hashes, header hash, disk size and launch settings.

The native ARM launcher registers swap after the ISO: the prepared kernel
discovers VirtIO MMIO slots in reverse registration order. A read-only V guest
verified that `/dev/vda`, which the unchanged fixture selects, is the 256 MiB
swap image with the correct header; `/dev/vdb` is the ISO. The x86 diagnostic
verified the same swap header on `/dev/sd0`. Diagnostic launches use QEMU
snapshots, and the diagnostic guest opens the devices only for reading. x86
retains the IDE disk and VirtIO RNG. Both architectures use the qualified
native guest supervisor, original pass/failure markers and disabled networking.

Speculation copies the exact production V policy into its isolated module,
retaining the mocked privileged instructions, freestanding flags, genuine
header and allocator-import rejection. The original independent C control can
be built alongside the V fixture; exit status and both output streams must
match. Host success requires exactly `SPECULATION POLICY PASS (6144 cases)`
plus a newline, exit zero and no ASan/UBSan/LeakSanitizer diagnostic. Both
sanitized programs keep the 180-second deadline; the native capture owns both
pipes and kills and reaps on timeout. macOS uses `detect_leaks=0` because its
runtime does not support LeakSanitizer; no LeakSanitizer claim is made. Other
hosts retain `detect_leaks=1`. Native guests keep the 3,600-second budget,
prebuilt executable, serial fixture and original assertion marker. Private
host workspaces retire on every exit; explicit fresh evidence is retained.

`check-policy-guests.v CONTROLLER PROFILE CACHE` checks both actual targets
for each runner, exact resource-group recipes, byte-identical recipe replays,
ELF architecture, kernel snapshots, swap size/header and both host architectures'
independent C/V sanitizer outputs. `--fronts` cold-builds both public commands
outside the checkout. `--disks CACHE` runs the read-only disk diagnostic.
The native unit checks cover complete swap-header bytes and size bounds,
device registration, untouched input arguments, exact oracle output/status and
sanitizer failures.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan controllers pass the cross-build,
recipe, host oracle and unit checks; the final ARM disk-order correction also
passes the targeted unit checks on all three hosts. Real ARM and x86
speculation guests pass all 6,144 cases. They test the mocked policy, not
hardware mitigation effectiveness.

The real ARM resource-group guest reaches its unchanged final retention check
after passing swap, CPU, I/O, hierarchy, pressure and limit checks, then reports
`CGROUP SLAB size=96 delta=6400` and fails at line 406. The prepared x86 kernel
fails the unchanged cgroup mount at line 418 with `errno=38`. These failures
remain failures; the assertions and deadlines are unchanged. No kernel source
was changed or rebuilt for this port.

Evidence is retained under
`/Users/alex/.cache/vinix-python-zero-process-20261011`. Prepared kernel SHA-256
values remain ARM
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`
and x86 `38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`.
The originals total 12,528 bytes / 229 lines. No source is hidden, language
attributes changed or Python executed.
