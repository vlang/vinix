@[has_globals]
module console

import x86.idt
import x86.apic
import x86.kio
import dev.keyboard
import wakesrc
import event
import klock
import flanterm as _

const capslock = 0x3a
const numlock = 0x45
const left_alt = 0x38
const left_alt_rel = 0xb8
const right_shift = 0x36
const left_shift = 0x2a
const right_shift_rel = 0xb6
const left_shift_rel = 0xaa
const ctrl = 0x1d
const ctrl_rel = 0x9d
const tab = 0x0f
const f4 = 0x3e
const space = 0x39
// Cmd on a Mac keyboard, Super elsewhere. Both arrive behind the 0xe0 prefix.
const left_meta = 0x5b
const right_meta = 0x5c
const left_meta_rel = 0xdb
const right_meta_rel = 0xdc

__global (
	console_convtab_numpad_numlock map[u8]u8
	console_numlock_active         = bool(false)
	console_capslock_active        = bool(false)
	console_shift_active           = bool(false)
	console_ctrl_active            = bool(false)
	console_alt_active             = bool(false)
	console_alt_keys               = u8(0)
	console_alt_tab_chorded        = bool(false)
	// Cmd, and whether a chord was sent while it was down. The desktop's
	// global shortcuts need the release so a held key cannot repeat a chord
	// forever; Cmd-Tab and Cmd-Space both opt into that report.
	console_meta_active            = bool(false)
	console_meta_chorded           = bool(false)
	console_extra_scancodes        = bool(false)
	// Held around console_scancode(): the PS/2 keyboard and a USB one are
	// read by different threads and share the modifiers.
	console_key_lock klock.Lock
	console_event_held [256]bool
	console_pause_bytes int
)

fn console_update_alt(right bool, pressed bool) {
	mask := if right { u8(2) } else { u8(1) }
	if pressed {
		console_alt_keys |= mask
	} else {
		console_alt_keys &= ~mask
	}
	console_alt_active = console_alt_keys != 0
	if !console_alt_active && console_alt_tab_chorded {
		console_alt_tab_chorded = false
		add_to_buf(c'\e[57443;1:3u', 12, true)
	}
}

// Modified navigation keys use xterm's CSI 1;<modifier><final> encoding.
// Keeping Super in this stream lets the framebuffer desktop offer the same
// global tiling keys on PS/2 machines as it does on Apple and virtio keyboards.
fn console_add_modified_arrow(final u8) {
	modifier := 9 + if console_shift_active { 1 } else { 0 } +
		if console_alt_active { 2 } else { 0 } + if console_ctrl_active { 4 } else { 0 }
	mut sequence := [8]u8{}
	sequence[0] = 0x1b
	sequence[1] = `[`
	sequence[2] = `1`
	sequence[3] = `;`
	mut length := 0
	if modifier >= 10 {
		sequence[4] = u8(`0`) + u8(modifier / 10)
		sequence[5] = u8(`0`) + u8(modifier % 10)
		sequence[6] = final
		length = 7
	} else {
		sequence[4] = u8(`0`) + u8(modifier)
		sequence[5] = final
		length = 6
	}
	add_to_buf(&sequence[0], u64(length), true)
	console_meta_chorded = true
}

// Printable Super chords use CSI-u. Desktop workspaces use the number row and
// window actions use letters, so preserve the entire translated ASCII range.
fn console_add_csi_u(codepoint u8) {
	modifier := 9 + if console_shift_active { 1 } else { 0 } +
		if console_alt_active { 2 } else { 0 } + if console_ctrl_active { 4 } else { 0 }
	mut sequence := [16]u8{}
	sequence[0] = 0x1b
	sequence[1] = `[`
	mut length := 2
	if codepoint >= 100 {
		sequence[length] = u8(`0`) + codepoint / 100
		length++
	}
	if codepoint >= 10 {
		sequence[length] = u8(`0`) + (codepoint / 10) % 10
		length++
	}
	sequence[length] = u8(`0`) + codepoint % 10
	length++
	sequence[length] = `;`
	length++
	if modifier >= 10 {
		sequence[length] = u8(`0`) + u8(modifier / 10)
		length++
	}
	sequence[length] = u8(`0`) + u8(modifier % 10)
	length++
	sequence[length] = `u`
	length++
	add_to_buf(&sequence[0], u64(length), true)
	console_meta_chorded = true
}

// The 8042 is shared with the mouse. Finish its setup in initialise(), before
// dev.mouse negotiates its protocol, rather than racing it from a thread.
fn setup_keyboard() ?u8 {
	// First: a key of a USB keyboard is decoded with these too (usb_key()),
	// whether or not there is a PS/2 keyboard to read.
	console_convtab_numpad_numlock = {
		u8(0x37): u8(`*`)
		u8(0x4a): u8(`-`)
		u8(0x4e): u8(`+`)
		u8(0x47): u8(`7`)
		u8(0x48): u8(`8`)
		u8(0x49): u8(`9`)
		u8(0x4b): u8(`4`)
		u8(0x4c): u8(`5`)
		u8(0x4d): u8(`6`)
		u8(0x4f): u8(`1`)
		u8(0x50): u8(`2`)
		u8(0x51): u8(`3`)
		u8(0x52): u8(`0`)
		u8(0x53): u8(`.`)
	}

	// A machine with no keyboard controller reads all ones where its status
	// would be. There is nothing to set up and nothing to wait for; waiting
	// for its input buffer to empty, as the writes below do, would never end.
	if kio.port_in[u8](0x64) == 0xff {
		C.kprintf(c'console: no PS/2 keyboard controller\n')
		return none
	}

	vect := idt.allocate_vector()

	C.kprintf(c'console: PS/2 keyboard vector is 0x%llx\n', u64(vect))

	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, vect, 1, true)

	// Disable primary and secondary PS/2 ports
	if !ps2_command(0xad) || !ps2_command(0xa7) {
		return none
	}

	// Read from port 0x60 to flush the PS/2 controller buffer
	ps2_flush()

	if !ps2_command(0x20) {
		return none
	}
	mut ps2_config := read_ps2() or { return none }

	// Enable keyboard interrupt and keyboard scancode translation
	ps2_config |= (1 << 0) | (1 << 6)

	// The mouse enables its interrupt after reading its command replies.
	ps2_config &= ~ps2_pointer_interrupt

	if !ps2_set_config(ps2_config) {
		return none
	}

	// Enable keyboard port
	if !ps2_command(0xae) {
		return none
	}

	// Enable mouse port if any
	if ps2_config & (1 << 5) != 0 {
		if !ps2_command(0xa8) {
			return none
		}
	}
	// Kept for the day the controller has to be told again: resume_amd64.v.
	remember_ps2_config(ps2_config)
	return vect
}

fn keyboard_handler(vect u8) {
	for {
		event.await_one(mut int_events[vect], true) or {}
		// The byte the interrupt announced may be gone: whoever set the
		// controller up again after a sleep emptied its buffer. Waiting for
		// one that is not coming would hold this CPU until the next key.
		if kio.port_in[u8](0x64) & 1 == 0 {
			continue
		}
		input_byte := kio.port_in[u8](0x60)
		console_key_lock.acquire()
		console_scancode(input_byte)
		console_key_lock.release()
	}
}

// One byte of what a PS/2 keyboard sends, in the first scancode set: a key
// going down, the same with its top bit set for the key coming up, 0xe0 in
// front of either for the keys the first keyboards did not have. The byte
// is the controller's, or made for a key of a keyboard that speaks another
// language (usb_key() below). Call with console_key_lock held: the state of
// the modifiers is one state, whoever the key came from.
fn console_scancode(input_byte u8) {
	if console_key_events && (console_pause_bytes > 0 || input_byte == 0xe1) {
		if input_byte == 0xe1 && console_pause_bytes == 0 { console_pause_bytes = 5; return }
		console_pause_bytes--
		if console_pause_bytes == 0 {
			add_to_buf(c'\e[?119;1k\e[?119;0k', 18, false)
		}
		return
	}
	// A key going down ends a sleep, if keys are allowed to. Its release
	// does not: the release of the key that asked for the sleep arrives
	// just as the machine has gone down. Break codes have the top bit
	// set, as has the 0xe0 that prefixes an extended key.
	if input_byte < 0x80 {
		wakesrc.report(.keyboard)
	}

	if input_byte == 0xe0 {
		console_extra_scancodes = true
		return
	}
	if console_key_events {
		mut code := u16(input_byte & 0x7f)
		if console_extra_scancodes {
			console_extra_scancodes = false
			code = 0
			for pair in usb_extended_keys {
				if pair[1] == input_byte & 0x7f { code = u16(pair[0]); break }
			}
		}
		if code > 0 && code < 256 {
			value := if input_byte & 0x80 != 0 { u32(0) } else if console_event_held[code] { u32(2) } else { u32(1) }
			console_track_key_event(code, value)
			mut bytes := [16]u8{}
			n := keyboard.event_bytes(code, value, &bytes[0])
			add_to_buf(&bytes[0], n, false)
		}
		return
	}

	if console_extra_scancodes == true {
		console_extra_scancodes = false

		match input_byte {
			left_alt {
				console_update_alt(true, true)
				return
			}
			left_alt_rel {
				console_update_alt(true, false)
				return
			}
			ctrl {
				console_ctrl_active = true
				return
			}
			ctrl_rel {
				console_ctrl_active = false
				return
			}
			left_meta, right_meta {
				console_meta_active = true
				return
			}
			left_meta_rel, right_meta_rel {
				console_meta_active = false
				// Cmd let go. Nothing on a terminal has ever wanted to
				// hear about a modifier's release, so this only goes out
				// when a chord was sent while it was down and something is
				// waiting for the end of it. It is the left Super key in
				// the CSI-u functional encoding, with an event type of 3,
				// "released".
				if console_meta_chorded {
					console_meta_chorded = false
					add_to_buf(c'\e[57444;1:3u', 12, true)
				}
				return
			}
			0x1c {
				add_to_buf(c'\n', 1, true)
				return
			}
			0x35 {
				add_to_buf(c'/', 1, true)
				return
			}
			0x48 {
				// Up arrow
				if console_meta_active {
					console_add_modified_arrow(`A`)
				} else if console_decckm == false {
					add_to_buf(c'\e[A', 3, true)
				} else {
					add_to_buf(c'\eOA', 3, true)
				}
				return
			}
			0x4b {
				// Left arrow
				if console_meta_active {
					console_add_modified_arrow(`D`)
				} else if console_decckm == false {
					add_to_buf(c'\e[D', 3, true)
				} else {
					add_to_buf(c'\eOD', 3, true)
				}
				return
			}
			0x50 {
				// Down arrow
				if console_meta_active {
					console_add_modified_arrow(`B`)
				} else if console_decckm == false {
					add_to_buf(c'\e[B', 3, true)
				} else {
					add_to_buf(c'\eOB', 3, true)
				}
				return
			}
			0x4d {
				// Right arrow
				if console_meta_active {
					console_add_modified_arrow(`C`)
				} else if console_decckm == false {
					add_to_buf(c'\e[C', 3, true)
				} else {
					add_to_buf(c'\eOC', 3, true)
				}
				return
			}
			0x47 {
				// Home
				add_to_buf(c'\e[1~', 4, true)
				return
			}
			0x4f {
				// End
				add_to_buf(c'\e[4~', 4, true)
				return
			}
			0x49 {
				// PG UP
				add_to_buf(c'\e[5~', 4, true)
				return
			}
			0x51 {
				// PG DOWN
				add_to_buf(c'\e[6~', 4, true)
				return
			}
			0x53 {
				// Delete
				add_to_buf(c'\e[3~', 4, true)
				return
			}
			else {}
		}
	}

	match input_byte {
		numlock {
			console_numlock_active = true
			return
		}
		left_alt {
			console_update_alt(false, true)
			return
		}
		left_alt_rel {
			console_update_alt(false, false)
			return
		}
		left_shift, right_shift {
			console_shift_active = true
			return
		}
		left_shift_rel, right_shift_rel {
			console_shift_active = false
			return
		}
		ctrl {
			console_ctrl_active = true
			return
		}
		ctrl_rel {
			console_ctrl_active = false
			return
		}
		capslock {
			console_capslock_active = !console_capslock_active
			return
		}
		else {}
	}

	// Cmd-Tab is the window switcher's, not the terminal's, so it goes out
	// as the CSI-u encoding of Tab -- the key's own code point, then 1
	// plus a mask of the modifiers held with it, where super is 8 and
	// shift is 1 -- and the tab itself is not also sent.
	if console_meta_active && input_byte == tab {
		if console_shift_active {
			add_to_buf(c'\e[9;10u', 7, true)
		} else {
			add_to_buf(c'\e[9;9u', 6, true)
		}
		console_meta_chorded = true
		return
	}
	if console_alt_active && !console_meta_active && !console_ctrl_active
		&& input_byte == tab {
		if console_shift_active {
			add_to_buf(c'\e[9;4u', 6, true)
		} else {
			add_to_buf(c'\e[9;3u', 6, true)
		}
		console_alt_tab_chorded = true
		return
	}
	if console_alt_active && !console_meta_active && !console_ctrl_active
		&& !console_shift_active && input_byte == f4 {
		add_to_buf(c'\e[1;3S', 6, true)
		return
	}

	// Quick Launch uses the same CSI-u convention as the other input
	// backends: Space is code point 32 and Super contributes modifier 8.
	// Keep modified variants as ordinary input; Spotlight is Cmd-Space.
	if console_meta_active && !console_shift_active && !console_ctrl_active
		&& !console_alt_active && input_byte == space {
		add_to_buf(c'\e[32;9u', 7, true)
		console_meta_chorded = true
		return
	}

	// The ISO key has no US character; see keyboard.iso_key.
	if input_byte == keyboard.key_102nd {
		if !console_meta_active {
			if console_alt_active {
				add_to_buf(c'\e', 1, true)
			}
			add_to_buf(keyboard.iso_key(console_shift_active), 2, true)
		}
		return
	}

	// Ctrl-Space is NUL, as on any terminal; the table cannot say it. The
	// desktop moves to the next keyboard layout on it.
	if console_ctrl_active && !console_meta_active && input_byte == space {
		nul := u8(0)
		if console_alt_active {
			add_to_buf(c'\e', 1, true)
		}
		add_to_buf(&nul, 1, true)
		return
	}

	mut c := u8(0)

	if console_meta_active {
		base := if input_byte in console_convtab_numpad_numlock {
			console_convtab_numpad_numlock[input_byte]
		} else {
			keyboard.translate(input_byte, console_shift_active, console_capslock_active,
				false)
		}
		if base != 0 {
			console_add_csi_u(base)
			return
		}
	}

	if input_byte in console_convtab_numpad_numlock {
		c = console_convtab_numpad_numlock[input_byte]
	} else {
		c = keyboard.translate(input_byte, console_shift_active, console_capslock_active, console_ctrl_active)
		if c == 0 {
			return
		}
	}

	// Option (Alt) goes in front as an escape, the way a terminal's Meta
	// key does. The desktop's keyboard layouts type AltGr characters from it.
	if console_alt_active {
		add_to_buf(c'\e', 1, true)
	}
	add_to_buf(&c, 1, true)
}

fn read_ps2() ?u8 {
	for _ in 0 .. ps2_spins {
		if kio.port_in[u8](0x64) & 1 != 0 {
			return kio.port_in[u8](0x60)
		}
	}
	return none
}

pub fn initialise() {
	// A serial-only QEMU boot can legitimately have no Limine framebuffer.
	// The console device still provides stdin/stdout; only the terminal callback
	// depends on a live flanterm context.
	if flanterm_ctx != unsafe { nil } {
		C.flanterm_set_callback(flanterm_ctx, voidptr(flanterm_callback))
	}

	setup_console()

	register_keyboard_controller()
	if vect := setup_keyboard() {
		spawn keyboard_handler(vect)
	} else {
		C.kprintf(c'console: PS/2 setup unavailable; USB input remains enabled\n')
	}
}

fn caps_lock_on() bool {
	return console_capslock_active
}

fn num_lock_on() bool { return console_numlock_active }

// The framebuffer is the console here; the serial port is a device of its own.
fn mirror_to_serial(_ voidptr, _ u64) {}

// Linux's codes for the keys that a PS/2 keyboard sends behind 0xe0, and the
// byte that follows the prefix. The keys with codes below 89 need no table:
// Linux numbered them after the scancodes of this very set.
const usb_extended_keys = [
	[u8(96), 0x1c]!, // keypad Enter
	[u8(97), 0x1d]!, // right Ctrl
	[u8(98), 0x35]!, // keypad /
	[u8(99), 0x37]!, // Print Screen (ignore the preceding fake Shift)
	[u8(100), 0x38]!, // right Alt
	[u8(102), 0x47]!, // Home
	[u8(103), 0x48]!, // Up
	[u8(104), 0x49]!, // Page Up
	[u8(105), 0x4b]!, // Left
	[u8(106), 0x4d]!, // Right
	[u8(107), 0x4f]!, // End
	[u8(108), 0x50]!, // Down
	[u8(109), 0x51]!, // Page Down
	[u8(110), 0x52]!, // Insert
	[u8(111), 0x53]!, // Delete
	[u8(125), 0x5b]!, // left Super
	[u8(126), 0x5c]!, // right Super
]!

// A key of a keyboard that is not the PS/2 one -- a USB keyboard, through
// dev/xhci -- by its Linux key code: down (1), up (0) or held and repeating
// (2). It goes the way a PS/2 key goes, as the scancode the same key has
// there, so that every chord, layout and escape sequence is one piece of
// code. A key this console has no scancode for is dropped.
pub fn usb_key(code u16, value u32) {
	if console_key_events {
		if code == 0 || code > 255 || value > 2 { return }
		if value != 0 { wakesrc.report(.keyboard) }
		console_key_lock.acquire()
		console_track_key_event(code, value)
		mut bytes := [16]u8{}
		n := keyboard.event_bytes(code, value, &bytes[0])
		add_to_buf(&bytes[0], n, false)
		console_key_lock.release()
		return
	}
	// Input is decoded only after setup_keyboard() has made its tables.
	if console_convtab_numpad_numlock.len == 0 || code == 0 || code > 0xff {
		return
	}
	mut scancode := u8(0)
	mut extended := false
	if code < 89 {
		scancode = u8(code)
	} else {
		for pair in usb_extended_keys {
			if pair[0] == u8(code) {
				scancode = pair[1]
				extended = true
				break
			}
		}
	}
	if scancode == 0 {
		return
	}
	if value == 0 {
		scancode |= 0x80
	}
	console_key_lock.acquire()
	if extended {
		console_scancode(0xe0)
	}
	console_scancode(scancode)
	console_key_lock.release()
}

fn console_track_key_event(code u16, value u32) {
	console_event_held[code] = value != 0
	console_shift_active = console_event_held[42] || console_event_held[54]
	console_ctrl_active = console_event_held[29] || console_event_held[97]
	console_alt_active = console_event_held[56] || console_event_held[100]
	console_alt_keys = (if console_event_held[56] { u8(1) } else { u8(0) }) | (if console_event_held[100] { u8(2) } else { u8(0) })
	console_meta_active = console_event_held[125] || console_event_held[126]
	console_meta_chorded = false
	console_alt_tab_chorded = false
	if code == 58 && value == 1 { console_capslock_active = !console_capslock_active }
	if code == 69 && value == 1 { console_numlock_active = !console_numlock_active }
}
