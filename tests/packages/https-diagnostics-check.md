# Actionable HTTPS acquisition failures

HTTPS failures previously returned `download failed (N)` with a generic retained
partial-data message. curl's stderr could explain the cause to a CLI user, but
an administrator-service caller could receive only the exception text. The
service now adds an explanation and a relevant next step using the local exit
status. The status prefix and repository URL remain available.

The classifications follow [curl's documented exit statuses](https://curl.se/docs/manpage.html#exit-codes).
They distinguish repository/proxy DNS, connection failure, timeout, interruption,
HTTP refusal, invalid URLs/redirects, unavailable transport features, TLS
handshake/identity/client-certificate/CA-bundle errors, response-size limits and
resource/tool failures. Unknown statuses retain their number and general
diagnostic guidance. HTTP error 22 does not identify a specific HTTP status, so
the service does not claim a 403, 404 or authentication failure from that code.

No server text is parsed for classification. curl stderr keeps its existing
stream; no transport executable override is exposed to users. Verification,
signed bounds, captured output, transaction activation and retries retain their
existing rules. In particular, only resumed byte-range refusal triggers the
one immediate fresh fallback. TLS/access/timeout/interruption failures retain
bounded partial data for a later command. Fresh truncation still waits for
body bytes or successful empty EOF.

The [output suite](../../tools/packages/pkgcore/https_output_test.v) checks
41 process exit statuses with both fresh and resumed acquisition, actual
signal termination, prefix preservation, request counts and child reaping.
The existing 72 checkpoint/progress substitutions and 96 flush-failure cycles
continue to check captured identity, retained recovery bytes and retirement
under a 32-descriptor limit. A focused scope constructs and closes messages and
errors for 43 statuses over 1,000 measured cycles.

The [real TLS suite](https-check.v) now requires useful explanations for
untrusted CAs, hostname mismatch, HTTP refusal, blocked insecure redirects,
declared oversized replies and interrupted responses. It still checks signed
install/remove/reinstall, Range fallback, checksums, unchanged activation after
failure, resumed retry and rollback. The destination probe and local signed
download-recovery suite remain part of the host qualification.

Run the [host driver](https-diagnostics-check.v):

```sh
v -nocache -o /tmp/https-diagnostics-check tests/packages/https-diagnostics-check.v
V=/path/to/reviewed/v /tmp/https-diagnostics-check /build/new-https-diagnostics
```

It retains commands, timings and source/compiler/artifact hashes for twelve
compile/run checks: producer, ordinary/sanitized output tests, local recovery,
TLS server/client and destination probe. OpenSSL development libraries/CLI and
the fixed `/usr/bin/curl` are required. ASan leak detection is disabled; explicit
allocation measurements cover error construction/close, rather than all service
and test-process allocations.

The [native controller](https-diagnostics-runtime-check.v) runs the same output
suite and V producer on both targets through the hardware harness. These target
checks qualify local process statuses, diagnostics, captured bytes and recovery;
real TLS is host-qualified. No guest TLS stack, public repository, proxy fleet,
graphical acceptance or physical power-cut qualification is implied. Roadmap
section 14 remains open for production catalog migration and broader runtime
and graphical release gates.

## Recorded results, 2026-10-18

All **twelve host checks passed**, including clang ASan/UBSan, real TLS/Range
and destination probes, signed local recovery and the complete output suite.
The error construction/close scope retained zero tracked bytes over 1,000
measured cycles across 43 statuses, in ordinary and sanitized runs.

| Native target | Result | Guest time | Evidence |
| --- | --- | --- | --- |
| aarch64 | PASS | 83.3 s | [report](results/2026-10-18/https-diagnostics-aarch64.txt), [serial](results/2026-10-18/https-diagnostics-aarch64.serial.txt) |
| x86_64 | PASS | 90.0 s | [report](results/2026-10-18/https-diagnostics-x86_64.txt), [serial](results/2026-10-18/https-diagnostics-x86_64.serial.txt) |

Both guests checked message ownership, exit-status and signal handling, prefix
preservation, bounded retries and the existing output guards. They reused the
pinned prebuilt kernels and V plain-USTAR adapter for x86_64 legacy boot media.
The compiler is frozen V 0.5.2 `826e96f`, with fallback and automatic compiler
error reporting disabled. Kernel and production boot-media code were unchanged.

The [host receipt](results/2026-10-18/https-diagnostics-host.json) and
[summary](results/2026-10-18/https-diagnostics-host.txt) retain commands, timings
and output. The [retainer](https-diagnostics-retain.v) binds local source,
compiler, artifact and raw-evidence hashes in the
[ledger](results/2026-10-18/https-diagnostics-ledger.json); `--verify` checks
those hashes while the local files remain available.
