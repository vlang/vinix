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
