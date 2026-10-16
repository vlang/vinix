# Launch socket EOF and resource recovery

A partially sent isolated launch request followed by `shutdown(SHUT_WR)` could
wait for its ten-second input deadline. The UNIX receive paths drained the last
queued byte or record and cleared `POLLIN`, although a subsequent read would
return EOF immediately. Fresh isolated tracking builds of `973446f44` reproduce
this on AArch64 and x86-64: the probe's 250 ms poll returns zero, then read
returns zero. The same probe returns `POLLIN` immediately on both patched kernels.

Stream reads, sequenced-packet receives and `recvmsg` now preserve readability
when the peer has finished or the local receive half is shut down. Ordinary
empty live sockets still lose readability. Shutdown publishes its flags and
readiness under the receive lock, preventing a concurrent drain from erasing
the notification. It releases the local endpoint lock before taking the peer
lock, so opposite shutdowns cannot invert those locks. Allocation, reference
count and reclamation lifetimes are unchanged. The existing syscall reference
keeps the endpoint's open description and peer link alive through the call.

The stream regression fixture checks all three receive interfaces on stream
and sequenced-packet sockets, with both `SHUT_WR` and `SHUT_RDWR`. It covers
normal live-queue draining, short record truncation, repeated EOF polls/reads,
the surviving reverse direction after `SHUT_WR`, 16 pairs of simultaneous
opposite shutdowns, and empty/partial-header/partial-body launch requests that
must report interruption within one second. Existing separate-stream,
close-on-exec, missing-rights and surplus-rights checks still run. Darwin can
return `ENOTCONN` on the second opposite `SHUT_RDWR`; the host concurrency test
accepts that specific result. Linux/Vinix must complete both shutdowns normally.

## Socket budget diagnosis

The earlier ENOMEM observations also reproduce on current HEAD. They are an
object admission limit in the focused empty-pair probe, rather than physical
memory exhaustion: the 2,049th rapid socketpair is refused with errno 12,
`LastDenied: objects`, `LastDeniedKind: socket`, and 4,096 socket objects charged
33,554,432 bytes. This limit is global, and closed endpoints keep their charge
until the reader grace period expires. It is unchanged by this fix.

After a 13-second reclamation wait, both kernels report zero socket objects
and zero socket bytes, and another 200 pairs succeed. The 1536-byte endpoint
slab class returns to its pre-burst live count: AArch64 14 → 4110 → 14,
x86-64 13 → 4109 → 13. These measurements establish recovery for this probe;
they do not establish flat retention for every kernel class or workload.

The transport ownership guest now uses the same 1,000 cycles per wire case as
the native tracked fixture. Each cohort creates at most 2,000 endpoints, then
waits seven guest seconds for reclamation before starting another. No failed
socket creation is retried. The controller allows 900 seconds for both root
and UID 1000, including these explicit waits. Its allocation and descriptor
assertions remain unchanged. The separate EOF regression uses half-close;
the stress fixture retains its completely closed interrupted-client cases.

## Qualification

Kernels were built in separate worktrees at `973446f44`, with only the UNIX
socket patch applied, `ALLOC_TRACK=1`, and AArch64 `LIMINE_MP=1`. Shared uncommitted
kernel edits were excluded. The frozen compiler is V 0.5.2 `826e96f`; the compiler
on PATH rejected existing pointer-return code before a kernel could build.

Twelve focused native compile/run checks cover protocol, stream, ownership,
tracked ownership and ASan/UBSan stream/ownership fixtures. The dedicated
`launch-socket-runtime-check.v` runs the final EOF and descriptor fixture on
both architectures; the same fixture is also exercised against baseline kernels
to retain its expected failures. The paced transport suite runs all 1,000-cycle
wire windows as root and UID 1000, with zero retained user bytes and descriptors.
Artifact hashes and clean guest-initiated QMP shutdowns are checked separately.

| Guest | AArch64 | x86-64 |
| --- | --- | --- |
| Final EOF/descriptor regressions | Passed, 7.7 s | Passed, 5.5 s |
| Same regressions on baseline | Expected failure, 18.0 s | Expected failure, 15.7 s |
| Paced transport, root and UID 1000 | Passed, 410.4 s | Passed, 336.6 s |

Each transport guest completes 40,000 wire cycles across its two actors. These
TCG timings include fixture waits and qualify functionality, not performance.

The repository-wide allocation-site audit still fails its existing allowlist.
Baseline and patched reports have identical counts by file and allocation kind;
this change introduces no reported site. The allowlist was not changed. This
increment does not claim a passing global allocation audit, a desktop session
qualification, or completion of roadmap 14's publisher, catalog and runtime gates.

Run the dedicated guest controller with a short new state directory:

```sh
v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  -o /tmp/launch-socket tests/packages/launch-socket-runtime-check.v
/tmp/launch-socket --arch aarch64 --kernel /path/to/kernel/bin/vinix \
  --state-dir /tmp/launch-socket-arm
```

Use `--arch x86_64` for the other architecture. The paced ownership controller
remains `tests/packages/launch-transport-runtime-check.v` with the same options.
Retained evidence uses the `launch-socket-` prefix in
[the result directory](results/2026-10-16/).

- [Native checks](results/2026-10-16/launch-socket-host.json), [tracked windows](results/2026-10-16/launch-socket-memory.txt), [sanitizers](results/2026-10-16/launch-socket-asan.txt)
- [Allocation audit comparison](results/2026-10-16/launch-socket-allocation-comparison.txt), [generated-C review](results/2026-10-16/launch-socket-generated-c.txt), [source and artifact pins](results/2026-10-16/launch-socket-toolchain.json)
- [AArch64 baseline EOF failure](results/2026-10-16/launch-socket-aarch64.eof-before.serial.txt), [final EOF pass](results/2026-10-16/launch-socket-aarch64.eof-after.serial.txt), [transport receipt](results/2026-10-16/launch-socket-aarch64.stress.json)
- [x86-64 baseline EOF failure](results/2026-10-16/launch-socket-x86_64.eof-before.serial.txt), [final EOF pass](results/2026-10-16/launch-socket-x86_64.eof-after.serial.txt), [transport receipt](results/2026-10-16/launch-socket-x86_64.stress.json)
- [AArch64 resource recovery](results/2026-10-16/launch-socket-aarch64.candidate.serial.txt), [x86-64 resource recovery](results/2026-10-16/launch-socket-x86_64.candidate.serial.txt), [V probe](results/2026-10-16/launch-socket-probe.v), [probe controller](results/2026-10-16/launch-socket-probe-controller.v)
