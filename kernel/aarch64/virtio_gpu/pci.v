// SPDX-License-Identifier: GPL-2.0-or-later
module virtio_gpu

import aarch64.cpu
import aarch64.uart
import memory
import pci

fn mmio_r8(addr u64) u8 {
	value := unsafe { *&u8(addr) }
	cpu.dmb_ish()
	return value
}

fn mmio_r16(addr u64) u16 {
	value := unsafe { *&u16(addr) }
	cpu.dmb_ish()
	return value
}

fn mmio_w8(addr u64, value u8) {
	cpu.dmb_ish()
	unsafe { *&u8(addr) = value }
}

fn mmio_w16(addr u64, value u16) {
	cpu.dmb_ish()
	unsafe { *&u16(addr) = value }
}

fn mmio_w64(addr u64, value u64) {
	cpu.dmb_ish()
	unsafe { *&u64(addr) = value }
}

// Modern VirtIO PCI capabilities describe the registers and the host-visible
// BAR separately. Firmware has assigned their bus addresses before boot.
fn initialise_pci(hhdm u64) bool {
	dev := pci.get_device_by_vendor(0x1af4, 0x1050, 0) or { return false }
	mut common := u64(0)
	mut notify := u64(0)
	mut isr := u64(0)
	mut config := u64(0)
	mut multiplier := u32(0)
	mut host_base := u64(0)
	mut host_size := u64(0)
	mut cap := dev.read[u8](0x34)
	for _ in 0 .. 64 {
		if cap < 0x40 { break }
		next := dev.read[u8](u32(cap) + 1)
		if dev.read[u8](cap) == 9 && dev.read[u8](u32(cap) + 2) >= 16 {
			kind := dev.read[u8](u32(cap) + 3)
			bar_index := dev.read[u8](u32(cap) + 4)
			if bar_index < 6 {
				bar := dev.get_bar(bar_index)
				offset := u64(dev.read[u32](u32(cap) + 8))
				length := u64(dev.read[u32](u32(cap) + 12))
				if kind == 8 && dev.read[u8](u32(cap) + 2) >= 24 && dev.read[u8](u32(cap) + 5) == 1 {
					full_offset := offset | (u64(dev.read[u32](u32(cap) + 16)) << 32)
					full_length := length | (u64(dev.read[u32](u32(cap) + 20)) << 32)
					if bar.base != 0 && full_offset <= bar.size && full_length <= bar.size - full_offset {
						host_base = bar.base + full_offset
						host_size = full_length
					}
				} else if bar.base != 0 && offset <= bar.size && length <= bar.size - offset && length != 0 {
					address := memory.map_mmio(bar.base + offset, length)
					match kind {
						1 {
							if length >= 56 { common = address }
						}
						2 {
							if dev.read[u8](u32(cap) + 2) >= 20 {
								notify = address
								multiplier = dev.read[u32](u32(cap) + 16)
							}
						}
						3 { isr = address }
						4 {
							if length >= 16 { config = address }
						}
						else {}
					}
				}
			}
		}
		if next == cap { return false }
		cap = next
	}
	if common == 0 || notify == 0 || isr == 0 || config == 0 { return false }
	dev.write[u16](4, dev.read[u16](4) | 6)
	mmio_w8(common + 20, 0)
	mmio_w8(common + 20, 3)
	mmio_w32(common, 1)
	if mmio_r32(common + 4) & 1 == 0 { return false } // VIRTIO_F_VERSION_1
	mmio_w32(common, 0)
	offered := mmio_r32(common + 4)
	if offered & virtio_gpu_f_virgl == 0 { return false }
	features := offered & u32(0x19) // VIRGL, RESOURCE_BLOB, CONTEXT_INIT
	mmio_w32(common + 8, 1)
	mmio_w32(common + 12, 1)
	mmio_w32(common + 8, 0)
	mmio_w32(common + 12, features)
	mmio_w8(common + 20, 11) // FEATURES_OK
	if mmio_r8(common + 20) & 8 == 0 { return false }
	mmio_w16(common + 22, 0)
	maximum := mmio_r16(common + 24)
	if maximum < 2 { return false }
	queue_size := if maximum < wanted_queue_size { maximum } else { wanted_queue_size }
	mmio_w16(common + 24, queue_size)
	avail_offset := u64(queue_size) * 16
	used_offset := align_up(avail_offset + 6 + u64(queue_size) * 2, queue_align)
	queue_bytes := used_offset + 6 + u64(queue_size) * 8
	queue_pages := align_up(queue_bytes, page_size) / page_size
	request_pages := align_up(request_capacity, page_size) / page_size
	response_pages := align_up(response_capacity, page_size) / page_size
	queue_phys := u64(memory.pmm_alloc_fallible(queue_pages))
	if queue_phys == 0 { return false }
	request_phys := u64(memory.pmm_alloc_fallible(request_pages))
	if request_phys == 0 {
		memory.pmm_free(voidptr(queue_phys), queue_pages)
		return false
	}
	response_phys := u64(memory.pmm_alloc_fallible(response_pages))
	if response_phys == 0 {
		memory.pmm_free(voidptr(request_phys), request_pages)
		memory.pmm_free(voidptr(queue_phys), queue_pages)
		return false
	}
	queue_virt := queue_phys + hhdm
	unsafe { C.memset(voidptr(queue_virt), 0, queue_pages * page_size) }
	virtgpu_transport = Transport{
		hhdm:          hhdm
		common:        common
		notify:        notify + u64(mmio_r16(common + 30)) * multiplier
		isr:           isr
		config:        config
		hostmem_base:  host_base
		hostmem_size:  host_size
		features:      features
		queue_size:    queue_size
		desc:          queue_virt
		avail:         queue_virt + avail_offset
		used:          queue_virt + used_offset
		request_phys:  request_phys
		request_virt:  request_phys + hhdm
		response_phys: response_phys
		response_virt: response_phys + hhdm
		next_fence:    1
		ready:         true
	}
	mmio_w64(common + 32, queue_phys)
	mmio_w64(common + 40, queue_phys + avail_offset)
	mmio_w64(common + 48, queue_phys + used_offset)
	mmio_w16(common + 28, 1)
	mmio_w8(common + 20, 15)
	C.kprintf(c'virtio-gpu: PCI transport, features 0x%x, host memory 0x%llx + %llu bytes\n', features, host_base, host_size)
	if !query_capsets() {
		virtgpu_transport.ready = false
		mmio_w8(common + 20, 128)
		return false
	}
	uart.puts(c'virtio-gpu: PCI control queue ready\n')
	return true
}
