// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Functions that arrive after boot, and functions that leave.
//
// The boot scan (scan.v) publishes one record per function it finds, and
// drivers and uACPI keep pointers to those records for good. So a record is
// never freed and the list never moves: the list is made with room to spare,
// a function that arrives gets a record at its end, and a function that left
// keeps its record, marked absent, for the next one to arrive at the same
// address.
//
// A function that arrives has no addresses. They are worked out from the
// windows of the bridge it sits behind (window.v) and written here. A bridge
// that arrives is listed and left alone: giving it bus numbers and windows of
// its own is not done, so nothing behind it is found.
module pci

import memory

// How many functions may arrive beyond the ones present at boot.
pub const arrival_room = 64

const absent_vendor = u16(0xffff)
// With the absent vendor: a record that is not to be used again.
const retired_device = u16(0xfffe)

// Whether the record still stands for a function on the bus.
pub fn (dev &PCIDevice) present() bool {
	return dev.vendor_id != absent_vendor
}

// The function is gone. The record stays where its holders can still reach
// it, answers no lookup, and waits for adopt_function() to use it again.
pub fn (mut dev PCIDevice) forget() {
	dev.vendor_id = absent_vendor
	dev.device_id = 0xffff
	dev.class = 0xff
	dev.subclass = 0xff
	dev.prog_if = 0xff
	dev.msi_support = false
	dev.msix_support = false
}

// The function is gone but something still holds its record: the record is
// never used for another function. The next arrival at its address gets a
// record of its own.
pub fn (mut dev PCIDevice) retire() {
	dev.forget()
	dev.device_id = retired_device
}

fn config_peek(bus u8, slot u8, function u8, offset u64, width u32) u32 {
	mut value := u32(0xffffffff)
	checked_config_read(0, bus, slot, function, offset, width, unsafe { &value })
	return value
}

// Whether a function answers at this address now. A device that has only
// just been given power answers nothing, or asks to be tried again, which
// reads as vendor 1.
pub fn function_answers(bus u8, slot u8, function u8) bool {
	vendor := u16(config_peek(bus, slot, function, 0, 2))
	return vendor != 0xffff && vendor != 0 && vendor != 1
}

// Whether the function at this address says its device has more than one.
pub fn function_is_multi(bus u8, slot u8, function u8) bool {
	return config_peek(bus, slot, function, 0x0e, 1) & 0x80 != 0
}

// The record for an address, present or not; nil if it has none that can be
// used.
pub fn record_at(bus u8, slot u8, function u8) &PCIDevice {
	for device in scanned_devices {
		if device.bus == bus && device.slot == slot && device.function == function
			&& !(device.vendor_id == absent_vendor && device.device_id == retired_device) {
			return unsafe { device }
		}
	}
	return unsafe { nil }
}

// The record of the function that is at this address now: the one it already
// has, the one a departed function left behind, or a new one. Nil when
// nothing answers there or the list is full. `parent` is the address of the
// bridge the bus hangs off, as (bus << 8) | (slot << 3) | function, or -1.
pub fn adopt_function(bus u8, slot u8, function u8, parent i64) &PCIDevice {
	if !boot_scan_done || !function_answers(bus, slot, function) {
		return unsafe { nil }
	}
	mut record := record_at(bus, slot, function)
	if record != unsafe { nil } && record.present() {
		return record
	}
	fresh := record == unsafe { nil }
	if fresh {
		if scanned_devices.len >= scanned_devices.cap {
			C.kprintf(c'pci: no room for the function at %llx:%llx.%llx\n', u64(bus), u64(slot),
				u64(function))
			return unsafe { nil }
		}
		// Never freed: see the top of this file.
		record = unsafe { &PCIDevice(memory.malloc_packed_fallible(sizeof(PCIDevice))) }
		if record == unsafe { nil } {
			return unsafe { nil }
		}
	} else {
		record.msix_table_bitmap.release()
	}
	identity := config_peek(bus, slot, function, 0, 4)
	class_revision := config_peek(bus, slot, function, 0x08, 4)
	header := u8(config_peek(bus, slot, function, 0x0e, 1))
	unsafe {
		*record = PCIDevice{
			bus:           bus
			slot:          slot
			function:      function
			parent:        parent
			header_type:   header & 0x7f
			device_id:     u16(identity >> 16)
			vendor_id:     u16(identity)
			revision_id:   u16(u8(class_revision))
			class:         u8(class_revision >> 24)
			subclass:      u8(class_revision >> 16)
			prog_if:       u8(class_revision >> 8)
			multifunction: header & 0x80 != 0
			irq_pin:       u8(config_peek(bus, slot, function, 0x3d, 1))
		}
	}
	caps, status := capabilities_read((u32(bus) << 8) | (u32(slot) << 3) | function, record.header_type,
		native_topology_read)
	if status == topology_ok {
		record.msi_support = caps.msi_offset != 0
		record.msi_offset = caps.msi_offset
		record.msix_support = caps.msix_offset != 0
		record.msix_offset = caps.msix_offset
		record.msix_table_size = caps.msix_entries
		if record.msix_support {
			record.msix_table_bitmap.initialise(caps.msix_entries)
		}
	}
	if fresh {
		// Within the capacity made at boot, so the list does not move under
		// a reader: the record is complete before the length takes it in.
		scanned_devices << record
	}
	C.kprintf(c'pci: Arrived [%llx:%llx:%llx:%lld] %04llx:%04llx\n', u64(bus), u64(slot),
		u64(function), parent, u64(record.vendor_id), u64(record.device_id))
	return record
}

// A bridge's secondary bus: the one directly behind it.
pub fn (dev &PCIDevice) secondary_bus() u8 {
	return dev.read[u8](0x19)
}

// What a bridge forwards to the bus behind it.
pub fn (dev &PCIDevice) forwarded() Windows {
	if dev.header_type != 1 {
		return Windows{}
	}
	return decode_windows(dev.read[u32](0x20), dev.read[u32](0x24), dev.read[u32](0x28),
		dev.read[u32](0x2c), dev.read[u16](0x1c), dev.read[u32](0x30))
}

// Ask each base address register of a function how much it wants, and note
// what it holds now. Sizing a register means writing all ones to it, so the
// function's decoding is off while that is done: for a moment the register
// points at whatever is at the top of the address space.
fn (dev &PCIDevice) add_claims(mut claims Claims) {
	// A bridge has two registers of its own, which nothing here uses.
	if dev.header_type != 0 {
		return
	}
	command := dev.read[u16](0x04)
	dev.write[u16](0x04, command & ~u16(3))
	for index := u8(0); index < 6; index++ {
		register := u32(0x10) + u32(index) * 4
		original := dev.read[u32](register)
		dev.write[u32](register, u32(0xffffffff))
		sized := dev.read[u32](register)
		dev.write[u32](register, original)
		if sized == 0 || sized == 0xffffffff {
			continue
		}
		if sized & 1 != 0 {
			mut mask := sized & ~u32(3)
			if mask & 0xffff0000 == 0 {
				// A register that decodes sixteen bits.
				mask |= 0xffff0000
			}
			claims.add(Claim{
				size:     u64(~mask + 1)
				io:       true
				function: dev.function
				register: index
				address:  u64(original & ~u32(3))
			})
			continue
		}
		wide := (sized >> 1) & 3 == 2
		mut mask := u64(sized & ~u32(0xf)) | 0xffffffff_00000000
		mut address := u64(original & ~u32(0xf))
		if wide && index < 5 {
			upper := dev.read[u32](register + 4)
			dev.write[u32](register + 4, u32(0xffffffff))
			mask = u64(sized & ~u32(0xf)) | (u64(dev.read[u32](register + 4)) << 32)
			dev.write[u32](register + 4, upper)
			address |= u64(upper) << 32
		}
		claims.add(Claim{
			size:         ~mask + 1
			prefetchable: sized & 8 != 0
			wide:         wide
			function:     dev.function
			register:     index
			address:      address
		})
		if wide {
			index++
		}
	}
	dev.write[u16](0x04, command)
}

fn among(dev &PCIDevice, list [8]&PCIDevice, count int) bool {
	for i in 0 .. count {
		if voidptr(list[i]) == voidptr(dev) {
			return true
		}
	}
	return false
}

// Give the functions that have just arrived behind `bridge` their addresses,
// and turn on the decoding of the ones that got any. Every other function on
// that bus keeps what it has. Returns how many registers could not be given
// an address because the bridge's windows have no room for them.
pub fn configure_arrivals(bridge &PCIDevice, arrivals [8]&PCIDevice, count int) int {
	if bridge.header_type != 1 || count <= 0 {
		return 0
	}
	windows := bridge.forwarded()
	// On the stack, by hand: a local handed on as `mut` is otherwise moved to
	// the heap, and nothing would free it.
	mut claims := unsafe { &Claims(C.vinix_stack_alloc(sizeof(Claims))) }
	mut theirs := unsafe { &Claims(C.vinix_stack_alloc(sizeof(Claims))) }
	claims.count = 0
	for i in 0 .. count {
		arrivals[i].add_claims(mut claims)
	}
	if claims.count == 0 {
		return 0
	}
	// Found again with firmware's or an earlier arrival's addresses still
	// in place: nothing to work out.
	if claims.settled(windows) {
		return 0
	}
	secondary := bridge.secondary_bus()
	mut taken := Taken{}
	for device in scanned_devices {
		if device.bus != secondary || !device.present() || among(device, arrivals, count) {
			continue
		}
		theirs.count = 0
		device.add_claims(mut theirs)
		for i in 0 .. theirs.count {
			taken.note(windows, theirs.list[i].address, theirs.list[i].size, theirs.list[i].io)
		}
	}
	placed := claims.place(windows, taken)
	for i in 0 .. count {
		dev := arrivals[i]
		mut enable := u16(0)
		for j in 0 .. claims.count {
			claim := &claims.list[j]
			if claim.function != dev.function {
				continue
			}
			register := u32(0x10) + u32(claim.register) * 4
			if !claim.placed {
				C.kprintf(c'pci: [%llx:%llx:%llx] no room for register %llu (0x%llx bytes)\n',
					u64(dev.bus), u64(dev.slot), u64(dev.function), u64(claim.register),
					claim.size)
				continue
			}
			if claim.io {
				dev.write[u32](register, u32(claim.address) | 1)
				enable |= 1
				continue
			}
			// The low bits of a memory register are read-only: what kind
			// of register it is.
			dev.write[u32](register, u32(claim.address))
			if claim.wide {
				dev.write[u32](register + 4, u32(claim.address >> 32))
			}
			enable |= 2
		}
		// No legacy interrupt line is known for a function firmware never
		// saw; 0xff says so.
		dev.write[u8](0x3c, u8(0xff))
		dev.update_command(0, enable)
	}
	// The bridge has to pass on what its new children decode, and what they
	// send upstream.
	mut forward := u16(0x6)
	if !windows.io.empty() {
		forward |= 1
	}
	bridge.update_command(0, forward)
	return claims.count - placed
}
