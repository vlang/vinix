# Network option behavior

Run `./tests/network-options/run-host.sh` for ASan/UBSan coverage of the production
lwIP glue. It checks TCP SYN SACK/timestamp options, an injected SYN-ACK, out-of-order data/SACK and gap recovery,
timer-driven keepalive probes and failed-peer teardown, listener inheritance,
receive/send limits, empty UDP datagram accounting, TCP receive-buffer shrink
and retry, send backpressure/output failures, and abort-close callback cleanup.

Build the kernel for the desired architecture, then run:

```sh
VINIX_QEMU_RT_NO_BUILD=1 python3 tests/network-options/run.py
python3 tests/network-options/run.py --arch amd64
```

The ARM64 runner uses the same build/VM support as `tests/realtime`. Its optional
`VINIX_VM_RUNNER_ROOT`, `VINIX_KERNEL_DIR` and `VINIX_AARCH64_SYSROOT` settings
support isolated worktree builds. The AMD64 runner uses
`x86_64-linux-musl-gcc`, the existing ISO builder and QEMU TCG; set
`VINIX_AMD64_KERNEL` to select an already-built kernel. Each boot uses private
images and requires all four test groups and the final PASS marker.

The guest checks socket option bounds/readback, rejected unsupported options,
UDP send-budget enforcement, rtnetlink mutation errors with/without ACK,
netlink queue budget/recovery, a TCP linger deadline with pending data, and background linger during process exit.

`SO_SNDBUF` and `SO_RCVBUF` set per-socket queue budgets. Requests are doubled,
with a 4096-byte minimum and 4 MiB maximum; the transport's own compile-time TCP
window/send capacity remains an additional bound. A TCP receiver accepts one
already-advertised/coalesced pbuf chain into an empty queue even when it exceeds
a newly reduced receive budget, so shrinking cannot permanently stall the
stream. Further chains apply backpressure. UDP accounts packet metadata as well
as payload and drops excess datagrams. Netlink charges retained reply capacity
and metadata, rejects oversized requests, and reports queue exhaustion.

These changes partially address NET3/NET4 in the OpenBSD gap report. Mutable
routes/interfaces, multiple physical NICs and independent network namespaces
remain unfinished. IP_RECVERR retains the existing glibc resolver compatibility
setting without an ICMP error queue; PMTU feedback, ECN, raw userspace IPv4
sockets, IPv6, multicast membership, packet filtering/NAT and VPNs also remain
unfinished. SACK/timestamp negotiation is enabled and tested; this suite does
not establish performance gains or exhaustive loss/reordering behavior.
