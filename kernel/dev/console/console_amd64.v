@[has_globals]
module console

import x86.idt
import x86.apic
import x86.kio
import dev.keyboard
import event
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

fn keyboard_handler() {
	vect := idt.allocate_vector()

	C.kprintf(c'console: PS/2 keyboard vector is 0x%llx\n', u64(vect))

	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, vect, 1, true)

	// Disable primary and secondary PS/2 ports
	write_ps2(0x64, 0xad)
	write_ps2(0x64, 0xa7)

	// Read from port 0x60 to flush the PS/2 controller buffer
	for kio.port_in[u8](0x64) & 1 != 0 {
		kio.port_in[u8](0x60)
	}

	mut ps2_config := read_ps2_config()

	// Enable keyboard interrupt and keyboard scancode translation
	ps2_config |= (1 << 0) | (1 << 6)

	// Enable mouse interrupt if any
	if ps2_config & (1 << 5) != 0 {
		ps2_config |= (1 << 1)
	}

	write_ps2_config(ps2_config)

	// Enable keyboard port
	write_ps2(0x64, 0xae)

	// Enable mouse port if any
	if ps2_config & (1 << 5) != 0 {
		write_ps2(0x64, 0xa8)
	}

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

	for {
		event.await_one(mut int_events[vect], true) or {}
		input_byte := read_ps2()

		if input_byte == 0xe0 {
			console_extra_scancodes = true
			continue
		}

		if console_extra_scancodes == true {
			console_extra_scancodes = false

			match input_byte {
				left_alt {
					console_update_alt(true, true)
					continue
				}
				left_alt_rel {
					console_update_alt(true, false)
					continue
				}
				ctrl {
					console_ctrl_active = true
					continue
				}
				ctrl_rel {
					console_ctrl_active = false
					continue
				}
				left_meta, right_meta {
					console_meta_active = true
					continue
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
					continue
				}
				0x1c {
					add_to_buf(c'\n', 1, true)
					continue
				}
				0x35 {
					add_to_buf(c'/', 1, true)
					continue
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
					continue
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
					continue
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
					continue
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
					continue
				}
				0x47 {
					// Home
					add_to_buf(c'\e[1~', 4, true)
					continue
				}
				0x4f {
					// End
					add_to_buf(c'\e[4~', 4, true)
					continue
				}
				0x49 {
					// PG UP
					add_to_buf(c'\e[5~', 4, true)
					continue
				}
				0x51 {
					// PG DOWN
					add_to_buf(c'\e[6~', 4, true)
					continue
				}
				0x53 {
					// Delete
					add_to_buf(c'\e[3~', 4, true)
					continue
				}
				else {}
			}
		}

		match input_byte {
			numlock {
				console_numlock_active = true
				continue
			}
			left_alt {
				console_update_alt(false, true)
				continue
			}
			left_alt_rel {
				console_update_alt(false, false)
				continue
			}
			left_shift, right_shift {
				console_shift_active = true
				continue
			}
			left_shift_rel, right_shift_rel {
				console_shift_active = false
				continue
			}
			ctrl {
				console_ctrl_active = true
				continue
			}
			ctrl_rel {
				console_ctrl_active = false
				continue
			}
			capslock {
				console_capslock_active = !console_capslock_active
				continue
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
			continue
		}
		if console_alt_active && !console_meta_active && !console_ctrl_active
			&& input_byte == tab {
			if console_shift_active {
				add_to_buf(c'\e[9;4u', 6, true)
			} else {
				add_to_buf(c'\e[9;3u', 6, true)
			}
			console_alt_tab_chorded = true
			continue
		}
		if console_alt_active && !console_meta_active && !console_ctrl_active
			&& !console_shift_active && input_byte == f4 {
			add_to_buf(c'\e[1;3S', 6, true)
			continue
		}

		// Quick Launch uses the same CSI-u convention as the other input
		// backends: Space is code point 32 and Super contributes modifier 8.
		// Keep modified variants as ordinary input; Spotlight is Cmd-Space.
		if console_meta_active && !console_shift_active && !console_ctrl_active
			&& !console_alt_active && input_byte == space {
			add_to_buf(c'\e[32;9u', 7, true)
			console_meta_chorded = true
			continue
		}

		// The ISO key has no US character; see keyboard.iso_key.
		if input_byte == keyboard.key_102nd {
			if !console_meta_active {
				if console_alt_active {
					add_to_buf(c'\e', 1, true)
				}
				add_to_buf(keyboard.iso_key(console_shift_active), 2, true)
			}
			continue
		}

		// Ctrl-Space is NUL, as on any terminal; the table cannot say it. The
		// desktop moves to the next keyboard layout on it.
		if console_ctrl_active && !console_meta_active && input_byte == space {
			nul := u8(0)
			if console_alt_active {
				add_to_buf(c'\e', 1, true)
			}
			add_to_buf(&nul, 1, true)
			continue
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
				continue
			}
		}

		if input_byte in console_convtab_numpad_numlock {
			c = console_convtab_numpad_numlock[input_byte]
		} else {
			c = keyboard.translate(input_byte, console_shift_active, console_capslock_active, console_ctrl_active)
			if c == 0 {
				continue
			}
		}

		// Option (Alt) goes in front as an escape, the way a terminal's Meta
		// key does. The desktop's keyboard layouts type AltGr characters from it.
		if console_alt_active {
			add_to_buf(c'\e', 1, true)
		}
		add_to_buf(&c, 1, true)
	}
}

fn read_ps2() u8 {
	for kio.port_in[u8](0x64) & 1 == 0 {
	}
	return kio.port_in[u8](0x60)
}

fn write_ps2(port u16, value u8) {
	for kio.port_in[u8](0x64) & 2 != 0 {
	}
	kio.port_out[u8](port, value)
}

fn read_ps2_config() u8 {
	write_ps2(0x64, 0x20)
	return read_ps2()
}

fn write_ps2_config(value u8) {
	write_ps2(0x64, 0x60)
	write_ps2(0x60, value)
}

pub fn initialise() {
	// A serial-only QEMU boot can legitimately have no Limine framebuffer.
	// The console device still provides stdin/stdout; only the terminal callback
	// depends on a live flanterm context.
	if flanterm_ctx != unsafe { nil } {
		C.flanterm_set_callback(flanterm_ctx, voidptr(flanterm_callback))
	}

	setup_console()

	spawn keyboard_handler()
}

fn caps_lock_on() bool {
	return console_capslock_active
}

// The framebuffer is the console here; the serial port is a device of its own.
fn mirror_to_serial(_ voidptr, _ u64) {}
