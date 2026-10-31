// SPDX-License-Identifier: GPL-2.0-or-later
// QEMU transitional virtio-9p-pci 1af4:1009, legacy BAR0 port I/O.
module virtio_9p

import devcore
import dma
import pci
import x86.kio

__global ninep_driver &devcore.Driver

// There is deliberately no remove callback. devcore then pins this Device
// record on hot removal instead of reclaiming its DMA domain behind an
// in-flight request or a quarantined queue. This small boot-lifetime binding
// also prevents another driver from binding to the live mount's device.
fn refuse_active_suspend(mut _ devcore.Device) bool { return !ninep_claimed }

fn inactive_resume(mut _ devcore.Device) bool { return !ninep_claimed }

fn (ch &Channel) barrier() {
	asm volatile amd64 { mfence ; ; ; memory }
}

fn (ch &Channel) read16(address u64) u16 { return kio.mmin[u16](unsafe { &u16(address) }) }

fn (ch &Channel) read32(address u64) u32 { return kio.mmin[u32](unsafe { &u32(address) }) }

fn (ch &Channel) page_size() u64 { return 4096 }

fn (mut ch Channel) alloc_dma(bytes u64) ?dma.Buffer {
	return dma.alloc_buffer(mut ch.device, bytes)
}

fn (mut ch Channel) free_dma(buffer dma.Buffer) {
	if buffer.bus != 0 { dma.free_buffer(mut ch.device, buffer) }
}

fn (ch &Channel) set_status(value u8) { kio.port_out[u8](ch.io + 18, value) }

fn (ch &Channel) features() u32 { return kio.port_in[u32](ch.io) }

fn (ch &Channel) accept(value u32) { kio.port_out[u32](ch.io + 4, value) }

fn (ch &Channel) notify() { kio.port_out[u16](ch.io + 16, 0) }

fn (ch &Channel) ack() { _ = kio.port_in[u8](ch.io + 19) }

fn (ch &Channel) queue_max() u32 {
	kio.port_out[u16](ch.io + 14, 0)
	if kio.port_in[u32](ch.io + 8) != 0 { return 0 }
	return kio.port_in[u16](ch.io + 12)
}

fn (ch &Channel) install(address u64) {
	kio.port_out[u16](ch.io + 14, 0)
	kio.port_out[u32](ch.io + 8, u32(address / 4096))
}

fn (ch &Channel) reset() bool {
	if ch.io == 0 { return true }
	ch.set_status(0)
	for _ in 0 .. 10000 { if kio.port_in[u8](ch.io + 18) == 0 { return true } }
	return false
}

fn (ch &Channel) disable() {
	if ch.device != unsafe { nil } {
		ch.device.pci.update_command(4, 1 << 10)
	}
}

fn (mut ch Channel) locate(tag string) bool {
	for index := u32(0); index < 32; index++ {
		card := pci.get_device_by_vendor(0x1af4, 0x1009, index) or { break }
		if !card.present() || card.header_type != 0 || card.revision_id != 0 { continue }
		mut dev := devcore.of_pci(card)
		if dev == unsafe { nil } || (dev.driver != unsafe { nil } && dev.driver != ninep_driver)
			|| dev.state == .removed {
			continue
		}
		bar := card.get_bar(0)
		if bar.is_mmio || bar.base == 0 || bar.base > 65535 || bar.size < 22
			|| bar.size > 65536 - bar.base {
			continue
		}
		bdf := (u32(card.bus) << 8) | (u32(card.slot) << 3) | card.function
		caps, status := pci.capabilities_read(bdf, card.header_type, pci.native_topology_read)
		if status != pci.topology_ok { continue }
		command := card.read[u16](4)
		if command == 0xffff || card.update_command(6, 1 | (1 << 10)) != pci.config_ok { continue }
		mut good := true
		if caps.msi_offset != 0 {
			off := u32(caps.msi_offset) + 2
			ctl := card.read[u16](off)
			good = ctl != 0xffff && card.config_write(off, 2, ctl & ~u16(1)) == pci.config_ok
				&& card.read[u16](off) & 1 == 0
		}
		if good && caps.msix_offset != 0 {
			off := u32(caps.msix_offset) + 2
			ctl := card.read[u16](off)
			good = ctl != 0xffff && card.config_write(off, 2, (ctl & ~u16(0x8000)) | 0x4000) == pci.config_ok
				&& card.read[u16](off) & 0x8000 == 0
		}
		if !good {
			card.write[u16](4, command & ~u16(4))
			continue
		}
		ch.io = u16(bar.base)
		// MSI-X disabled: device config starts at 20, mount_tag_len then bytes.
		length := kio.port_in[u16](ch.io + 20)
		if kio.port_in[u32](ch.io) & 1 == 0 || int(length) != tag.len
			|| u64(length) > bar.size - 22 {
			card.write[u16](4, command & ~u16(4))
			ch.io = 0
			continue
		}
		for i in 0 .. int(length) {
			if kio.port_in[u8](ch.io + 22 + u16(i)) != tag[i] {
				good = false
				break
			}
		}
		if !good {
			card.write[u16](4, command & ~u16(4))
			ch.io = 0
			continue
		}
		if ninep_driver == unsafe { nil } {
			ninep_driver = devcore.register_driver(devcore.Driver{
				name:    'virtio-9p-mounted'
				bus:     .pci
				suspend: refuse_active_suspend
				resume:  inactive_resume
			}) or {
				card.write[u16](4, command & ~u16(4))
				ch.io = 0
				return false
			}
		}
		if dev.driver == unsafe { nil } && !devcore.claim(mut dev, mut ninep_driver) {
			card.write[u16](4, command & ~u16(4))
			ch.io = 0
			return false
		}
		ch.device = dev
		if !ch.reset() {
			ch.quarantined = true
			return false
		}
		dma.set_address_bits(mut dev, 44)
		if card.update_command(2, 5 | (1 << 10)) != pci.config_ok {
			ch.disable()
			return false
		}
		return true
	}
	return false
}
