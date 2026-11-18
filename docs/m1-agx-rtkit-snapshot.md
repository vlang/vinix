# G13 RTKit crash-log ownership

Omarchy's pinned Asahi copies the firmware crash log into private storage
before decoding it and stops receive work before freeing the shared buffer.
The Rust shmem bridge owns the mapping until the C transport releases it.
[Asahi crash callback](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L551-L605)
[Asahi teardown](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L1515-L1528)
[Rust shmem bridge](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/rust/kernel/soc/apple/rtkit.rs#L180-L215)

Vinix now copies the complete negotiated G13 crash buffer under the lock
that protects its backing. The parser runs after releasing the lock and
frees the private snapshot on every exit. Snapshot allocation skips reclaim
because a crash can arrive during locked boot. G13 runtime system requests
hold the manager lock through the reply that publishes the buffer address,
and shutdown blocks late requests. Failure reporting still proceeds when
the snapshot cannot be allocated or copied.

ARM64 and x86-64 kernel builds passed for
`121f3a3280e7cd2ab9625b883a17c40b4193a376` plus the archived source patch.
All 82 contract files, five pinned source gates, three sanitizer suites
and independent lifetime review passed. The focused fixture exercised 16
crash paths across both G13 ABIs, including shutdown immediately before
and after the copy. Three negative controls detected an unlocked copy,
an unlocked allocation and reply path, and dispatch after shutdown.
Generated ARM64 C confirmed callback registration and cleanup without
implicit heap allocations. The allocation scan reproduced the baseline's
178 allowance discrepancies.

The full audit remains `not_equivalent`. RTKit parser, message and DMA
differences and device coherency remain unverified. No hardware tests or
reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-snapshot-20261118/`.
The archive and restored copy passed complete inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `4737111668a9a223d86c722bd587c1bc2b33f2431b3e73473a541dbfe20622fd` |
| `bundle.tar.gz.inventory.txt` | `6190ec10b148c0125f389fc432f51848a6e45a6944202269070311e1dc238566` |
