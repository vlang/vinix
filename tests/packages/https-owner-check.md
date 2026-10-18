# Owned complete HTTPS acquisition

HTTPS acquisition now builds curl arguments from borrowed stack lists into one
owned request buffer. Appending the resume pair and URL previously left their
temporary V arrays allocated. Range fallback also retires its constructed label
and message. TLS/redirect policy, argument order, size/time limits, captured
output and the two-attempt bound are unchanged. The public transport still uses
the fixed `/usr/bin/curl`; private producer injection is only an in-process test
option and is not exposed through configuration, CLI or environment.

The [process fixture](../../tools/packages/pkgcore/https_owner_test.v) measures
64 complete calls after two warmups in each of 57 cases: **3,648 measured calls**.
Tracking starts after output/reset preparation and ends after error disposal.
Fresh/resumed success, Range fallback, empty responses, truncation, excessive
output, process failure, signal termination and missing executable cases accompany
offline/insecure/NUL refusals, oversized prefixes and special destinations.
Checkpoint and progress callbacks replace or grow the destination; flush checks
cover interruption, storage failure and added hard links. Foreign bytes remain
unchanged, child processes are reaped and repeated requests run with a
32-descriptor limit.

The paired original-source fixture measures two calls per case. Fresh transfers
retained 158 tracked bytes, resumed transfers 316, and resumed Range fallback
626. Both versions use the same fixture, including allocation-free callback
renames, so the measurement excludes deliberate test mutation overhead. Original
sources, executable, generated C and raw output are pinned.

The [live TLS fixture](https-owner-live.v) uses the production public fetch,
refresh and transaction APIs against the existing local OpenSSL repository.
It measures 64 calls after two warmups in 37 cases: **2,368 measured calls**.
Nine direct-fetch cases accompany signed refresh and install cases for both
architecture declarations. Fresh/resumed and Range fallback transfers, invalid
resumed prefixes, truncated responses, corrupt fresh fallback, HTTP refusal,
insecure redirect, untrusted certificate, hostname mismatch, oversized replies
and bad repository signatures have exact request counts and retained-state
assertions. Refused refresh preserves cache/history bytes; refused installation
leaves no active or published generation and retires its stage. Successful
requests close their independent replies before tracking ends.

A temporary CA bundle is passed to the dedicated controller child; no system
trust is changed. A planted `insecure` curlrc must be ignored. Server diagnostics
inherit the controller's drained output so repeated TLS refusals cannot fill a
separate pipe. The controller kills and reaps its server at completion.

The [host driver](https-owner-check.v) performs 22 fresh compile/run checks:
the process fixture with/without tracking and ASan/UBSan; ordinary/sanitized
output, status, callback and descriptor regressions; signed local recovery;
the existing real TLS and destination probes; and normal/sanitized tracked live
TLS repetition. Fallback and automatic compiler error reporting are disabled.

```sh
v -nocache -o /tmp/https-owner tests/packages/https-owner-check.v
V=/path/to/reviewed/v /tmp/https-owner /build/new-https-owner
```

The [native controller](https-owner-runtime-check.v) runs all 57 process cases
and the existing diagnostics/output suite on both targets using the V producer.
The parent checks file reservations after each child against one fixed initial
baseline plus 128 KiB, allowing at most 30 one-second waits outside measured
calls. The kernels are pinned prebuilt inputs; QEMU TCG has a 1,200-second
deadline. Real TLS repetition is host-qualified; these guests qualify the shared
process, pipe, argument, output-guard and recovery paths.

Qualification passed on 2026-10-18 with the frozen V 0.5.2 compiler at
`826e96f`, SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.

| Run | Result | Duration |
| --- | --- | --- |
| Host compile/run checks | 22 passed, including ASan/UBSan | 1,118.439 s total checks |
| AArch64 native process/output | 57 ownership cases and existing controls passed | 355.1 s |
| x86-64 native process/output | 57 ownership cases and existing controls passed | 460.7 s |

Every tracked process case retained zero bytes across 64 calls on the host and
both native targets. Every live TLS case retained zero bytes across 64 calls in
ordinary and sanitized host runs. Each guest used one initial file reservation
baseline of 2,048 bytes and a fixed ceiling of 133,120 bytes; both observations
stayed below the ceiling, with at most six waits.

Retained evidence includes the [host summary](results/2026-10-18/https-owner-host.txt)
and [command receipt](results/2026-10-18/https-owner-host.json),
[original-source measurements](results/2026-10-18/https-owner-baseline.txt),
[tracked process output](results/2026-10-18/https-owner-owner-tracked-run.txt),
[sanitized process output](results/2026-10-18/https-owner-owner-sanitize-run.txt),
[live TLS output](results/2026-10-18/https-owner-live-run.txt),
[sanitized live TLS output](results/2026-10-18/https-owner-live-sanitize-run.txt),
and raw [AArch64](results/2026-10-18/https-owner-aarch64.serial.txt) and
[x86-64](results/2026-10-18/https-owner-x86_64.serial.txt) serial logs.
The [hash ledger](results/2026-10-18/https-owner-ledger.json) pins source,
compiler, generated C, executables, kernels and evidence. The
[retainer](https-owner-retain.v) requires all process/live labels, output controls
and reservation checks; run it with `--verify` while the pinned build artifacts
remain available to recheck the hashes.

Measurements cover the parent's scoped V allocations, including complete public
request and reply/error retirement for live cases. They do not measure
curl/OpenSSL process memory or kernel heap usage. Guest TLS, public
repositories/proxy fleets, production catalog migration and broader
graphical/runtime acceptance remain separate; section 14 stays open.
