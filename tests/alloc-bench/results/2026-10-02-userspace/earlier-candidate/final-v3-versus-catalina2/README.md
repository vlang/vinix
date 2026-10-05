# Completed v3 candidate against the fresh Catalina capture

Both captures completed all six workloads and 42 raw samples. Vinix used the
final v3 kernel and retained musl build. The fresh Catalina capture was much
faster than its earlier noisy capture: this comparison does **not** reach the
performance target. Only the 256 KiB malloc workload is faster on Vinix.

These complete records remain preserved while the general small-allocation,
atomic and memory-copy paths are optimized further. They contribute no final
parity claim for a later implementation. The strict comparison retains every
raw sample and records all configuration/compiler differences.
