Run `V=/path/to/v sh build-support/run-v-tool.sh tests/virtio-net/run.v`.
The V fixture compiles the production policy and checks transitional PCI
identification, I/O BAR bounds, full legacy PCI queue sizes, ARM queue sizing,
split-ring layout, PCI's 4 KiB and MMIO's 16 KiB PFN units, completion-index wrap and RX
descriptor/length rejection. An in-memory transport also exercises the production
queue engine: all partial allocation failures, an unrepresentable PFN, absent
polling, ARM's 64-entry queues, synchronous DHCP/receive callback sends, TX full
and reclaim, malformed/duplicate RX IDs, busy poll locks, missing ANY_LAYOUT,
failed attachment and reset failure with successful DMA disable.
Hardware access, DMA ordering and real stack attachment require both architecture
builds and QEMU boots; these host checks do not replace those gates.

Transport scope: ARM legacy MMIO version 1 and amd64 transitional PCI
1af4:1000 revision 0 with a legacy I/O BAR. Modern-only PCI 1af4:1041 and
MMIO version 2 are not supported. Legacy PCI queues must be power-of-two,
at most 1024 descriptors, and use the full device-advertised size. ANY_LAYOUT
is required for the single-descriptor header-plus-frame layout.

The PCI driver has no suspend/resume callbacks; devcore therefore refuses
deep sleep and hibernation while it is bound. Hotplug and IOMMU behavior need
hardware qualification. An unrecoverable reset AND DMA-disable failure stops
the kernel rather than letting devcore free memory a device may still reach.
