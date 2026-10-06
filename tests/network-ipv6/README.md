# IPv6 networking regression tests

This document records the earlier XNU implementation checkpoint and its
measurements. The merged adapter also includes the later OpenBSD work; its
managed memberships, network proc files and physical-network validation are
documented in [ipv6-multicast](../ipv6-multicast/README.md). The host fixture
here now uses that adapter's endpoint API. Historical measurements below are
not measurements of the final consolidated kernel.

This checkpoint addresses the socket and automatic-address parts of NET1 in
[the XNU comparison](../../docs/macos-xnu-kernel-gap-analysis.md). It enables the
pinned lwIP IPv6 implementation, neighbor discovery, router solicitation, SLAAC,
and multicast listener handling. Linux `AF_INET6` stream/datagram sockets use
28-byte `sockaddr_in6` addresses (the legacy 24-byte input form also works),
scoped link-local destinations, `IPV6_V6ONLY`, and `IPV6_UNICAST_HOPS`. Dual-stack
wildcard listeners receive IPv4 connections/datagrams as IPv4-mapped addresses.
`RTM_GETADDR` respects the requested family and reports IPv6 loopback and the
physical interface's current lwIP address slots. e1000 accepts multicast frames
needed by neighbor discovery. TCP sequence-number hashing includes all IPv6
address bytes.

The dependency export now includes `src/core/ipv6/*.c`. Existing generated
`kernel/c/lwip` directories must be refreshed with `kernel/get-deps` before
building; the pinned upstream revision is unchanged. Isolated worktrees should
use their own generated dependency copy when another session is building.

Run the production-stack host tests with:

```sh
tests/network-ipv6/run-host.sh
tests/network-options/run-host.sh
tests/net-random/run.sh
tests/krandom/run.sh /absolute/path/to/v
```

The IPv6 host test compiles the native V adapter in `kernel/netcore` and pinned lwIP with AddressSanitizer
and UndefinedBehaviorSanitizer. It exercises native IPv6 and mapped IPv4 UDP/TCP,
IPv6-only refusal, scope errors, address-setting restrictions, timer processing,
600 repeated UDP exchanges with no remaining UDP PCBs or retained lwIP heap
bytes, and an Ethernet ICMPv6 router advertisement that creates a SLAAC address. Transport-option regressions
remain covered by the existing tests.

After building an isolated kernel, run the actual Linux ABI test with:

```sh
python3 tests/kernel-gaps/run.py --arch=aarch64 --kernel-dir=/absolute/kernel \
  --source=tests/network-ipv6/guestfixture/core.v \
  --expect='IPV6 PASS: TCP UDP dual-stack socket ABI' \
  --expect='IPV6 PASS: rtnetlink IPv6 loopback reporting' \
  --expect='IPV6 PASS: repeated socket path allocation measurement' \
  --fail='IPV6 FAIL:'
```

The guest measures retained slab pages and live objects in every heap size class
before and after 500 warmed-up UDP socket exchanges, IPv6 option queries, and
IPv6 rtnetlink address dumps. This also verifies that dump reply buffers transfer
to the receive queue without nested-array cloning, and interface queries keep
MAC/DNS scratch arrays on the stack. The metric read uses native `openat`
directly. The guest uses the procfs mounted by the kernel at startup.

Release kernels built and passed these guest checks on both architectures:

| Architecture | Repeated operations | Live heap objects | Retained slab pages |
| --- | --- | --- | --- |
| ARM64 | 500 UDP exchanges plus IPv6 option queries and address dumps | All 18 classes unchanged | 1088 → 1088 KiB |
| x86_64 | 500 UDP exchanges plus IPv6 option queries and address dumps | All 14 classes unchanged | 876 → 876 KiB |

The host stack separately measured lwIP's internal heap at 0 → 0 bytes across
600 warmed-up UDP exchanges; slab statistics alone cannot see allocations in
that fixed backing pool. ASan/UBSan IPv6 and transport-option tests, random-port
regressions, and existing ChaCha20 reference vectors passed.

The allocation-site allowlist audit was also run with the pinned V compiler. It
failed on hundreds of existing unlisted heap/interface sites across the kernel
(359 ARM64 and 248 x86_64 reported sites), and the x86_64 report returned compiler
status 1. Its old allowlist was not replaced. These failures need a separate
compiler/reporting and ownership audit; the targeted guest measurements above
were performed on successfully built release kernels.

Measurement exposed existing leaks in nested-array netlink reply cloning,
MAC/DNS query scratch arrays, CSPRNG refill/rekey blocks, and the procfs text
builders used by the measurement itself. The queue now owns each reply buffer
once, and synchronous scratch buffers stay on the stack. The procfs readers
consume their builder by value with `lib.finish_text`, retaining the original
string-buffer lifetime. Generated C was checked for these allocation sites.
The CSPRNG sites were also identified with `ALLOC_TRACK=1`: 5000 exchanges
previously retained 78 refill and 78 rekey blocks of 64 bytes each.

The earlier validation found a procfs self-mount redirect cycle and `ELOOP`.
The consolidated kernel rejects mounts of a cached procfs root onto itself
or its descendants before changing the graph; [procfs-mount](../procfs-mount/README.md)
covers that repair, including stale PID views and legitimate aliases.

## Historical remaining networking requirements

The following table records the scope left by this earlier checkpoint.
Managed IPv4/IPv6 memberships, `/proc/net/tcp6` and physical IPv6 acceptance
tests were subsequently implemented. Current remaining work is tracked in
the [OpenBSD gap report](../../docs/openbsd-kernel-gap-analysis.md#current-networking)
and [XNU ledger](../../docs/macos-xnu-implementation-status.md).

| Finding | Remaining work after this checkpoint |
| --- | --- |
| NET1 | IPv6 route/neighbor dumps and mutation; packet-info and multicast socket controls; Linux error queues; `/proc/net/tcp6`; IPv6 DNS server publication; end-to-end external IPv6 and physical-driver validation. lwIP's automatic routing works independently of rtnetlink, whose route dump still describes IPv4. The stack still has one physical interface. |
| NET2 | Apply supported link/address/route changes with privilege and namespace ownership checks. Unsupported mutations currently return `EOPNOTSUPP` through the separately committed transport/control fix. Multiple interfaces, bounded route tables, per-network-namespace stack ownership, and notifications are still needed. |
| NET3 | Define a deliberate native rule-control ABI, bounded connection tracking and timeout ownership, input/output filter hooks, stateful rules, NAT mapping/reverse translation, fragmentation behavior, checksum repair, and allocation/pressure tests. No firewall or NAT was added here. |
| NET4 | Add `/dev/net/tun`, Linux TUN/TAP ioctls, packet queues/poll/read/write lifetime handling, privilege checks, routing and teardown. IPsec additionally needs security associations, replay windows, authenticated encryption, policy, and key-management integration. |
| NET5 | Measure lock contention, drops, throughput and tail latency. The `NO_SYS` stack still uses one network lock and one hardware queue; parallelization requires explicit PCB/pbuf ownership and driver multiqueue support. |
| NET6 | Introduce multiple usable interfaces/routes before per-flow application policy and handover. MPTCP needs protocol negotiation, subflow scheduling, retransmission/sequence mappings and userspace controls. No Apple-private NECP compatibility is claimed. |
