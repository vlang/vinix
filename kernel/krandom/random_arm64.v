module krandom

import aarch64.cpu
import devicetree
import crypto.sha256
import limine
import memory
import time

const virtio_mmio_base = u64(0x0a000000)
const virtio_mmio_slot_size = u64(0x200)
const virtio_mmio_slot_count = u64(32)
const virtio_magic = u32(0x74726976)
const virtio_id_entropy = u32(4)
const virtio_reg_magic = u64(0x000)
const virtio_reg_device_id = u64(0x008)
const virtio_reg_host_features = u64(0x010)
const virtio_reg_guest_features = u64(0x020)
const virtio_reg_guest_page_size = u64(0x028)
const virtio_reg_queue_sel = u64(0x030)
const virtio_reg_queue_num_max = u64(0x034)
const virtio_reg_queue_num = u64(0x038)
const virtio_reg_queue_align = u64(0x03c)
const virtio_reg_queue_pfn = u64(0x040)
const virtio_reg_queue_notify = u64(0x050)
const virtio_reg_interrupt_status = u64(0x060)
const virtio_reg_interrupt_ack = u64(0x064)
const virtio_reg_status = u64(0x070)
const virtio_status_acknowledge = u32(1)
const virtio_status_driver = u32(2)
const virtio_status_driver_ok = u32(4)
const virtio_descriptor_write = u16(2)
const virtio_queue_pages = u64(2)
const virtio_entropy_timeout_ns = u64(5_000_000_000)

__global (
	arm64_random_state = u64(0x9e3779b97f4a7c15)
)

fn read_counter() u64 {
	mut counter := u64(0)
	asm volatile aarch64 {
		mrs counter, CNTVCT_EL0
		; =r (counter)
	}
	return counter
}

fn next_seed_word() u64 {
	arm64_random_state += 0x9e3779b97f4a7c15
	mut word := arm64_random_state ^ read_counter()
	word = (word ^ (word >> 30)) * 0xbf58476d1ce4e5b9
	word = (word ^ (word >> 27)) * 0x94d049bb133111eb
	return word ^ (word >> 31)
}

fn qemu_entropy_requested() bool {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		return false
	}
	return unsafe { cstring_to_vstring(kernel_file.cmdline) }.contains('vinix.qemu_platform=1')
}

fn virtio_r32(address u64) u32 {
	value := unsafe { *&u32(address) }
	cpu.dmb_ish()
	return value
}

fn virtio_w32(address u64, value u32) {
	cpu.dmb_ish()
	unsafe { *&u32(address) = value }
}

// Pull one boot seed from QEMU's VirtIO entropy device.  The runner backs the
// device with the host CSPRNG, so this is trusted input rather than timer
// jitter.  Resetting the device before freeing the temporary queue also stops
// all DMA references to those pages.
fn virtio_entropy_seed(mut output [64]u8) bool {
	hhdm := memory.get_hhdm_offset()
	for slot := u64(0); slot < virtio_mmio_slot_count; slot++ {
		base := hhdm + virtio_mmio_base + slot * virtio_mmio_slot_size
		if virtio_r32(base + virtio_reg_magic) != virtio_magic
			|| virtio_r32(base + virtio_reg_device_id) != virtio_id_entropy {
			continue
		}

		virtio_w32(base + virtio_reg_status, 0)
		virtio_w32(base + virtio_reg_status, virtio_status_acknowledge)
		virtio_w32(base + virtio_reg_status, virtio_status_acknowledge | virtio_status_driver)
		_ = virtio_r32(base + virtio_reg_host_features)
		virtio_w32(base + virtio_reg_guest_features, 0)
		virtio_w32(base + virtio_reg_guest_page_size, 4096)
		virtio_w32(base + virtio_reg_queue_sel, 0)
		if virtio_r32(base + virtio_reg_queue_num_max) == 0 {
			virtio_w32(base + virtio_reg_status, 0)
			return false
		}
		virtio_w32(base + virtio_reg_queue_num, 1)
		virtio_w32(base + virtio_reg_queue_align, 4096)

		queue_phys_ptr := memory.pmm_alloc(virtio_queue_pages)
		if queue_phys_ptr == unsafe { nil } {
			virtio_w32(base + virtio_reg_status, 0)
			return false
		}
		queue_phys := u64(queue_phys_ptr)
		entropy_phys_ptr := memory.pmm_alloc(1)
		if entropy_phys_ptr == unsafe { nil } {
			memory.pmm_free(queue_phys_ptr, virtio_queue_pages)
			virtio_w32(base + virtio_reg_status, 0)
			return false
		}
		entropy_phys := u64(entropy_phys_ptr)
		queue := queue_phys + hhdm
		entropy := entropy_phys + hhdm
		unsafe {
			C.memset(voidptr(queue), 0, virtio_queue_pages * 4096)
			C.memset(voidptr(entropy), 0, 4096)
			// Descriptor table begins at queue + 0.  The one-entry available
			// ring follows it; the used ring is page-aligned at queue + 4096.
			*&u64(queue) = entropy_phys
			*&u32(queue + 8) = u32(output.len)
			*&u16(queue + 12) = virtio_descriptor_write
			*&u16(queue + 14) = 0
			*&u16(queue + 16 + 4) = 0
		}
		virtio_w32(base + virtio_reg_queue_pfn, u32(queue_phys / 4096))
		virtio_w32(base + virtio_reg_status, virtio_status_acknowledge |
			virtio_status_driver | virtio_status_driver_ok)
		cpu.dmb_ish()
		unsafe { *&u16(queue + 16 + 2) = 1 }
		virtio_w32(base + virtio_reg_queue_notify, 0)

		deadline := time.monotonic_ns() + virtio_entropy_timeout_ns
		mut complete := false
		for time.monotonic_ns() < deadline {
			cpu.dmb_ish()
			if unsafe { *&u16(queue + 4096 + 2) } != 0 {
				used_id := unsafe { *&u32(queue + 4096 + 4) }
				used_length := unsafe { *&u32(queue + 4096 + 8) }
				complete = used_id == 0 && used_length == u32(output.len)
				break
			}
		}
		if complete {
			unsafe { C.memcpy(&output[0], voidptr(entropy), output.len) }
		}
		interrupts := virtio_r32(base + virtio_reg_interrupt_status)
		if interrupts != 0 {
			virtio_w32(base + virtio_reg_interrupt_ack, interrupts)
		}
		virtio_w32(base + virtio_reg_status, 0)
		cpu.dmb_ish()
		unsafe { C.memset(voidptr(entropy), 0, 4096) }
		memory.pmm_free(entropy_phys_ptr, 1)
		memory.pmm_free(queue_phys_ptr, virtio_queue_pages)
		return complete
	}
	return false
}

fn architecture_seed(mut output [64]u8) bool {
	arm64_random_state ^= read_counter()
	for i := 0; i < output.len; i += 8 {
		word := next_seed_word()
		unsafe { C.memcpy(&output[i], &word, 8) }
	}

	chosen := devicetree.find_node('/chosen') or {
		return qemu_entropy_requested() && virtio_entropy_seed(mut output)
	}
	seed := devicetree.get_property(chosen, 'rng-seed') or {
		return qemu_entropy_requested() && virtio_entropy_seed(mut output)
	}
	if seed.len < 32 || seed.len > 4096 {
		return false
	}
	domain := 'Vinix kernel CSPRNG v1'
	mut input := []u8{len: domain.len + int(seed.len) + 1}
	unsafe {
		C.memcpy(input.data, domain.str, domain.len)
		C.memcpy(&input[domain.len], seed.data, seed.len)
	}
	for i in 0 .. 2 {
		input[input.len - 1] = u8(i)
		digest := sha256.sum(input)
		unsafe {
			C.memcpy(&output[i * 32], digest.data, 32)
			C.memset(digest.data, 0, digest.len)
			digest.free()
		}
	}
	unsafe {
		C.memset(input.data, 0, input.len)
		input.free()
	}
	return true
}
