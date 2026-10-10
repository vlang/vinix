// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The VirtIO transports of a virtual ARM machine: thirty-two memory-mapped
// slots at a fixed address, each either empty or one device.
//
// The drivers for them predate the device core and each looks through the
// slots for its own kind. This lists what is in the slots once they have,
// and says which devices have a working driver by asking the devices: a
// driver that brought one up left DRIVER_OK in its status register, and one
// that gave up left FAILED. So the list is what happened, not what was meant
// to.
module devcore

import aarch64.kio
import lib

// QEMU's `virt` machine: where the slots are and how big each is.
const virtio_mmio_base = u64(0x0a000000)
const virtio_mmio_slot = u64(0x200)
const virtio_mmio_slots = u64(32)

const virtio_magic = u32(0x74726976)
const virtio_reg_device = u64(0x008)
const virtio_reg_vendor = u64(0x00c)
const virtio_reg_status = u64(0x070)
const virtio_status_driver_ok = u32(4)
const virtio_status_failed = u32(0x80)

// The driver for a VirtIO device type, or '' for a type nothing here drives.
fn virtio_driver(kind u32) string {
	return match kind {
		1 { 'virtio_net' }
		2 { 'virtio_blk' }
		16 { 'virtio_gpu' }
		18 { 'virtio_input' }
		25 { 'virtio_snd' }
		else { '' }
	}
}

// List the devices in the VirtIO slots. `hhdm` is where physical memory is
// mapped. Called once every VirtIO driver has had its turn.
pub fn enumerate_virtio_mmio(hhdm u64) {
	mut found := 0
	for slot := u64(0); slot < virtio_mmio_slots; slot++ {
		physical := virtio_mmio_base + slot * virtio_mmio_slot
		base := hhdm + physical
		if kio.mmin32(unsafe { &u32(base) }) != virtio_magic {
			continue
		}
		kind := kio.mmin32(unsafe { &u32(base + virtio_reg_device) })
		if kind == 0 {
			continue
		}
		// Linux's name for it: the address, then what it is.
		mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
		unsafe { *text = lib.new_text(24) }
		text.add_radix(physical, 16, 0)
		text.add('.virtio_mmio')
		name := text.str()
		mut dev := new_device(.platform, name)
		unsafe { name.free() }
		dev.compatible = 'virtio,mmio'
		dev.vendor = u16(kio.mmin32(unsafe { &u32(base + virtio_reg_vendor) }))
		dev.device = u16(kind)
		if !add(mut dev) {
			unsafe {
				dev.name.free()
				free(dev)
			}
			continue
		}
		found++
		status := kio.mmin32(unsafe { &u32(base + virtio_reg_status) })
		driver := virtio_driver(kind)
		if driver.len != 0 && status & virtio_status_driver_ok != 0
			&& status & virtio_status_failed == 0 {
			claim_on(.platform, dev.name, 'virtio,mmio', driver)
		}
	}
	if found != 0 {
		C.kprintf(c'devcore: %lld VirtIO devices listed\n', i64(found))
	}
}
