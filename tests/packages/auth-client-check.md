# Authentication client ownership

Package launch and administration use `authclient.transact`, `ask` and
`ask_root`. A failed reply read previously retained a 16-byte error-interface
wrapper on each call, even after its message and concrete error were freed.
The frozen compiler promoted the implicit `or` error when its mutable `free`
method was called directly. A private value-parameter helper now retires the
message and concrete error without promoting that wrapper.

The socket address and kernel peer-identity scratch already stay on the stack;
they needed no change. The generated C confirms this on both target
architectures. There are no new allocation retries or authorization changes.

Requests remain borrowed: every field is erased on success or failure, while
the caller retains its buffers, lengths and explicitly supplied variadic table.
Successful calls return an independent owned frame that must be closed. Root
checking still precedes transmission of any request byte, and failed reply
reads retain the existing generic service diagnosis.

## Measurements

The same fixture and frozen V compiler compare production client sources from
`531a9a0ce` with the final implementation. Input buffers and variadic tables
belong to the fixture outside each allocation window. All returned frames,
messages and errors are explicitly retired. Each matched window repeats five
times:

| Window | Previous bytes retained | Final bytes retained |
| --- | ---: | ---: |
| `transact`, `ask`, `ask_root` (each) | 0 | 0 |
| Reply EOF; partial header, length and body (each) | 80 | 0 |
| Bad magic, excess field count, oversized late field (each) | 80 | 0 |
| Long socket path, unavailable service, invalid request (each) | 0 | 0 |

The final fixture repeats all **13 windows 1,000 times**, retaining zero user
allocation bytes and preserving descriptor counts. It checks binary contents,
independent reply ownership, repeatable close, erased but reusable request
buffers and unchanged diagnostics. The server confirms EOF without receiving
any byte when an ordinary peer fails the root guard, or when a request is
locally refused before transmission.

A child server acknowledges each handled connection so immediate refusals do
not overrun its listen backlog. Guest cohorts wait seven seconds for deferred
kernel endpoint reclamation, following the measured [socket budget](launch-socket-check.md).
Neither mechanism changes production transport behavior. These measurements
cover client user allocations, not kernel memory or allocator residency.

## Qualification, 2026-10-16

All **28 focused native compile/run checks** passed: eight existing protocol,
account, launch and administrator fixture pairs; the tracked client, matched
previous/final and ASan/UBSan pairs; and signed CLI lifecycle/driver checks.
ASan/UBSan disables leak detection; explicit tracking checks allocation
retirement separately.

| Guest check | AArch64 | x86-64 |
| --- | --- | --- |
| Tracked client as root and UID 1000, protocol/rules/peer companions | Passed, 288.6 s | Passed, 344.6 s |
| Real account elevation | Passed, 46.3 s | Passed, 56.7 s |

Both target guests run all windows as root and UID 1000, with protocol,
authentication-rule and ordinary-peer companions. Fresh account/package tools
also run the real account elevation scenario. Runs use the unchanged isolated
tracking kernels from socket qualification and require clean guest-initiated
QMP shutdown. Artifact receipts pin the staged fixture, daemon, session helper,
package CLI and kernel. Guest durations include TCG and reclamation waits and
do not qualify performance.

This closes the measured client transport leak. It does not establish flat
allocation across package-client call sites, action execution, password
implementation or session/UI workflows. Production repository/publisher
rollout, advertised foreign-runtime catalog qualification and graphical
session/display integration remain broader roadmap 14 gates.

Repeat from the repository root:

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/auth-client \
  tools/accounts/authclient/ownership_test.v
/tmp/auth-client
```

The target controller is `tests/packages/auth-client-runtime-check.v`, accepting
`--arch aarch64|x86_64 --kernel PATH --state-dir NEW_SHORT_DIRECTORY`.
The distribution driver includes the tracked client fixture.

- [Native checks](results/2026-10-16/auth-client-host.json), [summary](results/2026-10-16/auth-client-host.txt), [tracked windows](results/2026-10-16/auth-client-memory.txt), [sanitizers](results/2026-10-16/auth-client-asan.txt), [CLI lifecycle](results/2026-10-16/auth-client-cli.txt)
- [Matched previous/final measurements](results/2026-10-16/auth-client-comparison.txt), [V fixture](../../tools/accounts/authclient/ownership_test.v), [generated-C lifetime review](results/2026-10-16/auth-client-generated-c.txt), [source/toolchain/artifact pins](results/2026-10-16/auth-client-toolchain.json)
- [AArch64 receipt](results/2026-10-16/auth-client-aarch64.json), [serial](results/2026-10-16/auth-client-aarch64.serial.txt), [elevation serial](results/2026-10-16/auth-client-aarch64.elevation.serial.txt)
- [x86-64 receipt](results/2026-10-16/auth-client-x86_64.json), [serial](results/2026-10-16/auth-client-x86_64.serial.txt), [elevation serial](results/2026-10-16/auth-client-x86_64.elevation.serial.txt)
