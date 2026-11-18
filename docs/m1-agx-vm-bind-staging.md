# G13 VM_BIND staging

Omarchy's pinned Asahi G13 path reserves storage for the full strided batch
before reading userspace. A batch that exceeds the signed capacity limit
or fails allocation returns `ENOMEM`. After successful allocation, a
fault in the full-batch copy returns `EFAULT` before any mapping changes.
[Asahi VM_BIND](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L793-L842)
· [Linux usercopy](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/rust/kernel/uaccess.rs#L370-L380)
· [Linux vector capacity](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/rust/kernel/alloc/kvec.rs#L665-L695)

Vinix now follows that error order for G13, including null and wrapping
pointers. The shared handler still rejects those pointers early on G17
or when there is no GPU manager. Empty batches return after header
validation without allocating. The one scratch buffer is freed on every
exit after allocation. Vinix and Linux still use different allocators,
so memory pressure and fragmentation can produce different outcomes.

ARM64 and x86-64 builds, 82 V contract files, two sanitizer suites and
five pinned source gates passed for `9ac58b73ef08d7d865a7400646269e7c95c820ad`
plus the archived patch. The focused suite covers 14 staging cases and
1,200 mapping checks. Three negative controls caught the previous pointer
ordering, a wrong capacity error and a G17 regression. Independent lifetime
review and generated C checks passed. The allocation scan reproduced 178
baseline discrepancies.

The overall audit still reports `not_equivalent`. No M1 hardware tests or
reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-vm-bind-staging-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `d2db42531c6ca8db857a0b10afc6d613e43936e5becb3b5a1fbbee0b7e94a303` |
| `bundle.tar.gz.inventory.txt` | `909ede3f2e748adcdb0ca960347a164bda5831a6ca63db4c7ed2fabf81a2819a` |
