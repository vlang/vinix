// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// PCI configuration space across a sleep that powers the bus down.
//
// A function that loses power forgets what firmware and the kernel wrote into
// its configuration space: where its memory and ports are, whether it may use
// them or the bus, which interrupt it is on, and for a bridge which buses and
// address windows lie behind it. A driver's resume cannot start from there --
// it reaches its device through a BAR that reads zero -- so before a suspend
// to RAM the whole 256 bytes of every function the core knows are read out
// (pci_save_all()), and afterwards, before the first driver resumes, written
// back (pci_restore_all()).
//
// Written back in an order, not as a block: a function is first brought to
// D0, where its registers can be written at all; the address registers and a
// bridge's windows go in before the command register switches decoding on;
// the read-only words, the status register (whose bits clear when written)
// and the self-test register are not written; then the MSI and MSI-X
// capabilities; the command register last. The order and the read-back are
// those of Linux's pci_restore_state(). Devices are walked in the order they
// were added, so a bridge is restored before what is behind it.
//
// An MSI-X table lives in the device's memory, not in configuration space.
// Only its enable and mask bits are restored here; the entries are the
// driver's to write again, as it wrote them. The control registers of the
// PCI Express capability are restored as well: a hot-plug port's slot power
// and lights are among them.
//
// A function that left the machine before the sleep is not saved, and one
// that left during it is found not to be what it was and is left alone: its
// driver's resume fails and recovery deals with it, or the hot-plug thread
// notices the empty slot.
//
// A driver that has no suspend and resume leaves its device running through
// a sleep, which is right for suspend to idle. Through a loss of power it is
// not: the device comes back blank and the driver goes on as if nothing had
// happened. pci_power_down_blocker() names such a device, and a deep sleep
// is refused while there is one.
@[has_globals]
module devcore

import pci

const pci_state_words = 64

const pci_command = u32(0x04)
const pci_status = u32(0x06)
const pci_cache_line = u32(0x0c)
const pci_latency = u32(0x0d)
const pci_header = u32(0x0e)
const pci_capabilities = u32(0x34)
const pci_interrupt_line = u32(0x3c)
const pci_bridge_control = u32(0x3e)
const pci_status_has_capabilities = u32(1) << 4

const pci_cap_power = u8(0x01)
const pci_cap_msi = u8(0x05)
const pci_cap_msix = u8(0x11)
const pci_power_state_mask = u16(0x3)
const pci_power_pme_status = u16(0x8000)
const pci_msi_64bit = u16(1) << 7
const pci_msi_maskable = u16(1) << 8

// PCI Express capability: the control registers pci/express.v does not name,
// and the one kind of function that has no link registers in version 1.
const pci_express_device_control = u32(0x08)
const pci_express_link_control = u32(0x10)
const pci_express_root_control = u32(0x1c)
const pci_express_device_control_2 = u32(0x28)
const pci_express_link_control_2 = u32(0x30)
const pci_express_integrated_endpoint = u16(9)

// A function takes this long to leave D3, and a register this many tries to
// accept its value while the function is still coming up.
const pci_d0_settle_ms = u64(10)
const pci_write_attempts = 10

struct PciSaved {
mut:
	bdf   i64
	words [pci_state_words]u32
}

__global (
	// One record per PCI function, made the first time they are saved and
	// kept; made again only when there are more functions than it holds.
	devcore_pci_saved    &PciSaved
	devcore_pci_capacity int
	devcore_pci_count    int
	devcore_pci_restores u64
	devcore_pci_missing  u64
	// Registers the last restore found changed.
	devcore_pci_rewritten u64
)

// Whether `dev` is a PCI function that is there to be saved and restored. A
// function that has left the machine keeps its record, marked absent, for
// whoever still holds it: nothing answers at its address.
fn pci_function_present(dev &Device) bool {
	return dev.bus == .pci && dev.state != .removed && dev.pci != unsafe { nil } && dev.pci.present()
}

fn pci_device_count() int {
	mut count := 0
	for i := 0; i < devcore_device_count; i++ {
		if pci_function_present(devcore_devices[i]) {
			count++
		}
	}
	return count
}

// The first bound PCI device whose driver cannot take it through a loss of
// power, or nil. Call with bindings frozen.
pub fn pci_power_down_blocker() &Device {
	for i := 0; i < devcore_device_count; i++ {
		dev := devcore_devices[i]
		if dev.bus != .pci || dev.state != .bound || dev.driver == unsafe { nil } {
			continue
		}
		if dev.driver.suspend == unsafe { nil } || dev.driver.resume == unsafe { nil } {
			return dev
		}
	}
	return unsafe { nil }
}

// Read out the configuration space of every PCI function. Call with bindings
// frozen and the drivers suspended, so that what is read is what they left.
// False when there is no memory to keep it in.
pub fn pci_save_all() bool {
	wanted := pci_device_count()
	if wanted > devcore_pci_capacity {
		if devcore_pci_saved != unsafe { nil } {
			unsafe { free(devcore_pci_saved) }
		}
		devcore_pci_count = 0
		devcore_pci_capacity = 0
		// Room for what a rescan may add before the next sleep.
		capacity := wanted + 8
		devcore_pci_saved = unsafe { &PciSaved(malloc(u64(capacity) * sizeof(PciSaved))) }
		if devcore_pci_saved == unsafe { nil } {
			return false
		}
		devcore_pci_capacity = capacity
	}
	mut count := 0
	for i := 0; i < devcore_device_count && count < devcore_pci_capacity; i++ {
		dev := devcore_devices[i]
		if !pci_function_present(dev) {
			continue
		}
		mut record := unsafe { &devcore_pci_saved[count] }
		record.bdf = pci_bdf(dev.pci)
		for word in 0 .. pci_state_words {
			record.words[word] = dev.pci.read[u32](u32(word * 4))
		}
		count++
	}
	devcore_pci_count = count
	return true
}

fn pci_saved_for(bdf i64) &PciSaved {
	for i in 0 .. devcore_pci_count {
		if unsafe { devcore_pci_saved[i].bdf } == bdf {
			return unsafe { &devcore_pci_saved[i] }
		}
	}
	return unsafe { nil }
}

fn (saved &PciSaved) byte_at(offset u32) u8 {
	return u8(saved.words[offset / 4] >> ((offset & 3) * 8))
}

fn (saved &PciSaved) word_at(offset u32) u16 {
	return u16(saved.words[offset / 4] >> ((offset & 2) * 8))
}

// Write one saved double word back, unless the register already holds it. A
// function that has just been powered up may ignore the first writes, so the
// address registers are read back and written again.
fn pci_put_word(p &pci.PCIDevice, saved &PciSaved, word int, attempts int, always bool) {
	offset := u32(word * 4)
	value := saved.words[word]
	found := p.read[u32](offset)
	if found != value {
		devcore_pci_rewritten++
	} else if !always {
		return
	}
	for attempt := 0; attempt < attempts; attempt++ {
		p.write[u32](offset, value)
		if attempts == 1 || p.read[u32](offset) == value {
			return
		}
		sleep_ms(1)
	}
}

// The offset of capability `id` in the saved image, or 0. The list is walked
// in the image, which is what the function had; a list that loops or leaves
// the capability area ends the walk.
fn (saved &PciSaved) capability(id u8) u32 {
	if u32(saved.word_at(pci_status)) & pci_status_has_capabilities == 0 {
		return 0
	}
	mut offset := u32(saved.byte_at(pci_capabilities)) & ~u32(3)
	for _ in 0 .. 48 {
		if offset < 0x40 || offset > 0xfc {
			return 0
		}
		if saved.byte_at(offset) == id {
			return offset
		}
		offset = u32(saved.byte_at(offset + 1)) & ~u32(3)
	}
	return 0
}

// Bring a function to D0, where it listens. One left in D3 by firmware, or by
// a driver before the sleep, would take the writes that follow and keep none.
fn pci_wake_function(p &pci.PCIDevice, saved &PciSaved) {
	power := saved.capability(pci_cap_power)
	if power == 0 {
		return
	}
	control := p.read[u16](power + 4)
	if control & pci_power_state_mask == 0 {
		return
	}
	// The PME status bit clears when written as one; it is written as zero.
	p.write[u16](power + 4, control & ~(pci_power_state_mask | pci_power_pme_status))
	sleep_ms(pci_d0_settle_ms)
}

fn pci_restore_msi(p &pci.PCIDevice, saved &PciSaved) {
	msi := saved.capability(pci_cap_msi)
	if msi != 0 {
		control := saved.word_at(msi + 2)
		// Off while its address and data are written.
		p.write[u16](msi + 2, control & ~u16(1))
		p.write[u32](msi + 4, saved.words[(msi + 4) / 4])
		mut data := msi + 8
		if control & pci_msi_64bit != 0 {
			p.write[u32](msi + 8, saved.words[(msi + 8) / 4])
			data = msi + 12
		}
		p.write[u16](data, saved.word_at(data))
		if control & pci_msi_maskable != 0 && data + 4 <= 0xfc {
			p.write[u32](data + 4, saved.words[(data + 4) / 4])
		}
		p.write[u16](msi + 2, control)
	}
	msix := saved.capability(pci_cap_msix)
	if msix != 0 {
		p.write[u16](msix + 2, saved.word_at(msix + 2))
	}
}

// The control registers of a PCI Express function: what it may report and
// how, its link's settings, and for a port with a slot the slot's power
// switch and lights. Which of them a function has goes by the version of
// the capability and the kind of function, both in the saved image. Without
// this a slot the kernel had switched off comes back powered, and a card
// that was taken out of use is live again with nobody driving it.
fn pci_restore_express(p &pci.PCIDevice, saved &PciSaved) {
	express := saved.capability(pci.capability_express)
	if express == 0 {
		return
	}
	flags := saved.word_at(express + pci.express_flags)
	version := flags & 0xf
	kind := (flags >> 4) & 0xf
	has_link := version > 1 || kind != pci_express_integrated_endpoint
	is_port := kind == pci.express_type_root_port || kind == pci.express_type_downstream
	has_slot := is_port && flags & pci.express_flag_slot != 0
	p.write[u16](express + pci_express_device_control, saved.word_at(express + pci_express_device_control))
	if has_link {
		p.write[u16](express + pci_express_link_control, saved.word_at(express + pci_express_link_control))
	}
	if has_slot {
		p.write[u16](express + pci.express_slot_control, saved.word_at(express + pci.express_slot_control))
	}
	if kind == pci.express_type_root_port {
		p.write[u16](express + pci_express_root_control, saved.word_at(express + pci_express_root_control))
	}
	if version > 1 && express + pci_express_link_control_2 + 2 <= 0x100 {
		p.write[u16](express + pci_express_device_control_2, saved.word_at(express + pci_express_device_control_2))
		if has_link {
			p.write[u16](express + pci_express_link_control_2, saved.word_at(express + pci_express_link_control_2))
		}
	}
}

// One function. False when it is not there any more, or is not what it was.
fn pci_restore_function(p &pci.PCIDevice, saved &PciSaved) bool {
	if p.read[u32](0) != saved.words[0] {
		return false
	}
	pci_wake_function(p, saved)
	bridge := saved.byte_at(pci_header) & 0x7f == 1
	if bridge {
		// Expansion ROM and bridge control, then the windows -- the
		// prefetchable ones always, as some bridges forget them without
		// showing it -- then the buses and the two address registers.
		p.write[u16](pci_bridge_control, saved.word_at(pci_bridge_control))
		pci_put_word(p, saved, 14, 1, false)
		pci_put_word(p, saved, 12, 1, false)
		for word := 11; word >= 9; word-- {
			pci_put_word(p, saved, word, 1, true)
		}
		for word := 8; word >= 4; word-- {
			pci_put_word(p, saved, word, 1, false)
		}
	} else {
		// Subsystem and expansion ROM, then the address registers.
		for word := 12; word >= 10; word-- {
			pci_put_word(p, saved, word, 1, false)
		}
		for word := 9; word >= 4; word-- {
			pci_put_word(p, saved, word, pci_write_attempts, false)
		}
	}
	p.write[u8](pci_interrupt_line, saved.byte_at(pci_interrupt_line))
	p.write[u8](pci_cache_line, saved.byte_at(pci_cache_line))
	p.write[u8](pci_latency, saved.byte_at(pci_latency))
	pci_restore_msi(p, saved)
	pci_restore_express(p, saved)
	// Last: decoding and bus mastering as they were, now that there is
	// something to decode. Sixteen bits, leaving the status register alone.
	if p.read[u16](pci_command) != saved.word_at(pci_command) {
		devcore_pci_rewritten++
	}
	p.write[u16](pci_command, saved.word_at(pci_command))
	return true
}

// Write back what pci_save_all() read, to every function that is still
// there. Call with bindings frozen, before any driver resumes. Returns how
// many functions were not restored: gone, changed, or added since.
pub fn pci_restore_all() int {
	mut missing := 0
	devcore_pci_rewritten = 0
	for i := 0; i < devcore_device_count; i++ {
		dev := devcore_devices[i]
		if !pci_function_present(dev) {
			continue
		}
		saved := pci_saved_for(pci_bdf(dev.pci))
		if saved == unsafe { nil } || !pci_restore_function(dev.pci, saved) {
			missing++
			C.kprintf(c'devcore: %.*s was not restored after the sleep\n', i32(dev.name.len), dev.name.str)
		}
	}
	devcore_pci_restores++
	devcore_pci_missing += u64(missing)
	return missing
}

// What the last pci_restore_all() did: how many functions it had a record
// for, how many of their registers it found changed and wrote back, and how
// many functions have gone unrestored over the life of the machine. A
// restore that found nothing changed was a restore after a sleep in which
// nothing lost power.
pub fn pci_restore_report() (int, u64, u64) {
	return devcore_pci_count, devcore_pci_rewritten, devcore_pci_missing
}
