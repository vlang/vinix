# Authentication frame ownership

Package launch and administration use the account service's VAUT framing.
Encoding and decoding previously retained array growth buffers; interrupted
decodes retained already copied fields, and stream reads retained headers,
prefixes, field buffers and partial-frame state. Stream writes wiped their
encoded buffer but did not release it. These paths now retire their temporary
storage on success and refusal.

Encoding checks every count/length before allocating or copying fields and
reserves the exact bounded output size. Text construction and decoding reserve
their field table and transfer owned byte buffers without hidden header copies.
`read_frame` registers a new field with its partial-frame owner before reading
into it, so EOF or a read error erases and releases even partially received bytes.
The header and reusable length prefix are retired on every return. Stream writes
erase and release their temporary bytes and refuse zero-progress writes.

`Frame.close()` erases and releases fields, releases their table, and resets the
result; repeated close is safe. `text_frame`, `decode` and `read_frame` return
owned frames. `wipe()` still preserves borrowed containers and lengths, as
required by authentication clients and `authcore.handle`. Callers own encoded
arrays, `Frame.text()` strings and explicitly supplied variadic argument arrays.
Borrowed frames must not be closed as owners.

Erasure uses `explicit_bzero` on Linux and `memset_s` on macOS, preventing a
following free from removing the zeroing operation. The generated target C
calls the erase helper before freeing buffers; both target binaries retain an
actual call to `explicit_bzero`. The native tracked binary links `memset_s`.
Package replies now use the shared close operation, the authentication daemon
closes its owned request/reply, and the client retires an inner frame-read error
before returning its existing generic service diagnostic.

The VAUT magic, version 1, little-endian layout, arbitrary binary field contents,
12-field/4096-byte-field/49,212-byte-frame bounds and single-frame stream behavior
are unchanged. Header, length, trailing-data and authorization refusals keep
their existing behavior. An independent previous/current fixture produces
**321 identical rows**: 273 encoded-frame hashes across seven codes, all counts
0–12 and short/full-byte-range/maximum fields, plus 38 truncated and ten malformed
refusals. The original protocol's 20,000-round mutation fixture also passes.

## Measured storage

The matched fixture uses production framing sources from `0a6d5bdf1`, the same
frozen compiler/options and explicit retirement of every returned result and
error. Its variadic inputs are caller-owned and supplied outside each window.
Each probe repeats five times:

| Probe | Previous bytes retained | Final bytes retained |
| --- | ---: | ---: |
| Encode | 1450 | 0 |
| Decode and close | 3825 | 0 |
| Truncated decode | 9585 | 0 |
| Stream write | 7685 | 0 |
| Stream receive and close | 13180 | 0 |
| Interrupted stream receive | 18940 | 0 |
| Text-frame construction and close | 3825 | 0 |

These are live user allocation bytes for the fixture's inputs, not allocator
residency or kernel memory. The final ownership fixture checks every truncated
prefix once and repeats the following windows 1,000 times:

- Text-frame construction for every count 0–12, independently owned siblings,
  repeated close and full 49,212-byte frames containing all byte values.
- Sixteen malformed/trailing cases, an oversized
  final field after valid fields, and an excess field count.
- Maximum-frame wire roundtrips over one reusable pair, preserving input
  ownership and frame boundaries.
- Eight interrupted header/prefix/body positions, three malformed wire paths
  including a late oversized length after a secret field, and invalid-fd reads
  and writes. Heap windows retain zero bytes and descriptor counts stay flat.

Target malformed-wire cohorts wait seven guest seconds for deferred socket
reclamation, with no socket-allocation retry. This pacing follows the measured
[socket budget](launch-socket-check.md). Pure encode/decode loops do not wait.

## Qualification, 2026-10-16

All **28 focused native compile/run checks** passed: eight protocol/account/
launch/administrator fixture pairs, tracked ownership and ASan/UBSan pairs,
two compatibility pairs, and the signed CLI lifecycle/driver builds. ASan/UBSan
uses leak detection off; allocation retirement is checked separately by the
tracked fixture. All seven final matched probes retain zero bytes.

| Guest check | AArch64 | x86-64 |
| --- | --- | --- |
| Tracked frames as root and UID 1000, companion protocol/rules/peer checks | Passed, 211.3 s | Passed, 227.0 s |
| Real account elevation scenario | Passed, 46.5 s | Passed, 56.7 s |

Freshly built account/package tools run on the unchanged isolated tracking
kernels from the socket qualification. The elevation scenario exercises real
password verification/change, administrator and ordinary-user decisions,
fixed actions, throttling, malformed/silent clients, audit attribution and
console login. Each run ends in a clean guest-initiated QMP shutdown. The frame
receipt pins ten artifacts, including the staged authentication daemon, session
helper and package CLI; the elevation artifacts are pinned separately.
Durations include TCG and fixture waits and do not qualify performance.

This closes framing ownership; it does not establish flat allocation across
every authentication client, action runner, session-manager/UI workflow or
password implementation. Graphical session/display integration, production
publisher/catalog rollout and broader runtime/device gates in roadmap 14
remain open. No kernel or authorization policy was changed.

Repeat the tracked fixture from the repository root:

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/auth-frame \
  tools/accounts/authproto/ownership_test.v
/tmp/auth-frame
```

The guest controller is `tests/packages/auth-frame-runtime-check.v`, with
`--arch aarch64|x86_64 --kernel PATH --state-dir NEW_SHORT_DIRECTORY`. The
distribution driver now includes the tracked authentication frame fixture.

- [Native checks](results/2026-10-16/auth-frame-host.json), [summary](results/2026-10-16/auth-frame-host.txt), [tracked windows](results/2026-10-16/auth-frame-memory.txt), [sanitizers](results/2026-10-16/auth-frame-asan.txt)
- [Matched probes](results/2026-10-16/auth-frame-comparison.txt), [V probe](results/2026-10-16/auth-frame-comparison.v), [wire compatibility](results/2026-10-16/auth-frame-compatibility.txt), [V compatibility fixture](results/2026-10-16/auth-frame-compatibility.v)
- [Generated-C ownership review](results/2026-10-16/auth-frame-generated-c.txt), [target erase instructions](results/2026-10-16/auth-frame-erase.txt), [source/toolchain/artifact pins](results/2026-10-16/auth-frame-toolchain.json)
- [AArch64 frame receipt](results/2026-10-16/auth-frame-aarch64.json), [serial](results/2026-10-16/auth-frame-aarch64.serial.txt), [elevation serial](results/2026-10-16/auth-frame-aarch64.elevation.serial.txt)
- [x86-64 frame receipt](results/2026-10-16/auth-frame-x86_64.json), [serial](results/2026-10-16/auth-frame-x86_64.serial.txt), [elevation serial](results/2026-10-16/auth-frame-x86_64.elevation.serial.txt)
