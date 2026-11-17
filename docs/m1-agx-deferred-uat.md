# Deferred G13 UAT root publication

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` prepares a
VM's page tables before installing its application roots. The G13 queue
binds the VM during submission, and Asahi invalidates the ASID after
publishing the two root words.
[Asahi VM binding](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L3285-L3370)
· [G13 submission](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L708-L721)

Vinix now publishes a G13 VM's root during its first render or compute job
preparation. The UAT manager lock serializes root writes by host threads,
and the firmware handoff lock serializes them with the ASC. Root publication
completes the existing ASID invalidation before command construction. Later
jobs reuse the published root.

Dormant user mappings and initial TVB buffers update their page tables
without a firmware range flush. Kernel buffer mappings follow the existing
flush path. Dormant teardown keeps private PTEs and backing available until
final release, so a partial kernel-buffer failure can retry after another
queue publishes the VM. After publication, the cache-safe reprotect, flush
and unmap sequence applies.

Host checks exercised dormant `VM_BIND` and unbind, root publication and
reuse, initial TVB on both G13 firmware layouts, and a cached PTE surviving
first bind, a failed flush, and teardown retry. Negative controls caught
eager publication and premature dormant PTE removal. Both kernel builds,
82 V test files, the ioctl, UAT, TVB and async suites, and five pinned source
gates passed for Vinix `9aef22675` plus this patch. The allocation scan
reproduced the same 178 existing allowance findings. Independent lifetime
review covered host locking, firmware visibility and retained cleanup.

Vinix still reserves a hardware slot for each live VM until destruction,
with 63 slots shared by the device. Asahi leases slots for submissions.
Physical firmware behavior and full driver parity remain unverified. No
hardware tests or reboots were performed.

The tested patch, reference sources, native binaries and logs are under
`/Users/alex/.local/state/vinix/omarchy-m1-deferred-uat-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `34cd253a47ec5e25263fae3ff2bd7e803b85aba16dcf0ce8bc687d17d63438e1` |
| `bundle.tar.gz.inventory.txt` | `aba219c2fb45f3e195ff1d7c7cd363cba491426892add671b6bbd40886b489c1` |
