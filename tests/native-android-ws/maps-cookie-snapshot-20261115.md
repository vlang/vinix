# Canonical browser cookie snapshot path, 2026-11-15

The r110 protected account attempt passed X11 display admission, then the
browser engine exited with status 1. Its retained private log says cannot open
cookie snapshot database. Complete evidence and safe shutdown are recorded in
[the X11 runtime report](maps-x11-rejection-20261115.md). No account authenticated.

On Linux, browsercookies used /proc/self/fd/N/snapshot.sqlite together with
SQLITE_OPEN_NOFOLLOW. SQLite rejects symbolic links in any filename component,
including those intentional proc-fd aliases; see the
[SQLite open contract](https://www.sqlite.org/c3ref/open.html#opennofollow).
The account store already fixed this combination in c318d84f2. The cookie
store now uses the same approach: the canonical absolute path under the
directories already opened without following links and checked for trusted
ownership and protected modes. Only root or the selected application UID can
rename those ancestors. File/sidecar mode, ownership, link count and SQLite's
complete-path NOFOLLOW checks are preserved. No cookie completion is fabricated.

All 15 real-SQLite store cases pass normally and under AddressSanitizer
(detect_leaks=0, halt_on_error=1). The new case reproduces SQLite's refusal of a
directory symlink on every host, verifies canonical-path selection and checks
that the real snapshot remains intact. Existing transactional, restart,
session/attribute, lock-preservation, corruption, bounds, schema and filesystem
refusal cases pass. A separately named typed mkfifo binding avoids a collision
with current V's macOS declaration in the existing special-file test.

## Current-V build and staging tooling

Current compiler: /Users/alex/code/v/v, V 0.5.2 cbfc1be. The engine builder now
uses explicit new-compiler, no-parallel and nocache flags. It compiles each real
host test runner directly and sequentially, avoiding a concurrent vtest compiler
bootstrap; test coverage is retained. Hash buffers and contexts are freed.
Direct C helper sources/headers are copied and checked alongside V sources.
An optional explicit ZLIB_ROOT captures and uses zlib.h, zconf.h and libz.a
needed by the current compiler's cross build. The selected archive is from the
qualified browser-x11-protocol-build-20261115-r1/zlib bundle, not a host library.

The current guest stager accepts VINIX_CURRENT_BROWSER_ENGINE. It requires a
bounded regular AArch64 musl executable with only libc.so needed, no RPATH or
SONAME, and the same interpreter. The original engine and both principal
manifests are streamed from the fresh cloned boot image and verified against
the baseline deployment hashes. Only the engine file digest changes inside
each manifest; helper pins, principal attestation and sandbox policy remain
unchanged. Binary and manifest readbacks update the actual deployment inputs
and per-principal manifest digests. Historical browser bundle identity remains
baseline provenance; current_browser_engine records the override explicitly.
Producer/API/ABI qualification is still required before selecting an engine.

The manifest test passes exact preservation and ten malformed/duplicate/hash
refusals. The host stager compiled under the original caps. Neither a fresh
engine deployment nor ARM qualification of this cookie fix has occurred.

## Retained checks and host blocker

External root: /Users/alex/.local/state/vinix/android. Tools, generated C and
test binaries are under cookie-path-tools-20261115-r1; raw artifacts stay outside
Git. Store run receipts cookie-path-tests-run-20261115-r1 and its ASan counterpart
passed exit/child 0/0, empty reason, complete cleanup: 1384/1434 ms, sampled RSS
6258688/73777152, observed growth 245760/139264 bytes respectively.
The retained checksums for the build/check receipts, logs, selected host tools
and frozen-source inventories are cookie-checksums-20261115-r1.txt, SHA256
05037bb03e1c83e278f9123b7526d1980e12d80bcb030a7dd1292577a26e2691.
Incomplete engine attempts remain incomplete; these checksums do not replace
their missing successful build manifests or qualify them for deployment.

Build limits remain RSS 629145600, wall 300000 ms, reserve 1073741824, shared
growth 536870912 and output 4194304 bytes. Engine attempt r1 hit aggregate RSS
651460608 while bootstrapping vtest. Sequential attempt r2 passed all host
runners, then cross compilation failed for missing zlib.h; its explicit captured
zlib input was added. Attempts r3 and r4 hit observed shared disk growth:

| Engine attempt | Elapsed ms | Peak sampled RSS | Observed growth bytes |
| --- | ---: | ---: | ---: |
| cookie-path-engine-20261115-r3 | 26408 | 340688896 | 554729472 |
| cookie-path-engine-20261115-r4 | 80203 | 349224960 | 548438016 |

Both guards exited 125, child 137, complete cleanup. A short stager generation
also hit shared growth 639057920 in 3494 ms; its later generation retry passed
in 3840 ms, sampled RSS 255737856 and growth 61898752 bytes. Three independent
read-only probes, with no owned guest or build running, each exceeded their
stricter 67108864-byte growth cap:

| Probe receipt | Elapsed ms | Observed growth bytes |
| --- | ---: | ---: |
| cookie-host-quiet-20261115-r1.guard.json | 2227 | 71991296 |
| cookie-host-quiet-20261115-r2.guard.json | 1505 | 69521408 |
| cookie-host-quiet-20261115-r3.guard.json | 2184 | 88571904 |

Each probe exited 125, child 137, complete cleanup. Available space fell from
roughly 43 GiB at continuation start to about 17 GiB. A quiet disk window and
restored space are needed for a fresh full engine build under the retained
caps, followed by API/ABI checks, fresh staging, signed ARM and a protected
account retry. All owned test guests are stopped. Google authentication and
full Maps operation remain unqualified.

## Full engine qualification after continuation

The next read-only probe r4 still observed 250482688 bytes of growth in
6818 ms and stopped under the stricter read-only allowance. Engine attempt r5
completed host tests and cross compilation within the original build allowance,
then correctly failed its API audit: the supplied historical addon directory
was absent, leaving libXtst.so.6 unavailable. The builder now rejects missing
audit directories before starting expensive work.

The V recover-runtime-inputs tool streams the auditor's eight actual libraries
from maps-account.tar in the stopped parent boot image, and verifies every file
against that deployment's recorded digest. Recovery r2 additionally retains the
three deployed musl aliases. No image handles were open before reading the
parent. The historical audit is not weakened and no missing bundle is treated
as complete; these recovered files qualify only the selected API and musl
inputs. Existing runtime admission still checks the complete closure.

Using those exact API inputs, cookie-path-engine-20261115-r6 passed the full
current-V build under the original caps: 29052 ms, sampled peak RSS 346128384,
shared growth 16224256 bytes, exit/child 0/0, empty reason and complete cleanup.
All host runners passed, the AArch64 executable linked, all 99 browser/cookie API
exports were present, all three required VGC root/runtime symbols were present,
and frozen-input readback and the final complete inventory passed.

The separate verify-musl tool reuses the production deployment ABI auditor.
It passed all 136 requested symbols against both the exact link-time musl and
the recovered deployed musl, retaining checked copies of all three ELF inputs.
An intentional engine-as-runtime negative case failed on a missing libc symbol
without creating a successful audit. Recovery, ABI and negative receipts are
retained outside Git; neither tool launches an engine or changes a guest image.

| Qualified evidence | SHA256 |
| --- | --- |
| cookie-path-engine-20261115-r6/webview-engine | 1c160afcfae73a9c1fd58aa736022dbb602a5df08acca6107caa252b08a3cbc9 |
| Same root/build-sha256.json | dd858c2980825b4296452ddaf4e8ce9729bcc4bf4cf39a109a495e69708d0c00 |
| Same root/api-audit.json | b5f100bc447536ed74f825dd5cbeb1b45abe159135e84cf586ce0a0d146b2510 |
| cookie-musl-abi-20261115-r1/audit.json | 0e95286844ddf5afd3ca709f3eeb364aaea65879c226fc4480b2d4d4be9fe0fe |
| cookie-deployed-runtime-20261115-r2/recovery.json | f795c5ee8210cafd7ba8e439fb157d6e81c1f6650d7cba0cf01015d74a2887ff |

Fresh full-profile r111 staging passed under the original caps: 10187 ms,
sampled peak RSS 42385408, observed growth 184459264 bytes, exit/child 0/0,
empty reason and complete cleanup. The copied engine matches the qualified
digest. Both admission manifests and actual deployment inputs were updated;
all other closure hashes and principal assertions were preserved. Signed ARM
and the next protected account retry are pending in this fresh guest.

## r111 ARM pass and interrupted services startup

The complete signed ARM suite passed: child exit 0, readiness pass,
CONTACT-LABELS-PASS and CURRENT-API-PASS. The full public API export was
24007 bytes / 47 chunks and reconstructed without removals.

| ARM evidence | SHA256 |
| --- | --- |
| maps-cookie-api-uart-20261115-r1/full.log | b3647aeae254cc80d67da6d4fbc9441a2f07fb7a79ee0c0c57be67ef48f87d84 |
| maps-cookie-api-readback-20261115-r1/archive.json | 0f6fb57cde62c62a30d94bd6359301421cfb26deafc14257b577bf8af3090f6e |
| maps-cookie-api-child-20261115-r1/child.log | 11567a622b4a9cafc7a4ce702680fb802816d6c9886c3f36d4ace01b89562f84 |

After the checked persistent mount, Google services started, but QEMU60163
disappeared before the protected Maps launch or any Add account interaction.
QMP refused connections, the PID was absent and no image handles remained.
No owned stop had been requested and qemu.log is empty; the cause is unknown.
There is no complete account export or successful broker cleanup claim.

Read-only extraction retained r111-private/current-api-r111 and a partial
storage watch. The persisted API child log compares identical to the verified
public child log. Read-only e2fsck exited 4, reporting block/inode bitmap and
directory-count inconsistencies; the interrupted image was preserved unchanged,
without repair or relaunch. Its checked volume UUID was
e13e04c989fc4a9d90da3eb828c383fb. The retained final app-data.ext2 SHA256 is
6269f8849823d9d74d784f49a5023c5d430ce9ea40f0f8b4502112cbd58acf34
(maps-r111-data-hash-20261115-r1.log/guard receipt).

Fresh r112 staging passed under the original caps: elapsed 5857 ms, sampled
RSS 42303488 and observed growth 178970624 bytes, exit/child 0/0, empty reason,
complete cleanup. Its binaries match r111; the completed signed API evidence
is reused, with no new API-pass claim for r112. The new checked persistent volume
mounted before services startup. Protected account validation is pending.

## r112 kernel fault; guest memory preserved

Services reached `ready-awaiting-user-account-interaction`; the descriptor
snapshot for GMS PID31851 reported 234 descriptors, unavailable 0, non-atomic
true. The protected Maps launch occurred once. Its window stayed black and
no Sign in / Add account action or credential entry occurred.

The kernel then reported `ec=0x25 esr=0x96000007 far=0x60`,
`pc=0xffffffff802e6c94`, `x22=0`, process PID31851 `main`.
The unchanged parent kernel's symbols and disassembly locate this at
`table__syscall_trace_ret`: a load of `current_thread->audit_sequence`
at offset 96 through a null current-thread pointer. The return address
`0xffffffff80309880` is `handle_svc`, vectors.S:406.

The stop request was acknowledged (`controller=673`), but terminals subsequently
stalled. No complete account BEGIN/END export or copied-and-synced private
results were observed. QEMU PID77747 was paused through checked QMP, preserving
RAM and open images. It has **not** been terminated or relaunched; its images
must not be inspected offline while held by QEMU. Account cleanup and complete
private evidence remain unresolved. The signed API evidence remains r111's.

`guest-monitor.v` checks the owned PID command line, QMP socket and pidfile
before querying status or pausing. It confirms the paused acknowledgement
and records both statuses. It has no termination or relaunch operation.
Both current-V C generation and host linking passed the original limits;
the real pause and subsequent status queries passed.

Evidence is retained under `/Users/alex/.local/state/vinix/android/`:

| Retained artifact | SHA256 |
| --- | --- |
| maps-r112-paused-20261115-r1.json | e4b309e5ef88baafb2749f8e713b22d205206c2b03f533aad7a755ddffb3ef9b |
| maps-r112-kernel-20261115-r1/paused-uart.log | e5b23347423c0f8b9d166b5279bc3f74f410713d15ffb070e4f1ea125fe7b23f |
| maps-r112-kernel-20261115-r1/vinix (stopped parent boot image) | a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151 |

The frozen original generated C is retained at
`pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2/source/kernel/obj/blob.c`,
SHA256 d472464b984da437c553e6ec044b43389af46b7b9f565b67a00dca1e76a68077.
A guarded frozen boot-image copy was refused before spawning due to disk
reserve; no actual-r112 offline kernel readback or image comparison is claimed.
Maps, authentication and sustained responsiveness remain unqualified.
