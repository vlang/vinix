@[has_globals]
module pci

import memory

__global (
	scanned_devices []&PCIDevice
	boot_scan_done bool
)

// This is a native V callback, not a Linux PCI configuration ABI. The actual
// checked transport releases its lock before the caller allocates a record.
pub fn native_topology_read(bdf u32, offset u16, width u8) (u32, int) {
	mut value := u32(0)
	status := checked_config_read(0, bdf >> 8, (bdf >> 3) & 31, bdf & 7,
		u64(offset), u32(width), unsafe { &value })
	return value, int(status)
}

pub fn initialise() {
	// Devices escape to drivers and uACPI as permanent borrowed pointers. This
	// is boot publication, never live replacement or a hotplug/rescan interface.
	if boot_scan_done { return }
	print('pci: Building device scan\n')
	// Existing platform setup supports domain-zero root bus zero. Neither a
	// host bridge's function number nor an MCFG aperture establishes other
	// roots; firmware SEG/BBN/CRS root discovery remains a separate dependency.
	mut roots := [u8(0)]!
	snapshot, status := topology_build(unsafe { &roots[0] }, 1, native_topology_read, 0)
	if status != topology_ok {
		C.kprintf(c'pci: read-only topology failed, status=%lld\n', i64(status))
		panic('pci: cannot construct a valid configured topology')
	}
	// The exact capacity prevents growth from retaining old array buffers.
	mut boot_records := []&PCIDevice{cap: int(snapshot.function_count())}
	boot_records.flags |= .noslices
	mut function := snapshot.first_function()
	for function != unsafe { nil } {
		mut device := unsafe { &PCIDevice(memory.malloc_packed_fallible(sizeof(PCIDevice))) }
		if device == unsafe { nil } {
			// No capability bitmap exists yet, and no device has escaped.
			for previous in boot_records { memory.free(previous) }
			unsafe { boot_records.free() }
			topology_destroy(snapshot)
			panic('pci: device publication allocation failed')
		}
		unsafe {
			*device = PCIDevice{
				bus: u8(function.bdf >> 8)
				slot: u8((function.bdf >> 3) & 31)
				function: u8(function.bdf & 7)
				parent: i64(function.parent_bridge_bdf)
				header_type: function.header_type
				device_id: u16(function.identity >> 16)
				vendor_id: u16(function.identity)
				revision_id: u16(u8(function.class_revision))
				class: u8(function.class_revision >> 24)
				subclass: u8(function.class_revision >> 16)
				prog_if: u8(function.class_revision >> 8)
				multifunction: function.multifunction
				irq_pin: function.irq_pin
			}
		}
		boot_records << device
		function = function.next_function()
	}
	// Only scalar fields were copied. No published device borrows graph nodes.
	topology_destroy(snapshot)
	for mut device in boot_records {
		caps, cap_status := capabilities_read((u32(device.bus) << 8) |
			(u32(device.slot) << 3) | device.function, device.header_type, native_topology_read)
		if cap_status == topology_ok {
			device.msi_support = caps.msi_offset != 0
			device.msi_offset = caps.msi_offset
			device.msix_support = caps.msix_offset != 0
			device.msix_offset = caps.msix_offset
			device.msix_table_size = caps.msix_entries
			if device.msix_support { device.msix_table_bitmap.initialise(caps.msix_entries) }
		} else {
			C.kprintf(c'pci: rejecting interrupt capabilities for BDF=%u, status=%lld\n',
				(u32(device.bus) << 8) | (u32(device.slot) << 3) | device.function, i64(cap_status))
		}
		C.kprintf(c'pci: Found [%llx:%llx:%llx:%lld]\n', u64(device.bus), u64(device.slot),
			u64(device.function), i64(device.parent))
	}
	// Transfer the unique vector backing store into its permanent boot owner.
	scanned_devices = unsafe { boot_records }
	boot_scan_done = true
	$if pci_topology_test ? {
		if !topology_native_selftest() { panic('pci: native topology self-test failed') }
		C.kprintf(c'pci: native bounded topology, read-only capabilities and rollback passed; no pages or heap objects retained\n')
	}
}

pub fn get_device_by_vendor(vendor_id u16, device_id u16, index u32) ?&PCIDevice {
	mut count := 0
	for device in scanned_devices {
		if device.vendor_id == vendor_id && device.device_id == device_id {
			if count == index {
				return unsafe { device }
			} else {
				count += 1
			}
		}
	}
	return none
}

pub fn get_device_by_coordinates(bus u8, slot u8, function u8, index u32) ?&PCIDevice {
	mut count := 0
	for device in scanned_devices {
		if device.bus == bus && device.slot == slot && device.function == function {
			if count == index {
				return unsafe { device }
			} else {
				count += 1
			}
		}
	}
	return none
}

pub fn get_device_by_class(class u8, subclass u8, progif u8, index u32) ?&PCIDevice {
	mut count := 0
	for device in scanned_devices {
		if device.class == class && device.subclass == subclass && device.prog_if == progif {
			if count == index {
				return unsafe { device }
			} else {
				count += 1
			}
		}
	}
	return none
}
