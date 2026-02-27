@[has_globals]
module virtio_input

import memory
import aarch64.cpu
import aarch64.uart
import dev.keyboard

// Virtio MMIO register offsets (legacy v1 + shared)
const reg_magic = u64(0x000)
const reg_version = u64(0x004)
const reg_device_id = u64(0x008)
const reg_status = u64(0x070)
const reg_queue_sel = u64(0x030)
const reg_queue_num_max = u64(0x034)
const reg_queue_num = u64(0x038)
const reg_queue_notify = u64(0x050)
const reg_interrupt_status = u64(0x060)
const reg_interrupt_ack = u64(0x064)
const reg_host_features = u64(0x010)
const reg_guest_features = u64(0x020)
// Legacy v1 only
const reg_guest_page_size = u64(0x028)
const reg_queue_align = u64(0x03c)
const reg_queue_pfn = u64(0x040)

// Virtio status bits
const status_acknowledge = u32(1)
const status_driver = u32(2)
const status_driver_ok = u32(4)

// Virtio descriptor flags
const vring_desc_f_write = u16(2)

// Device IDs
const virtio_id_input = u32(18)
const virtio_magic_val = u32(0x74726976)

// Queue size
const queue_size = u64(16)
// Queue alignment for legacy MMIO (used ring alignment)
const queue_align = u64(256)

// MMIO transport for QEMU virt
const mmio_base = u64(0x0a000000)
const mmio_slot_size = u64(0x200)
const mmio_slot_count = u64(32)

// Linux input event types
const ev_key = u16(1)

// Linux keycodes for extended keys
const key_up = u16(103)
const key_down = u16(108)
const key_left = u16(105)
const key_right = u16(106)
const key_home = u16(102)
const key_end = u16(107)
const key_pageup = u16(104)
const key_pagedown = u16(109)
const key_delete = u16(111)

// Linux keycodes for modifiers
const key_leftshift = u16(42)
const key_rightshift = u16(54)
const key_leftctrl = u16(29)
const key_rightctrl = u16(97)
const key_leftalt = u16(56)
const key_rightalt = u16(100)
const key_capslock = u16(58)

// MMIO accessors with compiler barriers to prevent LDP/STP generation.
// STP (store pair) doesn't set ESR_EL2.ISV, crashing QEMU's HVF handler.
fn mmio_r32(addr u64) u32 {
	val := unsafe { *&u32(addr) }
	cpu.dmb_ish()
	return val
}

fn mmio_w32(addr u64, val u32) {
	cpu.dmb_ish()
	unsafe { *&u32(addr) = val }
}

__global (
	vi_dev_base      = u64(0)
	vi_vq_avail_virt = u64(0)
	vi_vq_used_virt  = u64(0)
	vi_events_virt   = u64(0)
	vi_last_used_idx = u16(0)
	vi_shift_active  = false
	vi_ctrl_active   = false
	vi_alt_active    = false
	vi_caps_active   = false
	vi_outbuf        [64]u8
	vi_outlen        = u64(0)
)

fn vi_put(b u8) {
	if vi_outlen < 64 {
		vi_outbuf[vi_outlen] = b
		vi_outlen++
	}
}

fn vi_emit_arrow(final u8) {
	vi_put(0x1b)
	vi_put(u8(`[`))
	vi_put(final)
}

fn vi_emit_tilde(num u8) {
	vi_put(0x1b)
	vi_put(u8(`[`))
	vi_put(num)
	vi_put(u8(`~`))
}

fn process_key(code u16, value u32) {
	// Handle modifier keys (track press/release state)
	match code {
		key_leftshift, key_rightshift {
			vi_shift_active = value != 0
			return
		}
		key_leftctrl, key_rightctrl {
			vi_ctrl_active = value != 0
			return
		}
		key_leftalt, key_rightalt {
			vi_alt_active = value != 0
			return
		}
		key_capslock {
			if value == 1 {
				vi_caps_active = !vi_caps_active
			}
			return
		}
		else {}
	}

	// Only process on press (1) or repeat (2), not release (0)
	if value == 0 {
		return
	}

	// Extended keys (outside conversion table range)
	match code {
		key_up {
			vi_emit_arrow(u8(`A`))
			return
		}
		key_down {
			vi_emit_arrow(u8(`B`))
			return
		}
		key_right {
			vi_emit_arrow(u8(`C`))
			return
		}
		key_left {
			vi_emit_arrow(u8(`D`))
			return
		}
		key_home {
			vi_emit_tilde(u8(`1`))
			return
		}
		key_end {
			vi_emit_tilde(u8(`4`))
			return
		}
		key_pageup {
			vi_emit_tilde(u8(`5`))
			return
		}
		key_pagedown {
			vi_emit_tilde(u8(`6`))
			return
		}
		key_delete {
			vi_emit_tilde(u8(`3`))
			return
		}
		else {}
	}

	// Regular keys — use shared conversion tables
	c := keyboard.translate(u8(code), vi_shift_active, vi_caps_active, vi_ctrl_active)
	if c == 0 {
		return
	}
	vi_put(c)
}

pub fn initialise(hhdm u64) {
	for i := u64(0); i < mmio_slot_count; i++ {
		base := hhdm + mmio_base + i * mmio_slot_size

		if mmio_r32(base + reg_magic) != virtio_magic_val {
			continue
		}
		if mmio_r32(base + reg_device_id) != virtio_id_input {
			continue
		}

		uart.puts(c'virtio-input: found at slot ')
		uart.put_dec(i)
		uart.puts(c'\n')

		// Virtio legacy (v1) handshake
		mmio_w32(base + reg_status, 0) // Reset
		mmio_w32(base + reg_status, status_acknowledge)
		mmio_w32(base + reg_status, status_acknowledge | status_driver)
		mmio_w32(base + reg_guest_features, 0) // Accept no features
		mmio_w32(base + reg_guest_page_size, 4096)

		// Configure virtqueue 0
		mmio_w32(base + reg_queue_sel, 0)
		max_q := mmio_r32(base + reg_queue_num_max)
		if max_q == 0 {
			uart.puts(c'virtio-input: queue 0 not available\n')
			continue
		}
		qsz := if max_q < u32(queue_size) { u64(max_q) } else { queue_size }
		mmio_w32(base + reg_queue_num, u32(qsz))
		mmio_w32(base + reg_queue_align, u32(queue_align))

		// Allocate one page for virtqueue structures + event buffers
		// Legacy vring layout (device computes same offsets from QueuePFN):
		//   desc  = base
		//   avail = base + num*16
		//   used  = align_up(avail + 4 + 2*num + 2, queue_align)
		// For num=16, align=256: desc=0x000, avail=0x100, used=0x200, events=0x300
		page_phys := u64(memory.pmm_alloc(1))
		page_virt := page_phys + hhdm
		events_phys := page_phys + 0x300

		avail_off := u64(qsz) * 16
		used_off := (avail_off + 4 + 2 * u64(qsz) + 2 + queue_align - 1) & ~(queue_align - 1)
		vi_vq_avail_virt = page_virt + avail_off
		vi_vq_used_virt = page_virt + used_off
		vi_events_virt = page_virt + 0x300

		mmio_w32(base + reg_queue_pfn, u32(page_phys / 4096))

		// Set up descriptors: each points to an 8-byte event buffer (device-writable)
		for j := u64(0); j < qsz; j++ {
			doff := page_virt + j * 16
			unsafe {
				*&u64(doff) = events_phys + j * 8 // addr
				*&u32(doff + 8) = 8 // len
				*&u16(doff + 12) = vring_desc_f_write // flags
				*&u16(doff + 14) = 0 // next
			}
		}

		// Fill available ring with all descriptors
		for j := u64(0); j < qsz; j++ {
			unsafe { *&u16(vi_vq_avail_virt + 4 + j * 2) = u16(j) }
		}
		cpu.dmb_ish()
		unsafe { *&u16(vi_vq_avail_virt + 2) = u16(qsz) } // avail.idx

		mmio_w32(base + reg_status, status_acknowledge | status_driver | status_driver_ok)
		mmio_w32(base + reg_queue_notify, 0) // Notify: buffers available

		vi_dev_base = base
		vi_last_used_idx = 0

		uart.puts(c'virtio-input: ready, queue=')
		uart.put_dec(qsz)
		uart.puts(c'\n')
		return
	}

	uart.puts(c'virtio-input: no device found\n')
}

pub fn poll() {
	if vi_dev_base == 0 {
		return
	}

	vi_outlen = 0

	cpu.dmb_ish()

	new_idx := unsafe { *&u16(vi_vq_used_virt + 2) }
	if vi_last_used_idx == new_idx {
		return
	}

	mut avail_idx := unsafe { *&u16(vi_vq_avail_virt + 2) }

	for vi_last_used_idx != new_idx {
		ring_idx := u64(vi_last_used_idx % u16(queue_size))
		used_entry := vi_vq_used_virt + 4 + ring_idx * 8
		desc_id := unsafe { *&u32(used_entry) }

		event_addr := vi_events_virt + u64(desc_id) * 8
		ev_type := unsafe { *&u16(event_addr) }
		ev_code := unsafe { *&u16(event_addr + 2) }
		ev_value := unsafe { *&u32(event_addr + 4) }

		if ev_type == ev_key {
			process_key(ev_code, ev_value)
		}

		// Re-add descriptor to available ring
		avail_ring_pos := u64(avail_idx % u16(queue_size))
		unsafe { *&u16(vi_vq_avail_virt + 4 + avail_ring_pos * 2) = u16(desc_id) }
		avail_idx++

		vi_last_used_idx++
	}

	// Update avail index and notify device
	cpu.dmb_ish()
	unsafe { *&u16(vi_vq_avail_virt + 2) = avail_idx }
	mmio_w32(vi_dev_base + reg_queue_notify, 0)

	// Acknowledge any pending interrupts
	isr := mmio_r32(vi_dev_base + reg_interrupt_status)
	if isr != 0 {
		mmio_w32(vi_dev_base + reg_interrupt_ack, isr)
	}
}
