# Native AGX VM dummy page backing

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` creates a
zeroed 16 KiB dummy mapping in every new GPU VM, starting two UAT pages below
the top of the user address space. It uses GPU-shared read/write permissions
and leaves a guard page at the top. Base-M1 Mesa requests a VM before its
initial zero, scratch, and printf buffer binds.
[Asahi dummy mapping](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L615-L633)
· [UAT geometry](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L244-L262)
· [Mesa VM creation](https://github.com/omacom/mesa/blob/b7b03c5b3b8abe1e040d6056dc62c01b02d3639c/src/asahi/lib/agx_device.c#L1190-L1222)

Vinix mapped 16 KiB but requested four aligned physical pages. Its ARM64 PMM
uses 16 KiB pages, so each live VM reserved 64 KiB for this mapping. The
constructor now derives the page count and alignment from the UAT and PMM
granules. On ARM64 that saves 48 KiB of backing per live VM. Map failure and
VM destruction return the same physical page count. The tested source is
Vinix `7589e9646` plus this patch.

The ASan/UBSan allocator fixture checked 400 contexts and 2,400 driver-buffer
allocations across 16 KiB and 4 KiB PMM models. It verified the dummy page's
backing size, zero contents, mapped address and permissions, and confirmed
physical backing was returned on map failure and destruction. The base source
failed the backing-size assertion with a 65,536-byte allocation. UAT/TLB,
VM geometry and AGX ioctl fixtures, 82 V test files, both kernel builds and
five pinned source gates passed. The allocation scan reproduced the same 178
existing allowance findings.

Vinix publishes a hardware context slot at VM creation. Asahi's G13 queue
acquires a slot when preparing a submission, so VM capacity still differs.
The packaged Mesa device-open sequence and live UAT behavior on M1 remain
unverified. No hardware tests or reboots were performed.
[Asahi queue slot acquisition](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L709-L723)

The tested patch, reference sources, native binaries and logs are under
`/Users/alex/.local/state/vinix/omarchy-m1-vm-dummy-page-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `d579f944c1d87821b189f5289b3f7997d34063d2f72d3c8ddc8f49efb9d817c4` |
| `bundle.tar.gz.inventory.txt` | `f2ec201dfa036b972ff360077b3a2eff2bd9ea7425df293f3265e8a100ce37ff` |
