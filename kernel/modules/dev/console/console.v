module console

import x86.idt
import x86.apic
import x86.kio
import event
import event.eventstruct
import klock
import stat
import stivale2
import fs
import ioctl
import resource
import errno
import termios

const max_scancode = 0x57
const capslock = 0x3a
const left_alt = 0x38
const left_alt_rel = 0xb8
const right_shift = 0x36
const left_shift = 0x2a
const right_shift_rel = 0xb6
const left_shift_rel = 0xaa
const ctrl = 0x1d
const ctrl_rel = 0x9d

const console_buffer_size = 1024
const console_bigbuf_size = 4096

__global (
	console_read_lock klock.Lock
	console_event eventstruct.Event
	console_capslock_active = bool(false)
	console_shift_active = bool(false)
	console_ctrl_active = bool(false)
	console_alt_active = bool(false)
	console_extra_scancodes = bool(false)
	console_buffer [console_buffer_size]byte
	console_buffer_i = u64(0)
	console_bigbuf [console_bigbuf_size]byte
	console_bigbuf_i = u64(0)
	console_termios = &termios.Termios(0)
)

const convtab_capslock = [
	`\0`, `\e`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `0`, `-`, `=`, `\b`, `\t`,
	`Q`, `W`, `E`, `R`, `T`, `Y`, `U`, `I`, `O`, `P`, `[`, `]`, `\n`, `\0`, `A`, `S`,
	`D`, `F`, `G`, `H`, `J`, `K`, `L`, `;`, `'`, `\``, `\0`, `\\`, `Z`, `X`, `C`, `V`,
	`B`, `N`, `M`, `,`, `.`, `/`, `\0`, `\0`, `\0`, ` `
]

const convtab_shift = [
	`\0`, `\e`, `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`, `(`, `)`, `_`, `+`, `\b`, `\t`,
	`Q`, `W`, `E`, `R`, `T`, `Y`, `U`, `I`, `O`, `P`, `{`, `}`, `\n`, `\0`, `A`, `S`,
	`D`, `F`, `G`, `H`, `J`, `K`, `L`, `:`, `"`, `~`, `\0`, `|`, `Z`, `X`, `C`, `V`,
	`B`, `N`, `M`, `<`, `>`, `?`, `\0`, `\0`, `\0`, ` `
]

const convtab_shift_capslock = [
	`\0`, `\e`, `!`, `@`, `#`, `$`, `%`, `^`, `&`, `*`, `(`, `)`, `_`, `+`, `\b`, `\t`,
	`q`, `w`, `e`, `r`, `t`, `y`, `u`, `i`, `o`, `p`, `{`, `}`, `\n`, `\0`, `a`, `s`,
	`d`, `f`, `g`, `h`, `j`, `k`, `l`, `:`, `"`, `~`, `\0`, `|`, `z`, `x`, `c`, `v`,
	`b`, `n`, `m`, `<`, `>`, `?`, `\0`, `\0`, `\0`, ` `
]

const convtab_nomod = [
	`\0`, `\e`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `0`, `-`, `=`, `\b`, `\t`,
	`q`, `w`, `e`, `r`, `t`, `y`, `u`, `i`, `o`, `p`, `[`, `]`, `\n`, `\0`, `a`, `s`,
	`d`, `f`, `g`, `h`, `j`, `k`, `l`, `;`, `'`, `\``, `\0`, `\\`, `z`, `x`, `c`, `v`,
	`b`, `n`, `m`, `,`, `.`, `/`, `\0`, `\0`, `\0`, ` `
]

fn is_printable(c byte) bool {
	return (c >= 0x20 && c <= 0x7e)
}

fn add_to_buf_char(c byte) {
	console_read_lock.acquire()
	defer {
		console_read_lock.release()
	}

	if console_termios.c_lflag & termios.icanon != 0 {
		match c {
			`\n` {
				if console_buffer_i == console_buffer_size {
					return
				}
				console_buffer[console_buffer_i] = c
				console_buffer_i++
				if console_termios.c_lflag & termios.echo != 0 {
					print('${c:c}')
				}
				for i := u64(0); i < console_buffer_i; i++ {
					if console_bigbuf_i == console_bigbuf_size {
						return
					}
					console_bigbuf[console_bigbuf_i] = console_buffer[i]
					console_bigbuf_i++
				}
				console_buffer_i = 0
				return
			}
			`\b` {
				if console_buffer_i == 0 {
					return
				}
				console_buffer_i--
				console_buffer[console_buffer_i] = 0
				if console_termios.c_lflag & termios.echo != 0 {
					print('\b \b')
				}
				return
			}
			else {}
		}

		if console_buffer_i == console_buffer_size {
			return
		}
		console_buffer[console_buffer_i] = c
		console_buffer_i++
	} else {
		if console_bigbuf_i == console_bigbuf_size {
			return
		}
		console_bigbuf[console_bigbuf_i] = c
		console_bigbuf_i++
	}

	if is_printable(c) && console_termios.c_lflag & termios.echo != 0 {
		print('${c:c}')
	}
}

fn add_to_buf(ptr &byte, count u64) {
	for i := u64(0); i < count; i++ {
		// TODO: Accept signal characters
		unsafe { add_to_buf_char(ptr[i]) }
	}
	event.trigger(console_event, true)
}

fn keyboard_handler() {
	vect := idt.allocate_vector()

	print('console: PS/2 keyboard vector is 0x${vect:x}\n')

	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, vect, 1, true)

	for {
		mut which := u64(0)
		event.await([&int_events[vect]], &which, true)
		input_byte := read_ps2()

		if input_byte == 0xe0 {
			console_extra_scancodes = true
			continue
		}

		if console_extra_scancodes == true {
			console_extra_scancodes = false

			match input_byte {
				ctrl {
					console_ctrl_active = true
					continue
				}
				ctrl_rel {
					console_ctrl_active = false
					continue
				}
				0x47 {
					// Home
					add_to_buf(c'\e[H', 3)
					continue
				}
				0x4f {
					// End
					add_to_buf(c'\e[F', 3)
					continue
				}
				0x48 {
					// Up arrow
					add_to_buf(c'\e[A', 3)
					continue
				}
				0x4b {
					// Left arrow
					add_to_buf(c'\e[D', 3)
					continue
				}
				0x50 {
					// Down arrow
					add_to_buf(c'\e[B', 3)
					continue
				}
				0x4d {
					// Right arrow
					add_to_buf(c'\e[C', 3)
					continue
				}
				0x49 {
					// PG UP
					add_to_buf(c'\e[5~', 4)
					continue
				}
				0x51 {
					// PG DOWN
					add_to_buf(c'\e[6~', 4)
					continue
				}
				0x53 {
					// Delete
					add_to_buf(c'\e[3~', 4)
					continue
				}
				else {}
			}
		}

		match input_byte {
			left_alt {
				console_alt_active = true
				continue
			}
			left_alt_rel {
				console_alt_active = false
				continue
			}
			left_shift,
			right_shift {
				console_shift_active = true
				continue
			}
			left_shift_rel,
			right_shift_rel {
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

		mut c := byte(0)
		if input_byte < max_scancode {
			if console_capslock_active == false && console_shift_active == false {
				c = convtab_nomod[input_byte]
			}
			if console_capslock_active == false && console_shift_active == true {
				c = convtab_shift[input_byte]
			}
			if console_capslock_active == true && console_shift_active == false {
				c = convtab_capslock[input_byte]
			}
			if console_capslock_active == true && console_shift_active == true {
				c = convtab_shift_capslock[input_byte]
			}
		} else {
			continue
		}

		add_to_buf(&c, 1)
	}
}

fn read_ps2() byte {
	for kio.port_in<byte>(0x64) & 1 == 0 {}
	return kio.port_in<byte>(0x60)
}

fn write_ps2(port u16, value byte) {
	for kio.port_in<byte>(0x64) & 2 != 0 {}
	kio.port_out<byte>(port, value)
}

fn read_ps2_config() byte {
	write_ps2(0x64, 0x20)
	return read_ps2()
}

fn write_ps2_config(value byte) {
	write_ps2(0x64, 0x60)
	write_ps2(0x60, value)
}

pub fn stivale2_term_callback(t u64, extra u64, esc_val_count u64, esc_values u64) {
	C.printf(c'stivale2 terminal callback called\n')
}

pub fn initialise() {
	mut console_res := &Console{}
	console_res.stat.size = 0
	console_res.stat.blocks = 0
	console_res.stat.blksize = 512
	console_res.stat.rdev = resource.create_dev_id()
	console_res.stat.mode = 0o644 | stat.ifchr

	// Initialise termios
	console_res.termios.c_lflag = termios.isig | termios.icanon | termios.echo
	console_res.termios.c_cc[termios.vintr] = 0x03

	console_termios = &console_res.termios

	fs.devtmpfs_add_device(console_res, 'console')

	// Disable primary and secondary PS/2 ports
	write_ps2(0x64, 0xad)
	write_ps2(0x64, 0xa7)

	// Read from port 0x60 to flush the PS/2 controller buffer
	for kio.port_in<byte>(0x64) & 1 != 0 {
		kio.port_in<byte>(0x60)
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

	go keyboard_handler()
}

struct Console {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock

	termios termios.Termios
}

fn (mut this Console) read(void_buf voidptr, loc u64, count u64) ?i64 {
	mut buf := &byte(void_buf)

	for console_read_lock.test_and_acquire() == false {
		mut which := u64(0)
		if event.await([&console_event], &which, true) == false {
			errno.set(errno.eintr)
			return none
		}
	}

	mut wait := true

	for i := u64(0); i < count; {
		if console_bigbuf_i != 0 {
			unsafe { buf[i] = console_bigbuf[0] }
			i++
			console_bigbuf_i--
			for j := u64(0); j < console_bigbuf_i; j++ {
				console_bigbuf[j] = console_bigbuf[j + 1]
			}
			wait = false
		} else {
			if wait == true {
				console_read_lock.release()
				for {
					mut which := u64(0)
					if event.await([&console_event], &which, true) == false {
						errno.set(errno.eintr)
						return none
					}
					if console_read_lock.test_and_acquire() == true {
						break
					}
				}
			} else {
				console_read_lock.release()
				return i64(i)
			}
		}
	}

	console_read_lock.release()
	return i64(count)
}

fn (mut this Console) write(buf voidptr, loc u64, count u64) ?i64 {
	copy := unsafe { C.malloc(count) }
	defer {
		unsafe { C.free(copy) }
	}
	unsafe { C.memcpy(copy, buf, count) }
	stivale2.terminal_print(copy, count)
	return i64(count)
}

fn (mut this Console) ioctl(request u64, argp voidptr) ?int {
	match request {
		ioctl.tiocgwinsz {
			mut w := &ioctl.WinSize(argp)
			w.ws_row = terminal_rows
			w.ws_col = terminal_cols
			w.ws_xpixel = framebuffer_width
			w.ws_ypixel = framebuffer_height
			return 0
		}
		ioctl.tcgets {
			mut t := &termios.Termios(argp)
			unsafe { t[0] = this.termios }
			return 0
		}
		// TODO: handle these differently
		ioctl.tcsets, ioctl.tcsetsw, ioctl.tcsetsf {
			mut t := &termios.Termios(argp)
			unsafe { this.termios = t[0] }
			return 0
		}
		else {
			return resource.default_ioctl(request, argp)
		}
	}
}
