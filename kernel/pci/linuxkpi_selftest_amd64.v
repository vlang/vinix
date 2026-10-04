// SPDX-License-Identifier: GPL-2.0-or-later
module pci

// The boot scan retains its records for the kernel's lifetime. This fixture
// copies scalar identity fields only; it never publishes a Linux PCI device
// or retains any of the caller's output pointers.
@[export: 'vinix_linuxkpi_pci_identity']
fn linuxkpi_pci_identity(index u32, bdf &u32, identity &u32, class_revision &u32) int {
	$if linuxkpi ? {
		if bdf == unsafe { nil } || identity == unsafe { nil } ||
			class_revision == unsafe { nil } {
			return -22
		}
		if u64(index) >= u64(scanned_devices.len) {
			return -2
		}
		dev := scanned_devices[int(index)]
		unsafe {
			*bdf = (u32(dev.bus) << 8) | (u32(dev.slot) << 3) | dev.function
			*identity = (u32(dev.device_id) << 16) | dev.vendor_id
			*class_revision = (u32(dev.class) << 24) | (u32(dev.subclass) << 16) |
				(u32(dev.prog_if) << 8) | (u32(dev.revision_id) & 0xff)
		}
		return 0
	}
	return -22
}
