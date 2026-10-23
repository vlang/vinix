Run `v -cc cc run tests/network-arp/run.v` from any directory. This V fixture
builds the production lwIP sources with the kernel configuration, enabling
statistics only in its private build headers.

It holds an ARP reply while two outgoing packets are queued, then checks that
both reach the Ethernet output in order. This reproduces the cold-neighbor
loss seen with libc's consecutive A/AAAA DNS queries. It also checks the
three-packet bound and runs 200 resolution, unanswered-neighbor expiry and
interface-removal cycles, measuring live heap and pool allocations after each
cycle. No production queue or lifetime algorithm is copied into the fixture.

`--baseline` disables multiple-packet queueing in the private headers. That
run must fail at the paired-packet assertion, transmitting only `[28]`.
