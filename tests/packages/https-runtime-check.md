# HTTPS acquisition inside Vinix

The [V controller](https-runtime-check.v) boots both architectures with real
target curl at the production `/usr/bin/curl` path and its complete shared-library
closure. Each ELF is checked for the selected architecture by the guest builder.
The controller records the original input paths and hashes; it neither substitutes
a producer nor adds a transport override. The guest prints curl/OpenSSL versions.

A fresh local signed repository is served on host loopback. QEMU user networking
connects the guest to that listener through `10.0.2.2`; no public server or host
network configuration is needed. A temporary certificate admits that IP, while
an independently generated CA and a wrong hostname test refusal. Only dedicated
test processes receive the CA bundle. A planted `insecure` curlrc must be ignored.
The controller stops and reaps its server when qualification ends or fails.

The [shared case list](tlsruntime/fixture.v) has 23 cases. The
[target probe](https-runtime-probe.v) measures eight complete cycles after two
warmups in each case: **200 measured API calls per guest**, including the two
interrupted-transfer retries in every cycle. Direct fetch covers
fresh/resumed bytes, ignored Range, interruption, HTTP refusal, insecure redirect,
untrusted certificates, hostname mismatch and excessive declared size. Signed
refresh covers success, certificate/hostname refusal and a bad signature.
Installation covers fresh/resumed bytes, Range fallback, damaged prefixes,
truncation, HTTP/redirect refusal, corrupt fresh fallback and certificate/hostname
refusal. Each guest uses its actual architecture declaration.

Successful requests return exact authenticated payloads and independently closed
replies. Failed refresh retains the exact cache and replay-history bytes; failed
installation leaves no active or published generation or staging directory.
Interrupted transfers retain the exact 1,536-byte prefix; a second call resumes
those bytes to the complete payload and, for installation, activates it.
Corrupt fresh fallback removes
its part and makes no third attempt. The server log checks exact per-case request
counts, including zero HTTP requests after certificate refusals and exactly two
object requests for recovery. The server tags setup requests separately.

Tracking covers parent V request/reply/error storage, with setup, environment
changes and persistent-state assertions outside each scope. Every call must
already have reaped its curl child. Each case runs in its own process and retires
test state before exit. The guest parent checks creator file reservations after
every case against one initial baseline plus 128 KiB, with at most thirty waits.
These are reservation checks, not kernel heap or curl/OpenSSL memory measurements.

The same probe also runs every case on the host, ordinarily and with clang
ASan/UBSan, leak detection disabled and undefined behavior fatal. The controller
pins its inputs before running and verifies them again before writing a receipt.
The compiler executable and library sources are pinned, and `VEXE` is set to
that executable. Compiler fallback and automatic error reporting are disabled.

The first complete installation measurement exposed a 144-byte retained `State`
copy per call in root planning. The compiler promoted the parent of a nested
array clone to the heap. `clone_root_ids` now clones a borrowed array header
synchronously; generated C keeps the parent on the stack. The existing
[1,000-cycle planning regression](results/2026-10-22/https-runtime-root-planning.txt)
covers install, remove, upgrade, deployment and refusal paths with zero retained
tracked bytes and unchanged borrowed inputs. The new lifetime was independently
reviewed.

```sh
v -nocache -no-skip-unused -cc clang \
  -path '@vlib|@vmodules|.|tools/accounts|tests/packages|tests/hardware-platform' \
  -o /tmp/https-runtime tests/packages/https-runtime-check.v
V=/path/to/reviewed/v /tmp/https-runtime host /build/new-host-work
V=/path/to/reviewed/v /tmp/https-runtime aarch64 /path/to/aarch64/root \
  --arch aarch64 --kernel /path/to/kernel --state-dir /build/new-arm-work
V=/path/to/reviewed/v /tmp/https-runtime x86_64 /path/to/x86_64/root \
  --arch x86_64 --kernel /path/to/kernel --state-dir /build/new-x86-work
```

The kernel is a pinned prebuilt input. QEMU TCG has a 1,200-second deadline. The
[host receipt](results/2026-10-22/https-runtime-host.json),
[AArch64 receipt](results/2026-10-22/https-runtime-aarch64.json) and
[x86-64 receipt](results/2026-10-22/https-runtime-x86_64.json) record the checks and
their original input paths. Raw serial output and exact request logs accompany
the [hash ledger](results/2026-10-22/https-runtime-ledger.json). The
[retainer](https-runtime-retain.v) saves command receipts, request logs and raw
serial output, requires all cases and settled reservations, and supports
`--verify` while the pinned artifacts remain available.

Later account, authenticated X11 and ELF dependency changes advanced fifteen original tool
source paths. Their
[content-addressed historical copies](results/2026-10-22/https-runtime-inputs/README.md)
preserve the exact qualified bytes without changing any original run receipt.
The retainer permits this fallback only beneath `tools/` with exact recorded
digests. The [historical-input controls](results/2026-10-22/https-runtime-input-check.txt)
admit three exact cases and refuse seven missing, corrupt, out-of-scope or
malformed alternatives. These copies preserve the historical run; they do not
qualify later tool code.

The [evidence controls](https-runtime-evidence-check.v) exercise the actual
retainer with five admitted boundaries and 29 refusals, including missing or
duplicate cases, unsettled/excessive reservations, retained allocations,
malformed versions, extra requests and wrong retry offsets. Their
[retained report](results/2026-10-22/https-runtime-evidence-check.txt) records all
34 controls. Admission uses explicit errors so `-prod` cannot remove the checks.
Both normal and `-prod` retainer builds passed all 44 evidence and historical-input
controls; the [retainer report](results/2026-10-22/https-runtime-retainer-modes.txt)
records the commands, source/compiler/binary hashes and exact outputs. The control
drivers also use explicit errors. Their [build-mode qualification](https-runtime-control-modes.v)
runs all four driver/retainer build combinations: 176 real controls plus 20
refusals for dishonest children, missing completion markers and invalid arguments.
The [driver report](results/2026-10-22/https-runtime-control-modes.txt) pins sources,
compiler and binaries, checks inputs again afterward, and requires refused suites
to publish no report. Run from the repository root with a new work directory:

```sh
v -cc clang -nocache -gc none -manualfree \
  -o /tmp/tls-control-modes tests/packages/https-runtime-control-modes.v
/tmp/tls-control-modes /absolute/path/to/v /absolute/path/to/clang \
  /tmp/tls-control-work /tmp/tls-control-modes.txt
```

The [failure cleanup check](https-runtime-cleanup-check.v) injects
a failed child command into the original controller after server readiness and
requires a stopped, reaped server and no success receipt. Its
[report](results/2026-10-22/https-runtime-cleanup-check.txt) pins the original
controller and compiler.

This qualifies a local TLS repository on both native targets. Public repositories,
proxy fleets, production publisher/catalog migration, graphical login and broader
installed-system/application acceptance remain open in roadmap section 14.
