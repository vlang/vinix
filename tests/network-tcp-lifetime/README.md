Run `./tests/network-tcp-lifetime/run-host.sh` to exercise the production Vinix
native V socket adapter (`kernel/netcore`) and lwIP 2.2.1 with ASan/UBSan. The fixture uses actual TCP packets
and timer processing; it does not mock shutdown, PCB allocation, or close.

It checks full shutdown followed by close and PCB reuse, both half-shutdown
orders, peer FIN after write shutdown (including CLOSING before the final ACK),
TIME-WAIT expiry while the descriptor remains open, queued receive bytes,
final FIN payload after a receive-budget shrink and metadata allocation failure,
endpoint queries including IPv6 scope, deferred FIN after TCP segment pool
exhaustion, and listener shutdown errors.

The host fixture enables lwIP statistics only in its temporary headers to
verify that the metadata-failure path restores heap usage and packet-pool
availability. The kernel's lwIP configuration is unchanged.
