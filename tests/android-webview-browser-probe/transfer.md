# Browser archive retransmission

`transfer.v` retransmits only the credential-free local browser probe archive.
It does not repair or qualify a damaged UART export, and it provides no Maps
or Google authentication evidence. The original UART parser in `collect.v`
continues to reject interrupted frames. The separate `--browser-tcp` import
uses the existing archive path, type, mode, size, digest and restoration checks.

The stopped `browser-r17-abort-launch-r1` VM lost its temporary archive. Its
original serial stream remains retained, and its rejected export was not
imported. A future run must supply its own BEGIN digest and byte length; old
pins cannot recover the stopped run.

Build the host tools with the default garbage collector and the mandatory nonblocking
socket option. Without that option the sender refuses to run, because V's
blocking socket implementation cannot enforce a stalled send deadline.

```sh
v -d net_nonblocking_sockets -o /external/tools/transfer tests/android-webview-browser-probe/transfer.v
v -d net_nonblocking_sockets -o /external/tools/collect tests/android-webview-browser-probe/collect.v
v -d net_nonblocking_sockets -o /external/tools/transfer-selftest tests/android-webview-browser-probe/transfer-selftest.v
/external/tools/transfer-selftest
/external/tools/collect --self-test
```

Keep an exact frozen serial snapshot from the same run after the browser export
ends, together with the original UART path and its hash. Use the intact unique
`VINIX-BROWSER-RESULTS-1 BEGIN SHA BYTES CHUNKS` line from that snapshot. The
receiver independently checks its digest, length and computed chunk count,
then hashes the entire snapshot before and after the transfer. This check
does not accept or normalize the CHUNK or END frames.

```sh
/external/tools/transfer receive /external/fresh-transfer 39017 SHA BYTES /external/frozen-serial.log
```

Wait for `BROWSER-TCP READY 127.0.0.1:39017`. Run the cross-built sender inside
the same guest while its original archive still exists:

```sh
/opt/vinix-browser-probe/browser-transfer send 39017 SHA BYTES
```

The sender's source is fixed to `/tmp/vinix-browser-probe-results.json` and its
destination to QEMU's host endpoint `10.0.2.2`. The host listens only on
`127.0.0.1`, accepts one connection and enforces a 600-second absolute deadline
including accept, reads and mandatory EOF. The sender has a bounded connect
and a 120-second write deadline. Both sides stream with fixed 64 KiB buffers
and reject changed hashes, wrong lengths and extra bytes. The archive limit is
32 MiB. Source serial snapshots are bounded to 256 MiB. A sender `SENT` line
means only sender completion; the receiver must separately report `PASS`.

Transfer and import output paths must be canonical absolute paths outside Git
checkouts, with an existing canonical parent and a fresh final directory.
The receiver creates its directory with mode 0700 and files with mode 0600,
using exclusive no-follow creation. It retains incomplete bytes as
`archive.partial` on failure and creates no successful receipt. On success it
retains exact `archive.json` bytes and explicit `browser-tcp-v1` provenance in
`transfer.json`. The SHA supplies integrity against the pinned BEGIN, not peer
authentication; this receiver is for the isolated credential-free diagnostic.

```sh
/external/tools/collect --browser-tcp /external/fresh-transfer /external/fresh-import
```

Import rechecks the archive and source snapshot, restores the existing browser
archive schema, preserves the exact transfer receipt, and records its hash.
It never synthesizes a UART log or a UART-success receipt. Keep the complete
transfer, import, original UART, frozen snapshot and producer bundles together
for later audit.

The small static Linux aarch64 sender can be appended to an existing isolated
browser diagnostic module at `/opt/vinix-browser-probe/browser-transfer`; the
rest of the WebKit runtime and SDK are reused. Its cross-build is:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -os linux -arch arm64 -cc /opt/homebrew/bin/aarch64-linux-musl-gcc -gc none -prod -cflags -static -d net_nonblocking_sockets -o /external/tools/browser-transfer tests/android-webview-browser-probe/transfer.v
```

`transfer-audit.v` freezes and rechecks the selected V sources for the receiver,
sender, collector, localhost selftest and audit tool, plus selected compiler
binary hashes. Its `freeze|check BUILD_ROOT` modes use the five retained
`*-v-files.txt` lists captured with each tool's actual target and socket flags.
It rejects empty/incomplete receipts and missing compiler pins. This covers
the selected V inputs; C headers, sysroots, linked libraries and transitive
compiler executables are explicitly outside its nonhermetic scope.

Validation and exact prepared tool pins are retained externally under
`/Users/alex/.local/state/vinix/android/browser-tcp-tools-2026-10-27-r2`.
The source revision is the commit adding this report. No guest transfer or
browser runtime result is claimed by the localhost/tool validation.

The final sequential builds and tests passed on 2026-10-27. The localhost
regression covers binary payloads crossing several buffers, truncation, extra
bytes, wrong digests, a missing EOF deadline, stalled sender timeout, BEGIN
uniqueness, canonical external output and archive bounds. Collector tests
retain all historical UART protocol checks and additionally reject changed
payloads/source snapshots, missing EOF, missing receiver pins and existing
output; the damaged UART is still rejected. The audit tests reject empty
receipts, wrong format and missing compilers. Its final check passed for 1504
selected source inputs.

| Check | Elapsed seconds | Maximum RSS bytes |
| --- | ---: | ---: |
| Final host receiver build | 1.23 | 234356736 |
| Final collector build | 1.37 | 249495552 |
| Final static sender build | 6.36 | 389971968 |
| Source freeze | 3.00 | 8093696 |
| Localhost transfer tests | 3.56 | 15089664 |
| Collector tests | 1.67 | 6619136 |
| Final selected source check | 2.13 | 8978432 |

Every retained timing log reports zero swaps. These are individual process
measurements from `/usr/bin/time -l`, not a measurement of total host memory.
The static sender is 450336 bytes. Final SHA-256 pins are:

| Artifact in the prepared tool directory | SHA-256 |
| --- | --- |
| `browser-transfer` | `66a77e26c7f141b5d26ef785992c2e86e493aacd94bb80450e9f62daaa522d6f` |
| `transfer` | `1b2114b0168b5e2c234896564ad714a36dfdfe347cc02dfea1b90b624e28ee2b` |
| `collect` | `d044a6406b3d888307ebfad8c77d1d5af69554ebd9403d0a845bcffe0111c423` |
| `transfer-audit` | `7095370d884410660ff1105851a6dd58601b99c536c6c0fe9574dd96824e9351` |
| `closure.json` | `c1a59e33834e71fbc821d434015a604a1dd2f59f888409661cd349aea383706d` |

The closed prepared directory has a complete one-root, 1545-entry streaming
seal at
`/Users/alex/.local/state/vinix/android/browser-tcp-tools-seal-2026-10-27-r2`.
Its manifest SHA-256 is
`eeee7ecc19ebff7891e32589a1a1339830d160bfd8ae5c5b9e801de298c572e4`.
Seal and subsequent full check passed; their logs and timing receipts are in
the sibling `browser-tcp-tools-seal-plan-2026-10-27-r2` directory. Sealing used
the existing sealer pinned to
`b12a4d0b2b133714da6876a0ed5cda623984dc72284c482d8e3ae57975304e77`.
The separate full check took 0.07 seconds, peaked at 22298624 RSS bytes and
reported zero swaps. This integrity seal preserves sources, tools and test
receipts; it is not a browser result or a hermetic toolchain claim. No files
were added to the prepared directory after sealing.
