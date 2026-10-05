# IPv6 and multicast regressions

The kernel enables the pinned lwIP 2.2.1 IPv6 core, ND/DAD, router
solicitations and advertisements, SLAAC address lifetimes, IPv6 fragmentation
and reassembly, IGMPv2 and MLDv1. `AF_INET6` TCP/UDP sockets use the Linux
28-byte `sockaddr_in6` ABI. IPv4-mapped endpoints, wildcard dual stack
listeners, `IPV6_V6ONLY`, interface scopes, unicast/multicast hop limits,
multicast output interfaces and loop controls are supported. IPv4 memberships
accept `ip_mreq`/`ip_mreqn`; IPv6 memberships accept `ipv6_mreq`.

Each socket owns at most 16 inline membership records. A join acquires the
native interface/group reference before installing a record; duplicate,
capacity and saturated 8-bit native refcounts fail without changing ownership.
Leave and final close release that reference. The automatic IPv4 all-hosts
group remains owned by the interface while sockets keep only their delivery
policy records for it. Physical interface detach
releases native groups, and a scalar generation prevents old socket records
from releasing groups created after reattach. Linux indices `lo=1` and
`eth0=2` remain stable while native lwIP zone IDs change at hotplug.
Datagrams are delivered to sockets joined on the receiving interface.
The e1000 receive control accepts multicast frames so router/neighbor
discovery reaches the native stack. It retains unicast address filtering;
multicast hardware hash filtering is a later optimization, with group and
socket policy enforced in software.

`/proc/net/if_inet6` reports actual address states, `/proc/net/tcp6` reports
live IPv6 TCP sockets, and connected `IPV6_MTU` reads the discovered path MTU.
The original IPv4 C bridge remains available to existing tests and drivers.
IPv6 TCP initial sequence numbers hash all 128 bits of both addresses with
the existing keyed RFC 6528 generator.

## Host checks

```sh
./tests/net-random/run.sh
./tests/ipv6-multicast/run-host.sh
python3 tests/ipv6-multicast/check-generated.py kernel/obj/blob.c
python3 tests/ipv6-multicast/check-generated.py build-amd64-kernel/obj/blob.c
```

The second command compiles the production bridge and all native lwIP core
sources with AddressSanitizer and UndefinedBehaviorSanitizer. It also runs
the existing IPv4 transport options suite. Additional checks cover IPv6
TCP/UDP, mapped datagrams, V6ONLY, membership filtering and loop delivery,
1,000 join/drop/close cycles, invalid scopes, socket membership capacity,
native refcount saturation, detach/reattach with old socket retirement and
new group delivery, and checksummed Ethernet RA and ICMPv6 packet-too-big
input. Native timers demonstrate DAD, preferred/valid lifetime expiry and
PMTU reduction from 1500 to 1280.
An actual 5,000-byte UDP datagram is fragmented by the native IPv6 core,
then its fragments are delivered in reverse order and reassembled intact.
The generated-C check rejects heap promotion of endpoint/option/Text
scratch and stack allocation inside retry or formatting loops.

## Guest checks

Build the isolated kernel with dependencies linked from the main checkout:

```sh
make -C kernel ARCH=aarch64 CC=clang V=/path/to/v PROD=1 LIMINE_MP=1 ALLOC_TRACK=1
V=/path/to/v PROD=1 ALLOC_TRACK=1 ./scripts/build-amd64.sh --no-userland --no-iso
VINIX_AARCH64_SYSROOT=/path/to/main/build-aarch64-userland/sysroot \
  ./tests/ipv6-multicast/run.sh aarch64
./tests/ipv6-multicast/run.sh amd64
```

An isolated worktree can reuse a populated main checkout's boot assets with
`VINIX_QEMU_RUNNER_ROOT=/path/to/main` and
`VINIX_KERNEL_DIR=/path/to/worktree/kernel`. `VINIX_TEST_CAPTURE` saves the
packet capture. The runner opens only local TCP/UDP echo sockets on `::1`
port 39066; run these guest tests sequentially to avoid sharing that port.

Guest checks exercise real syscall address copying, accepted socket names,
proc snapshots, mapped replies, V6ONLY, malformed options and user pointers,
link-local scope validation, both families' memberships on loopback and the
physical NIC, live SLAAC plus physical IPv6 TCP/UDP through QEMU's user
network, and 500 pairs of membership cycles measured through `/proc/meminfo`
and `/proc/allocsites`. Captures require RS/RA, NS/NA, IGMP/MLD reports and
outbound IPv6 TCP/UDP. The measured loop also reads and closes all three
network proc snapshots with live IPv4/IPv6 listeners. Run this against the
combined Socket I/O allocation fix; older syscall scratch buffers retain
memory independently of the network protocol implementation.

Validated production `ALLOC_TRACK=1` kernels with the Socket I/O and x86
`poll` timeout fixes pass all guest checks on both architectures:

| Guest | Physical adapter | Slab before/after 500 cycles |
| --- | --- | --- |
| AArch64 | VirtIO | 1,216 / 1,216 KiB |
| x86-64 | e1000 | 904 / 904 KiB |

Both captures include the required discovery/membership packets and IPv6
TCP/UDP. The host sanitizer suite, keyed ISN tests, and generated-C checks
pass. The general allocation allowlist check still has baseline failures;
its standalone x86 source copy also omits an existing DRM module, unlike
the successful production build. No allocation allowances were added.

This implements the ordinary IPv6/multicast socket path. Raw IPv6 sockets,
IPv6 ancillary data/error queues, source-specific multicast, multicast
routing, mutable IPv6 routes/addresses, per-namespace interfaces and IPsec
remain separate gaps. IGMPv3/MLDv2 source filtering is not supplied by the
pinned native stack; unsupported options return an error.

ABI references: [Linux ipv6(7)](https://man7.org/linux/man-pages/man7/ipv6.7.html),
[Linux ip(7)](https://man7.org/linux/man-pages/man7/ip.7.html), and
[lwIP IPv6 reassembly](https://github.com/lwip-tcpip/lwip/blob/STABLE-2_2_1_RELEASE/src/include/lwip/ip6_frag.h).
Receive register reference:
[Linux e1000 definitions](https://github.com/torvalds/linux/blob/master/drivers/net/ethernet/intel/e1000/e1000_hw.h).
