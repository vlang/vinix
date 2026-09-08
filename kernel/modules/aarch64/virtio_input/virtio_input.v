@[has_globals]
module virtio_input

import memory
import aarch64.cpu
import aarch64.uart
import dev.keyboard

fn C.vinix_call_void_fn(callback voidptr)

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

// Virtio input configuration space. `select`/`subsel` choose which table the
// union at `cfg_union` reports, and `cfg_size` is 0 when the device has
// nothing to say about that selection.
const cfg_select = u64(0x100)
const cfg_subsel = u64(0x101)
const cfg_size = u64(0x102)
const cfg_union = u64(0x108)

const cfg_ev_bits = u8(0x11)
const cfg_abs_info = u8(0x12)

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

// A virt machine is given a keyboard and a tablet; four covers both plus room
// for whatever else is on the bus without growing the polled set noticeably.
const max_devices = 4

// Linux input event types
const ev_syn = u16(0)
const ev_key = u16(1)
const ev_rel = u16(2)
const ev_abs = u16(3)

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
const key_tab = u16(15)
const key_leftshift = u16(42)
const key_rightshift = u16(54)
const key_leftctrl = u16(29)
const key_rightctrl = u16(97)
const key_leftalt = u16(56)
const key_rightalt = u16(100)
const key_capslock = u16(58)
const key_leftmeta = u16(125)
const key_rightmeta = u16(126)

// Pointer button codes. The bit a button takes in the reported mask is its
// distance from BTN_LEFT, so left is bit 0, right bit 1, middle bit 2.
const btn_left = u16(0x110)
const btn_last = u16(0x117)

// Pointer axes
const abs_x = u16(0)
const abs_y = u16(1)
const rel_x = u16(0)
const rel_y = u16(1)
const rel_wheel = u16(8)

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

fn mmio_r8(addr u64) u8 {
	val := unsafe { *&u8(addr) }
	cpu.dmb_ish()
	return val
}

fn mmio_w8(addr u64, val u8) {
	cpu.dmb_ish()
	unsafe { *&u8(addr) = val }
}

__global (
	vi_dev_count     = int(0)
	vi_dev_base      [4]u64
	vi_vq_avail_virt [4]u64
	vi_vq_used_virt  [4]u64
	vi_events_virt   [4]u64
	vi_last_used_idx [4]u16
	vi_dev_qsize     [4]u16
	vi_shift_active  = false
	vi_ctrl_active   = false
	vi_alt_active    = false
	vi_caps_active   = false
	// Cmd, and whether a chord was sent while it was down. The desktop's
	// window switcher is drawn for as long as Cmd is held, so unlike every
	// other modifier this one's release has to be reported -- but only to
	// someone who asked, which is what pressing Cmd-Tab counts as.
	vi_meta_active   = false
	vi_meta_chorded  = false
	vi_outbuf        [64]u8
	vi_outlen        = u64(0)
	// Pointer state, shared with /dev/pointer. `x`/`y` are raw device
	// coordinates spanning 0..max, which is what an absolute device reports;
	// a relative device is integrated into the same span so both kinds reach
	// userland as one position.
	vi_ptr_present  = false
	vi_ptr_absolute = false
	vi_ptr_x        = int(0)
	vi_ptr_y        = int(0)
	vi_ptr_max_x    = int(0)
	vi_ptr_max_y    = int(0)
	vi_ptr_buttons  = u32(0)
	// Edges latched between two reads, so a click shorter than the reader's
	// frame interval is still seen.
	vi_ptr_pressed  = u32(0)
	vi_ptr_released = u32(0)
	vi_ptr_scroll   = int(0)
	vi_ptr_callback = voidptr(0)
)

// /dev/pointer owns readiness and registers this after publishing its resource.
// Keeping the callback here avoids a dependency cycle between the device node
// and the VirtIO state it snapshots.
pub fn set_pointer_event_callback(callback voidptr) {
	vi_ptr_callback = callback
}

fn notify_pointer_event() {
	if vi_ptr_callback != voidptr(0) {
		C.vinix_call_void_fn(vi_ptr_callback)
	}
}

fn vi_put(b u8) {
	if vi_outlen < 64 {
		vi_outbuf[vi_outlen] = b
		vi_outlen++
	}
}

// vi_puts writes a whole escape sequence, the way the console's own key
// handling states one.
fn vi_puts(s &char) {
	unsafe {
		for i := 0; s[i] != 0; i++ {
			vi_put(u8(s[i]))
		}
	}
}

fn vi_put_uint(value u32) {
	mut divisor := u32(1)
	for divisor <= value / 10 {
		divisor *= 10
	}
	for divisor > 0 {
		vi_put(u8(`0`) + u8((value / divisor) % 10))
		divisor /= 10
	}
}

// CSI-u preserves the Super modifier which a traditional terminal byte
// stream otherwise discards. The Vinix Aquamarine backend turns these chords
// back into ordinary key events for Hyprland.
fn vi_emit_csi_u(codepoint u32, modifiers u32) {
	vi_puts(c'\e[')
	vi_put_uint(codepoint)
	vi_put(u8(`;`))
	vi_put_uint(1 + modifiers)
	vi_put(u8(`u`))
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

fn clamp_axis(value int, max int) int {
	if value < 0 {
		return 0
	}
	if value > max {
		return max
	}
	return value
}

fn process_button(code u16, value u32) {
	bit := u32(1) << u32(code - btn_left)
	if value != 0 {
		vi_ptr_buttons |= bit
		vi_ptr_pressed |= bit
	} else {
		vi_ptr_buttons &= ~bit
		vi_ptr_released |= bit
	}
	notify_pointer_event()
}

fn process_abs(code u16, value u32) {
	match code {
		abs_x {
			vi_ptr_x = clamp_axis(int(value), vi_ptr_max_x)
			notify_pointer_event()
		}
		abs_y {
			vi_ptr_y = clamp_axis(int(value), vi_ptr_max_y)
			notify_pointer_event()
		}
		else {}
	}
}

fn process_rel(code u16, value u32) {
	// Relative axes arrive as a signed 32-bit delta.
	delta := int(i32(value))
	match code {
		rel_x {
			vi_ptr_x = clamp_axis(vi_ptr_x + delta, vi_ptr_max_x)
			notify_pointer_event()
		}
		rel_y {
			vi_ptr_y = clamp_axis(vi_ptr_y + delta, vi_ptr_max_y)
			notify_pointer_event()
		}
		rel_wheel {
			vi_ptr_scroll += delta
			notify_pointer_event()
		}
		else {}
	}
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
		key_leftmeta, key_rightmeta {
			held := vi_meta_active
			vi_meta_active = value != 0
			// Cmd let go. Nothing on a terminal has ever wanted to hear about
			// a modifier's release, so this only goes out when a chord was
			// sent while it was down and something is waiting for the end of
			// it. It is the left Super key in the CSI-u functional encoding,
			// with an event type of 3, "released".
			if held && !vi_meta_active && vi_meta_chorded {
				vi_meta_chorded = false
				vi_puts(c'\e[57444;1:3u')
			}
			return
		}
		else {}
	}

	// Only process on press (1) or repeat (2), not release (0)
	if value == 0 {
		return
	}

	// Preserve GUI chords in the terminal stream for graphical compositors.
	// Native vinix-desktop consumes Cmd-Tab and ignores the other sequences.
	if vi_meta_active && code == key_tab {
		vi_emit_csi_u(9, 8 | if vi_shift_active { u32(1) } else { u32(0) })
		vi_meta_chorded = true
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

	// Regular keys — use shared conversion tables. GUI chords are encoded
	// before Ctrl turns letters into control bytes.
	base := keyboard.translate(u8(code), vi_shift_active, vi_caps_active, false)
	if vi_meta_active && base != 0 {
		mut modifiers := u32(8)
		if vi_shift_active {
			modifiers |= 1
		}
		if vi_alt_active {
			modifiers |= 2
		}
		if vi_ctrl_active {
			modifiers |= 4
		}
		vi_emit_csi_u(u32(base), modifiers)
		vi_meta_chorded = true
		return
	}
	c := keyboard.translate(u8(code), vi_shift_active, vi_caps_active, vi_ctrl_active)
	if c == 0 {
		return
	}
	vi_put(c)
}

// config_size reports how many bytes the device has for a selection, which is
// also how a driver asks whether the device supports it at all.
fn config_size(base u64, sel u8, subsel u8) u8 {
	mmio_w8(base + cfg_select, sel)
	mmio_w8(base + cfg_subsel, subsel)
	return mmio_r8(base + cfg_size)
}

// abs_axis_max is the top of an absolute axis' range. The axis' `min` sits at
// the head of the union and `max` right after it.
fn abs_axis_max(base u64, axis u16) int {
	if config_size(base, cfg_abs_info, u8(axis)) < 8 {
		return 0
	}
	return int(mmio_r32(base + cfg_union + 4))
}

// classify_pointer records a device that reports pointer axes. An absolute
// device brings its own coordinate span; a relative one is integrated over a
// span this driver picks, and userland scales either to the screen.
fn classify_pointer(base u64) {
	if config_size(base, cfg_ev_bits, u8(ev_abs)) > 0 {
		max_x := abs_axis_max(base, abs_x)
		max_y := abs_axis_max(base, abs_y)
		if max_x > 0 && max_y > 0 {
			vi_ptr_present = true
			vi_ptr_absolute = true
			vi_ptr_max_x = max_x
			vi_ptr_max_y = max_y
			vi_ptr_x = max_x / 2
			vi_ptr_y = max_y / 2
			uart.puts(c'virtio-input: absolute pointer, range ')
			uart.put_dec(u64(max_x))
			uart.puts(c'x')
			uart.put_dec(u64(max_y))
			uart.puts(c'\n')
			return
		}
	}

	if config_size(base, cfg_ev_bits, u8(ev_rel)) > 0 && !vi_ptr_absolute {
		vi_ptr_present = true
		vi_ptr_max_x = 32767
		vi_ptr_max_y = 32767
		vi_ptr_x = vi_ptr_max_x / 2
		vi_ptr_y = vi_ptr_max_y / 2
		uart.puts(c'virtio-input: relative pointer\n')
	}
}

pub fn initialise(hhdm u64) {
	for i := u64(0); i < mmio_slot_count; i++ {
		if vi_dev_count == max_devices {
			break
		}

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

		idx := vi_dev_count
		vi_vq_avail_virt[idx] = page_virt + avail_off
		vi_vq_used_virt[idx] = page_virt + used_off
		vi_events_virt[idx] = page_virt + 0x300

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
			unsafe { *&u16(vi_vq_avail_virt[idx] + 4 + j * 2) = u16(j) }
		}
		cpu.dmb_ish()
		unsafe { *&u16(vi_vq_avail_virt[idx] + 2) = u16(qsz) } // avail.idx

		mmio_w32(base + reg_status, status_acknowledge | status_driver | status_driver_ok)
		mmio_w32(base + reg_queue_notify, 0) // Notify: buffers available

		vi_dev_base[idx] = base
		vi_dev_qsize[idx] = u16(qsz)
		vi_last_used_idx[idx] = 0
		vi_dev_count++

		classify_pointer(base)

		uart.puts(c'virtio-input: ready, queue=')
		uart.put_dec(qsz)
		uart.puts(c'\n')
	}

	if vi_dev_count == 0 {
		uart.puts(c'virtio-input: no device found\n')
	}
}

fn poll_device(idx int) {
	base := vi_dev_base[idx]
	qsize := u16(vi_dev_qsize[idx])
	avail_virt := vi_vq_avail_virt[idx]
	used_virt := vi_vq_used_virt[idx]

	cpu.dmb_ish()

	new_idx := unsafe { *&u16(used_virt + 2) }
	if vi_last_used_idx[idx] == new_idx {
		return
	}

	mut avail_idx := unsafe { *&u16(avail_virt + 2) }

	for vi_last_used_idx[idx] != new_idx {
		ring_idx := u64(vi_last_used_idx[idx] % qsize)
		used_entry := used_virt + 4 + ring_idx * 8
		desc_id := unsafe { *&u32(used_entry) }

		event_addr := vi_events_virt[idx] + u64(desc_id) * 8
		ev_type := unsafe { *&u16(event_addr) }
		ev_code := unsafe { *&u16(event_addr + 2) }
		ev_value := unsafe { *&u32(event_addr + 4) }

		match ev_type {
			ev_key {
				if ev_code >= btn_left && ev_code <= btn_last {
					process_button(ev_code, ev_value)
				} else {
					process_key(ev_code, ev_value)
				}
			}
			ev_abs {
				process_abs(ev_code, ev_value)
			}
			ev_rel {
				process_rel(ev_code, ev_value)
			}
			else {}
		}

		// Re-add descriptor to available ring
		avail_ring_pos := u64(avail_idx % qsize)
		unsafe { *&u16(avail_virt + 4 + avail_ring_pos * 2) = u16(desc_id) }
		avail_idx++

		vi_last_used_idx[idx]++
	}

	// Update avail index and notify device
	cpu.dmb_ish()
	unsafe { *&u16(avail_virt + 2) = avail_idx }
	mmio_w32(base + reg_queue_notify, 0)

	// Acknowledge any pending interrupts
	isr := mmio_r32(base + reg_interrupt_status)
	if isr != 0 {
		mmio_w32(base + reg_interrupt_ack, isr)
	}
}

pub fn poll() {
	vi_outlen = 0

	for i := 0; i < vi_dev_count; i++ {
		poll_device(i)
	}
}
