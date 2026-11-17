# AGX VM reclamation

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` clears a
VM's published root and invalidates its ASID at final release. The page-table
destructor releases the VM's owned page tables. [Asahi VM teardown](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L2948-L3004)
· [Asahi page-table teardown](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/pgtable.rs#L1020-L1050)

After file mappings, queue backing and job captures retire, Vinix now
reclaims the VM record, page-table wrapper, residual driver-buffer records
and the two VA heaps' pointer arrays. Root removal and ASID invalidation
precede these frees. Page-table destruction preserves bootloader-owned
roots and their descendants.

The sanitizer fixture verified seven metadata releases per VM over 400
create/destroy cycles and 3,200 buffer allocations under both PMM granules.
The real page-table and heap fixture verified wrapper reclamation over 400
cycles. Two controls replayed the old code and failed the corresponding
reclamation assertions. Independent review checked the file, queue, job,
and shutdown ownership boundaries.

Both kernel builds, 82 V contract test files, six host suites and five
pinned source gates passed for Vinix `9ba14fb70` plus the archived patch.
The AArch64 allocation scan reports two fewer unannotated sites. The
existing allowance discrepancies still fail the scan. G13 still has 63
device-wide VM reservations. The source audit reports `not_equivalent`.
No hardware tests or reboots occurred.

The tested patch, references, generated C and logs are under
`/Users/alex/.local/state/vinix/omarchy-m1-vm-release-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `279bd1242bd81c2be80d665f4ea3bde0f7eea79874d7c78838f67a8acebfa661` |
| `bundle.tar.gz.inventory.txt` | `6bc03fd96ac2defdf1c685d87e08460272a0c6df7f54e5d9be60a9d281af024e` |
