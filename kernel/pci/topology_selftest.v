// SPDX-License-Identifier: GPL-2.0-only
module pci

import memory

struct TopologyHeapSnapshot {
mut:
	count int
	sizes [64]u64
	live [64]u64
}

fn topology_test_heap(snapshot &TopologyHeapSnapshot) bool {
	mut output := unsafe { snapshot }
	mut classes := memory.heap_classes() @[freed]
	defer { unsafe { classes.free() } }
	if classes.len > output.live.len { return false }
	output.count = classes.len
	for i, class in classes { output.sizes[i] = class.size; output.live[i] = class.live }
	return true
}

fn topology_test_cycle() bool {
	mut roots := [u8(0)]!
	snapshot, status := topology_build(unsafe { &roots[0] }, 1, native_topology_read, 0)
	if status != topology_ok || snapshot == unsafe { nil } { return false }
	mut valid := snapshot.function_count() == u32(scanned_devices.len)
	budget := 1 + snapshot.bus_count() + snapshot.function_count()
	mut function := snapshot.first_function()
	mut index := 0
	for function != unsafe { nil } {
		if index >= scanned_devices.len { valid = false; break }
		device := scanned_devices[index]
		bdf := (u32(device.bus) << 8) | (u32(device.slot) << 3) | device.function
		identity := (u32(device.device_id) << 16) | device.vendor_id
		class_revision := (u32(device.class) << 24) | (u32(device.subclass) << 16) |
			(u32(device.prog_if) << 8) | u32(device.revision_id)
		if function.bdf != bdf || function.identity != identity || function.class_revision != class_revision
			|| i64(function.parent_bridge_bdf) != device.parent
			|| function.header_type != device.header_type || function.irq_pin != device.irq_pin
			|| function.multifunction != device.multifunction { valid = false }
		caps, cap_status := capabilities_read(bdf, function.header_type, native_topology_read)
		if cap_status == topology_ok {
			if caps.msi_offset != device.msi_offset || caps.msix_offset != device.msix_offset
				|| caps.msix_entries != device.msix_table_size
				|| device.msi_support != (caps.msi_offset != 0)
				|| device.msix_support != (caps.msix_offset != 0) { valid = false }
		} else {
			// Boot retains a device with rejected capabilities, without granting
			// either MSI privilege or allocating an MSI-X vector bitmap.
			if device.msi_support || device.msix_support || device.msi_offset != 0
				|| device.msix_offset != 0 || device.msix_table_size != 0 { valid = false }
		}
		function = function.next_function()
		index++
	}
	// No function, bus or callback is borrowed past this destruction.
	topology_destroy(snapshot)
	if !valid || index != scanned_devices.len { return false }
	for attempt := u32(1); attempt <= budget; attempt++ {
		failed, error := topology_build(unsafe { &roots[0] }, 1, native_topology_read, attempt)
		if error != topology_no_memory || failed != unsafe { nil } {
			topology_destroy(failed)
			return false
		}
	}
	// A failure index past the exact owned allocation count must not fail.
	complete, complete_status := topology_build(unsafe { &roots[0] }, 1, native_topology_read, budget + 1)
	if complete_status != topology_ok || complete == unsafe { nil } {
		topology_destroy(complete)
		return false
	}
	topology_destroy(complete)
	return true
}

// Optional boot fixture, valid even before native CPU-local/task publication.
// Only actual configuration reads and native heap operations run here. There
// are no workers, task queries, fake BDFs, BAR probes or configuration writes.
pub fn topology_native_selftest() bool {
	for i in 0 .. 3 {
		before := memory.free_bytes()
		if !topology_test_cycle() { return false }
		C.kprintf(c'pci: topology lifecycle warmup %lld free-byte baseline=%llu after=%llu\n',
			i64(i + 1), before, memory.free_bytes())
	}
	mut before := TopologyHeapSnapshot{}
	mut after := TopologyHeapSnapshot{}
	if !topology_test_heap(unsafe { &before }) { return false }
	free_before := memory.free_bytes()
	if !topology_test_cycle() || !topology_test_heap(unsafe { &after }) { return false }
	free_after := memory.free_bytes()
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] { equal = false }
	}
	C.kprintf(c'pci: topology fourth lifecycle free-byte baseline=%llu after=%llu heap_equal=%lld\n',
		free_before, free_after, i64(equal))
	return free_before == free_after && equal
}
