# G13 UAT slot replacement

The pinned Asahi driver prefers a VM's cached slot when its token still
owns the root. Otherwise it takes the oldest idle slot. VM teardown clears
the TTBRs while preserving the allocator's release order. Replacement
publishes both TTBRs before invalidating the ASID once.
[Asahi allocator](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/slotalloc.rs#L233-L289)
· [Asahi teardown](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L2958-L3004)
· [Asahi replacement](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L3338-L3364)

Vinix G13 now applies the release order to cleared slots as well as
slots with cached roots. Replacement holds both page-table locks through
one ASID invalidation before clearing the displaced table's binding.
Vinix still excludes the ASC's current slot and any slot with outstanding
firmware invalidation from replacement. The offline audit reports
`not_equivalent`. Physical ASC cache behavior remains unverified.

ARM64 and x86-64 builds, 82 V contract test files, eight host suites and
five pinned source gates passed for `8b649b6c2` plus the archived patch.
The TLB fixture covered all 63 user slots, virgin and recently cleared
slots, both replacement TTBR words and edits to the old and new tables.
Two negative controls detected early reuse of a cleared slot and a
duplicate invalidation. Independent lifetime review and generated ARM64 C
confirmed the transfer lock and invalidation order. The allocation scan
reproduced the 178 existing allowance discrepancies. No M1 hardware tests
or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-uat-replacement-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `fd3c139a2a2ebb96e27fa263289a80954c802aa6c3285867ddaeb7fbff05cb2a` |
| `bundle.tar.gz.inventory.txt` | `a1448231ed4a9dae47a37596bf07768663f8e70d9e467eb21133d914aab6ff8d` |
