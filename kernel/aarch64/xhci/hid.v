// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// USB HID keyboards and pointers on top of the xHCI driver.
//
// A keyboard is switched to the boot protocol, whose 8-byte report is the same
// on every keyboard. A pointer keeps the report protocol, so a tablet can say
// where it is rather than how far it moved; its report descriptor is parsed
// for where the buttons, X, Y and the wheel sit. Both kinds come out as Linux
// input codes through virtio_input.
module xhci

import aarch64.timer
import aarch64.virtio_input

const kind_keyboard = 1
const kind_pointer = 2

// A field of a report: where it starts, how wide it is and what it spans.
struct Field {
mut:
	present  bool
	offset   u32
	size     u32
	min      i64
	max      i64
	relative bool
}

pub struct HidFunction {
mut:
	slot     u32
	dci      u32
	ring     Ring
	buf_phys u64
	buf_virt u64
	packet   u32
	kind     int
	// Pointer layout, from the report descriptor. With report IDs in use,
	// only reports carrying `report_id` describe the pointer.
	uses_ids       bool
	report_id      u8
	x              Field
	y              Field
	wheel          Field
	buttons_offset u32
	buttons_count  u32
	// The keys the last keyboard report held down, and its modifier byte.
	keys      [6]u8
	modifiers u8
}

__global (
	// Software key repeat: the boot protocol reports a held key once.
	xhci_repeat_code u16
	xhci_repeat_next u64
)

const repeat_delay_ns = u64(500000000)
const repeat_interval_ns = u64(33000000)

// Linux keycodes for the eight modifier bits of a boot report: left Ctrl,
// Shift, Alt, GUI, then the right-hand ones.
const modifier_codes = [u16(29), 42, 56, 125, 97, 54, 100, 126]!

// HID keyboard usages 0x00-0xe7 as Linux keycodes (drivers/hid/usbhid/usbkbd.c).
const hid_keycodes = [u8(0), 0, 0, 0, 30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24,
	25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 28, 1, 14, 15,
	57, 12, 13, 26, 27, 43, 43, 39, 40, 41, 51, 52, 53, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67,
	68, 87, 88, 99, 70, 119, 110, 102, 104, 111, 107, 109, 106, 105, 108, 103, 69, 98, 55, 74,
	78, 96, 79, 80, 81, 75, 76, 77, 71, 72, 73, 82, 83, 86, 127, 116, 117, 183, 184, 185, 186,
	187, 188, 189, 190, 191, 192, 193, 194, 134, 138, 130, 132, 128, 129, 131, 137, 133, 135,
	136, 113, 115, 114, 0, 0, 0, 121, 0, 89, 93, 124, 92, 94, 95, 0, 0, 0, 122, 123, 90, 91,
	85, 0, 0, 0, 0, 0, 0, 0, 111, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!

// An interface this driver wants, found in the configuration descriptor.
struct Candidate {
mut:
	iface      u8
	subclass   u8
	protocol   u8
	report_len u16
	endpoint   u8
	packet     u16
	interval   u8
}

// Walk the configuration descriptor in the device's buffer, set the
// configuration, and take every HID keyboard or pointer interface in it.
fn take_hid_functions(mut dev Device, total u64) {
	mut candidates := [4]Candidate{}
	mut count := 0
	mut current := -1
	config_value := buf_u8(&dev, 5)
	mut offset := u64(0)
	for offset + 2 <= total {
		length := u64(buf_u8(&dev, offset))
		kind := buf_u8(&dev, offset + 1)
		if length < 2 || offset + length > total {
			break
		}
		match kind {
			4 {
				// Interface: class 3 is HID.
				current = -1
				if buf_u8(&dev, offset + 5) == 3 && count < candidates.len {
					current = count
					candidates[count] = Candidate{
						iface:    buf_u8(&dev, offset + 2)
						subclass: buf_u8(&dev, offset + 6)
						protocol: buf_u8(&dev, offset + 7)
					}
					count++
				}
			}
			0x21 {
				// HID descriptor: the report descriptor's length.
				if current >= 0 && length >= 9 {
					candidates[current].report_len = buf_u16(&dev, offset + 7)
				}
			}
			5 {
				// Endpoint: the first interrupt IN one.
				address := buf_u8(&dev, offset + 2)
				if current >= 0 && candidates[current].endpoint == 0 && address & 0x80 != 0
					&& buf_u8(&dev, offset + 3) & 3 == 3 {
					candidates[current].endpoint = address & 0x0f
					candidates[current].packet = buf_u16(&dev, offset + 4) & 0x7ff
					candidates[current].interval = buf_u8(&dev, offset + 6)
				}
			}
			else {}
		}
		offset += length
	}

	if count == 0 {
		return
	}
	if !control(mut dev, 0x00, 9, u16(config_value), 0, 0) {
		println('xhci: slot ${dev.slot}: SET_CONFIGURATION failed')
		return
	}

	first := xhci_function_cnt
	for i := 0; i < count; i++ {
		c := candidates[i]
		if c.endpoint == 0 || xhci_function_cnt >= max_functions {
			continue
		}
		mut f := HidFunction{
			slot:   dev.slot
			dci:    u32(c.endpoint) * 2 + 1
			ring:   new_ring()
			packet: if c.packet > 0 && c.packet <= 64 { u32(c.packet) } else { u32(8) }
		}
		f.buf_phys, f.buf_virt = alloc_page()
		if c.subclass == 1 && c.protocol == 1 {
			// Boot keyboard: the fixed report, and reports only on change.
			f.kind = kind_keyboard
			control(mut dev, 0x21, 0x0b, 0, u16(c.iface), 0)
			control(mut dev, 0x21, 0x0a, 0, u16(c.iface), 0)
		} else {
			length := if c.report_len > 0 && c.report_len <= 1024 { c.report_len } else { u16(0) }
			if length == 0 || !control(mut dev, 0x81, 6, 0x2200, u16(c.iface), length) {
				continue
			}
			parse_report_descriptor(mut f, dev.buf_virt, u64(length))
			if !f.x.present || !f.y.present {
				continue
			}
			f.kind = kind_pointer
			absolute := !f.x.relative
			virtio_input.declare_pointer(absolute, int(f.x.max - f.x.min), int(f.y.max - f.y.min))
		}
		xhci_functions[xhci_function_cnt] = f
		xhci_function_cnt++
		println('xhci: slot ${dev.slot} interface ${c.iface}: ${if f.kind == kind_keyboard {
			'keyboard'
		} else if f.x.relative {
			'mouse'
		} else {
			'tablet'
		}}')
	}
	if xhci_function_cnt > first {
		configure_endpoints(mut dev, first, candidates, count)
	}
}

// The interval field for an interrupt endpoint: 2^n microframes. Full and low
// speed endpoints give bInterval in milliseconds, faster ones the exponent.
fn endpoint_interval(speed u32, interval u8) u32 {
	if speed >= 3 {
		if interval == 0 {
			return 0
		}
		return u32(interval) - 1
	}
	mut frames := u32(interval) * 8
	mut exponent := u32(0)
	for frames > 1 {
		frames >>= 1
		exponent++
	}
	if exponent < 3 {
		exponent = 3
	}
	if exponent > 10 {
		exponent = 10
	}
	return exponent
}

fn configure_endpoints(mut dev Device, first int, candidates [4]Candidate, count int) {
	clear_input(dev)
	mut add := u32(1)
	mut last_dci := u32(1)
	for i := first; i < xhci_function_cnt; i++ {
		f := xhci_functions[i]
		mut interval := u8(10)
		for j := 0; j < count; j++ {
			if u32(candidates[j].endpoint) * 2 + 1 == f.dci {
				interval = candidates[j].interval
			}
		}
		add |= u32(1) << f.dci
		if f.dci > last_dci {
			last_dci = f.dci
		}
		ep := ctx(dev.input_virt, u64(f.dci) + 1)
		mem_wr(ep, endpoint_interval(dev.speed, interval) << 16)
		// Error count 3, type 7 (interrupt IN), and the packet size.
		mem_wr(ep + 4, (3 << 1) | (7 << 3) | (f.packet << 16))
		mem_wr64(ep + 8, f.ring.phys | 1)
		mem_wr(ep + 16, f.packet | (f.packet << 16))
	}
	mem_wr(ctx(dev.input_virt, 0) + 4, add)
	write_slot(dev, last_dci)
	command(u32(dev.input_phys), u32(dev.input_phys >> 32), 0, (trb_configure_endpoint << 10) | (dev.slot << 24)) or {
		println('xhci: slot ${dev.slot}: endpoints not configured')
		// Keep nothing that would wait on an endpoint that does not exist.
		xhci_function_cnt = first
	}
}

fn queue_report(mut f HidFunction) {
	f.ring.push(u32(f.buf_phys), u32(f.buf_phys >> 32), f.packet, (trb_normal << 10) | trb_ioc | trb_isp)
	ring_doorbell(f.slot, f.dci)
}

// Parse the items of a HID report descriptor for the pointer fields.
fn parse_report_descriptor(mut f HidFunction, desc u64, length u64) {
	mut usage_page := u32(0)
	mut logical_min := i64(0)
	mut logical_max := i64(0)
	mut report_size := u32(0)
	mut report_count := u32(0)
	mut report_id := u8(0)
	mut usages := [16]u32{}
	mut usage_count := 0
	mut usage_min := u32(0)
	mut usage_max := u32(0)
	mut have_range := false
	// Bit offsets so far in each report ID's report.
	mut offsets := [256]u32{}
	mut pos := u64(0)
	for pos < length {
		prefix := unsafe { *&u8(desc + pos) }
		pos++
		if prefix == 0xfe {
			// A long item; nothing here needs one.
			if pos + 1 >= length {
				break
			}
			pos += 2 + u64(unsafe { *&u8(desc + pos) })
			continue
		}
		size := match prefix & 3 {
			3 { u64(4) }
			else { u64(prefix & 3) }
		}
		if pos + size > length {
			break
		}
		mut value := u32(0)
		for i := u64(0); i < size; i++ {
			value |= u32(unsafe { *&u8(desc + pos + i) }) << u32(i * 8)
		}
		// The same bits read as a signed number, for the logical extents.
		mut signed := i64(value)
		if size > 0 && size < 4 && value & (u32(1) << u32(size * 8 - 1)) != 0 {
			signed -= i64(1) << (size * 8)
		} else if size == 4 {
			signed = i64(i32(value))
		}
		pos += size
		item_type := (prefix >> 2) & 3
		tag := prefix >> 4
		match item_type {
			0 {
				// Main items.
				if tag == 8 {
					// Input.
					constant := value & 1 != 0
					variable := value & 2 != 0
					relative := value & 4 != 0
					base := offsets[report_id]
					if !constant && variable {
						for i := u32(0); i < report_count; i++ {
							mut usage := u32(0)
							if have_range {
								usage = usage_min + i
								if usage > usage_max {
									usage = usage_max
								}
							} else if usage_count > 0 {
								usage = usages[if int(i) < usage_count { int(i) } else { usage_count - 1 }]
							}
							mut page := usage_page
							if usage > 0xffff {
								page = usage >> 16
								usage &= 0xffff
							}
							field := Field{
								present:  true
								offset:   base + i * report_size
								size:     report_size
								min:      logical_min
								max:      logical_max
								relative: relative
							}
							if page == 1 && (usage == 0x30 || usage == 0x31 || usage == 0x38) {
								if report_id != 0 {
									if f.x.present && f.report_id != report_id {
										continue
									}
									f.uses_ids = true
									f.report_id = report_id
								}
								match usage {
									0x30 { f.x = field }
									0x31 { f.y = field }
									else { f.wheel = field }
								}
							} else if page == 9 && usage >= 1 && report_size == 1 {
								if f.buttons_count == 0 {
									f.buttons_offset = field.offset
								}
								if usage > f.buttons_count {
									f.buttons_count = usage
								}
							}
						}
					}
					offsets[report_id] = base + report_count * report_size
				}
				// Every main item clears the local state.
				usage_count = 0
				have_range = false
			}
			1 {
				// Global items.
				match tag {
					0 { usage_page = value }
					1 { logical_min = signed }
					2 { logical_max = signed }
					7 { report_size = value }
					8 { report_id = u8(value) }
					9 { report_count = value }
					else {}
				}
			}
			2 {
				// Local items.
				match tag {
					0 {
						if usage_count < usages.len {
							usages[usage_count] = value
							usage_count++
						}
					}
					1 {
						usage_min = value
						have_range = true
					}
					2 {
						usage_max = value
						have_range = true
					}
					else {}
				}
			}
			else {}
		}
	}
	if f.buttons_count > 8 {
		f.buttons_count = 8
	}
	// A logical maximum that did not fit its item came out negative; it was
	// unsigned all along.
	if f.x.max < f.x.min {
		f.x.max = (i64(1) << f.x.size) - 1
	}
	if f.y.max < f.y.min {
		f.y.max = (i64(1) << f.y.size) - 1
	}
}

// Bits [offset, offset+size) of the report, little-endian.
fn extract(data u64, length u32, offset u32, size u32) u64 {
	mut value := u64(0)
	for i := u32(0); i < size && i < 64; i++ {
		bit := offset + i
		if bit / 8 >= length {
			break
		}
		byte_value := unsafe { *&u8(data + u64(bit / 8)) }
		if byte_value & (u8(1) << (bit % 8)) != 0 {
			value |= u64(1) << i
		}
	}
	return value
}

fn field_value(field Field, data u64, length u32, base u32) i64 {
	raw := extract(data, length, base + field.offset, field.size)
	if field.min < 0 && field.size > 0 && field.size < 64 && raw & (u64(1) << (field.size - 1)) != 0 {
		return i64(raw) - (i64(1) << field.size)
	}
	return i64(raw)
}

fn (mut f HidFunction) report(length u32) {
	if f.kind == kind_keyboard {
		f.keyboard_report(length)
	} else {
		f.pointer_report(length)
	}
}

fn (mut f HidFunction) pointer_report(length u32) {
	mut base := u32(0)
	if f.uses_ids {
		if length == 0 || unsafe { *&u8(f.buf_virt) } != f.report_id {
			return
		}
		base = 8
	}
	x := field_value(f.x, f.buf_virt, length, base)
	y := field_value(f.y, f.buf_virt, length, base)
	if f.x.relative {
		virtio_input.report_relative(int(x), int(y))
	} else {
		virtio_input.report_absolute(int(x - f.x.min), int(y - f.y.min))
	}
	if f.wheel.present {
		virtio_input.report_scroll(int(field_value(f.wheel, f.buf_virt, length, base)))
	}
	mut buttons := u32(0)
	for i := u32(0); i < f.buttons_count; i++ {
		if extract(f.buf_virt, length, base + f.buttons_offset + i, 1) != 0 {
			buttons |= u32(1) << i
		}
	}
	virtio_input.report_buttons(buttons)
}

fn keycode(usage u8) u16 {
	if usage >= 0xe8 {
		return 0
	}
	return u16(hid_keycodes[usage])
}

fn (mut f HidFunction) keyboard_report(length u32) {
	if length < 3 {
		return
	}
	data := f.buf_virt
	modifiers := unsafe { *&u8(data) }
	mut keys := [6]u8{}
	for i := u32(0); i < 6 && i + 2 < length; i++ {
		keys[i] = unsafe { *&u8(data + u64(i + 2)) }
	}
	// Usage 1 in every slot is the keyboard saying it cannot tell (too many
	// keys down); the report says nothing about which keys changed.
	if keys[0] == 1 {
		return
	}

	for bit := 0; bit < 8; bit++ {
		mask := u8(1) << bit
		if (modifiers ^ f.modifiers) & mask != 0 {
			virtio_input.report_key(modifier_codes[bit], if modifiers & mask != 0 { u32(1) } else { u32(0) })
		}
	}
	for old in f.keys {
		if old <= 3 || contains_key(keys, old) {
			continue
		}
		code := keycode(old)
		if code != 0 {
			virtio_input.report_key(code, 0)
			if code == xhci_repeat_code {
				xhci_repeat_code = 0
			}
		}
	}
	for key in keys {
		if key <= 3 || contains_key(f.keys, key) {
			continue
		}
		code := keycode(key)
		if code != 0 {
			virtio_input.report_key(code, 1)
			xhci_repeat_code = code
			xhci_repeat_next = timer.get_ns() + repeat_delay_ns
		}
	}
	f.keys = keys
	f.modifiers = modifiers
}

fn contains_key(keys [6]u8, key u8) bool {
	for k in keys {
		if k == key {
			return true
		}
	}
	return false
}

fn repeat_keys() {
	if xhci_repeat_code == 0 {
		return
	}
	now := timer.get_ns()
	if now < xhci_repeat_next {
		return
	}
	virtio_input.report_key(xhci_repeat_code, 2)
	xhci_repeat_next = now + repeat_interval_ns
}
