// console.v: Console driver.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module console

import x86.idt
import x86.apic
import x86.kio
import event
import event.eventstruct
import klock
import stat
import term
import fs
import ioctl
import resource
import errno
import termios
import file
import userland
import proc
import katomic
import flanterm

const (
	max_scancode        = 0x57
	capslock            = 0x3a
	numlock             = 0x45
	left_alt            = 0x38
	left_alt_rel        = 0xb8
	right_shift         = 0x36
	left_shift          = 0x2a
	right_shift_rel     = 0xb6
	left_shift_rel      = 0xaa
	ctrl                = 0x1d
	ctrl_rel            = 0x9d
	console_buffer_size = 1024
	console_bigbuf_size = 4096
)

__global (
	console_convtab_numpad_numlock map[u8]u8
	console_res                    = &Console(unsafe { nil })
	console_read_lock              klock.Lock
	console_event                  eventstruct.Event
	console_numlock_active         = bool(false)
	console_capslock_active        = bool(false)
	console_shift_active           = bool(false)
	console_ctrl_active            = bool(false)
	console_alt_active             = bool(false)
	console_extra_scancodes        = bool(false)
	console_buffer                 [console_buffer_size]u8
	console_buffer_i               = u64(0)
	console_bigbuf                 [console_bigbuf_size]u8
	console_bigbuf_i               = u64(0)
	console_termios                = &termios.Termios(unsafe { nil })
	console_decckm                 = false
	// XXX this is a massive hack to allow ctrl-c and friends without process
	// groups
	latest_thread                  = &proc.Thread(unsafe { nil })
)

const convtab_capslock = [
	`\0`,
	`\e`,
	`1`,
	`2`,
	`3`,
	`4`,
	`5`,
	`6`,
	`7`,
	`8`,
	`9`,
	`0`,
	`-`,
	`=`,
	`\b`,
	`\t`,
	`Q`,
	`W`,
	`E`,
	`R`,
	`T`,
	`Y`,
	`U`,
	`I`,
	`O`,
	`P`,
	`[`,
	`]`,
	`\n`,
	`\0`,
	`A`,
	`S`,
	`D`,
	`F`,
	`G`,
	`H`,
	`J`,
	`K`,
	`L`,
	`;`,
	`'`,
	`\``,
	`\0`,
	`\\`,
	`Z`,
	`X`,
	`C`,
	`V`,
	`B`,
	`N`,
	`M`,
	`,`,
	`.`,
	`/`,
	`\0`,
	`\0`,
	`\0`,
	` `,
]

const convtab_shift = [
	`\0`,
	`\e`,
	`!`,
	`@`,
	`#`,
	`$`,
	`%`,
	`^`,
	`&`,
	`*`,
	`(`,
	`)`,
	`_`,
	`+`,
	`\b`,
	`\t`,
	`Q`,
	`W`,
	`E`,
	`R`,
	`T`,
	`Y`,
	`U`,
	`I`,
	`O`,
	`P`,
	`{`,
	`}`,
	`\n`,
	`\0`,
	`A`,
	`S`,
	`D`,
	`F`,
	`G`,
	`H`,
	`J`,
	`K`,
	`L`,
	`:`,
	`"`,
	`~`,
	`\0`,
	`|`,
	`Z`,
	`X`,
	`C`,
	`V`,
	`B`,
	`N`,
	`M`,
	`<`,
	`>`,
	`?`,
	`\0`,
	`\0`,
	`\0`,
	` `,
]

const convtab_shift_capslock = [
	`\0`,
	`\e`,
	`!`,
	`@`,
	`#`,
	`$`,
	`%`,
	`^`,
	`&`,
	`*`,
	`(`,
	`)`,
	`_`,
	`+`,
	`\b`,
	`\t`,
	`q`,
	`w`,
	`e`,
	`r`,
	`t`,
	`y`,
	`u`,
	`i`,
	`o`,
	`p`,
	`{`,
	`}`,
	`\n`,
	`\0`,
	`a`,
	`s`,
	`d`,
	`f`,
	`g`,
	`h`,
	`j`,
	`k`,
	`l`,
	`:`,
	`"`,
	`~`,
	`\0`,
	`|`,
	`z`,
	`x`,
	`c`,
	`v`,
	`b`,
	`n`,
	`m`,
	`<`,
	`>`,
	`?`,
	`\0`,
	`\0`,
	`\0`,
	` `,
]

const convtab_nomod = [
	`\0`,
	`\e`,
	`1`,
	`2`,
	`3`,
	`4`,
	`5`,
	`6`,
	`7`,
	`8`,
	`9`,
	`0`,
	`-`,
	`=`,
	`\b`,
	`\t`,
	`q`,
	`w`,
	`e`,
	`r`,
	`t`,
	`y`,
	`u`,
	`i`,
	`o`,
	`p`,
	`[`,
	`]`,
	`\n`,
	`\0`,
	`a`,
	`s`,
	`d`,
	`f`,
	`g`,
	`h`,
	`j`,
	`k`,
	`l`,
	`;`,
	`'`,
	`\``,
	`\0`,
	`\\`,
	`z`,
	`x`,
	`c`,
	`v`,
	`b`,
	`n`,
	`m`,
	`,`,
	`.`,
	`/`,
	`\0`,
	`\0`,
	`\0`,
	` `,
]

fn is_printable(c u8) bool {
	return c >= 0x20 && c <= 0x7e
}

fn add_to_buf_char(_c u8, echo bool) {
	mut c := _c

	if c == `\n` && console_termios.c_iflag & termios.icrnl == 0 {
		c = `\r`
	}

	if console_termios.c_lflag & termios.icanon != 0 {
		match c {
			`\n` {
				if console_buffer_i == console.console_buffer_size {
					return
				}
				console_buffer[console_buffer_i] = c
				console_buffer_i++
				if echo && console_termios.c_lflag & termios.echo != 0 {
					print('${c:c}')
				}
				for i := u64(0); i < console_buffer_i; i++ {
					if console_res.status & file.pollin == 0 {
						console_res.status |= file.pollin
						event.trigger(mut console_res.event, false)
					}
					if console_bigbuf_i == console.console_bigbuf_size {
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
				to_backspace := if console_buffer[console_buffer_i] >= 0x01
					&& console_buffer[console_buffer_i] <= 0x1a {
					2
				} else {
					1
				}
				console_buffer[console_buffer_i] = 0
				if echo && console_termios.c_lflag & termios.echo != 0 {
					for i := 0; i < to_backspace; i++ {
						print('\b \b')
					}
				}
				return
			}
			else {}
		}

		if console_buffer_i == console.console_buffer_size {
			return
		}
		console_buffer[console_buffer_i] = c
		console_buffer_i++
	} else {
		if console_res.status & file.pollin == 0 {
			console_res.status |= file.pollin
			event.trigger(mut console_res.event, false)
		}
		if console_bigbuf_i == console.console_bigbuf_size {
			return
		}
		console_bigbuf[console_bigbuf_i] = c
		console_bigbuf_i++
	}

	if echo && console_termios.c_lflag & termios.echo != 0 {
		if is_printable(c) {
			print('${c:c}')
		} else if c >= 0x01 && c <= 0x1a {
			print('^${c + 0x40:c}')
		}
	}
}

fn add_to_buf(ptr &u8, count u64, echo bool) {
	console_read_lock.acquire()
	defer {
		console_read_lock.release()
	}

	for i := u64(0); i < count; i++ {
		c := unsafe { ptr[i] }
		if console_termios.c_lflag & termios.isig != 0 {
			if c == console_termios.c_cc[termios.vintr] {
				userland.sendsig(latest_thread, userland.sigint)
			}
		}
		add_to_buf_char(c, echo)
	}

	event.trigger(mut console_event, false)
}

fn keyboard_handler() {
	vect := idt.allocate_vector()

	print('console: PS/2 keyboard vector is 0x${vect:x}\n')

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
		mut events := [&int_events[vect]]
		event.await(mut events, true) or {}
		input_byte := read_ps2()

		if input_byte == 0xe0 {
			console_extra_scancodes = true
			continue
		}

		if console_extra_scancodes == true {
			console_extra_scancodes = false

			match input_byte {
				console.ctrl {
					console_ctrl_active = true
					continue
				}
				console.ctrl_rel {
					console_ctrl_active = false
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
					if console_decckm == false {
						add_to_buf(c'\e[A', 3, true)
					} else {
						add_to_buf(c'\eOA', 3, true)
					}
					continue
				}
				0x4b {
					// Left arrow
					if console_decckm == false {
						add_to_buf(c'\e[D', 3, true)
					} else {
						add_to_buf(c'\eOD', 3, true)
					}
					continue
				}
				0x50 {
					// Down arrow
					if console_decckm == false {
						add_to_buf(c'\e[B', 3, true)
					} else {
						add_to_buf(c'\eOB', 3, true)
					}
					continue
				}
				0x4d {
					// Right arrow
					if console_decckm == false {
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
			console.numlock {
				console_numlock_active = true
				continue
			}
			console.left_alt {
				console_alt_active = true
				continue
			}
			console.left_alt_rel {
				console_alt_active = false
				continue
			}
			console.left_shift, console.right_shift {
				console_shift_active = true
				continue
			}
			console.left_shift_rel, console.right_shift_rel {
				console_shift_active = false
				continue
			}
			console.ctrl {
				console_ctrl_active = true
				continue
			}
			console.ctrl_rel {
				console_ctrl_active = false
				continue
			}
			console.capslock {
				console_capslock_active = !console_capslock_active
				continue
			}
			else {}
		}

		mut c := u8(0)

		if input_byte in console_convtab_numpad_numlock {
			c = console_convtab_numpad_numlock[input_byte]
		} else {
			if input_byte < console.max_scancode {
				if console_capslock_active == false && console_shift_active == false {
					c = console.convtab_nomod[input_byte]
				}
				if console_capslock_active == false && console_shift_active == true {
					c = console.convtab_shift[input_byte]
				}
				if console_capslock_active == true && console_shift_active == false {
					c = console.convtab_capslock[input_byte]
				}
				if console_capslock_active == true && console_shift_active == true {
					c = console.convtab_shift_capslock[input_byte]
				}
			} else {
				continue
			}
		}

		if console_ctrl_active {
			c = u8(C.toupper(c) - 0x40)
		}

		add_to_buf(&c, 1, true)
	}
}

fn read_ps2() u8 {
	for kio.port_in[u8](0x64) & 1 == 0 {}
	return kio.port_in[u8](0x60)
}

fn write_ps2(port u16, value u8) {
	for kio.port_in[u8](0x64) & 2 != 0 {}
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

fn dec_private(esc_val_count u64, esc_values &u32, final u64) {
	C.printf(c'dec private: ? %llu %c\n', unsafe { esc_values[0] }, final)
	match unsafe { esc_values[0] } {
		1 {
			match final {
				u64(`h`) {
					console_decckm = true
				}
				u64(`l`) {
					console_decckm = false
				}
				else {}
			}
		}
		else {}
	}
}

pub fn flanterm_callback(p &flanterm.Context, t u64, a u64, b u64, c u64) {
	C.printf(c'Flanterm callback called\n')

	match t {
		10 {
			dec_private(a, &u32(b), c)
		}
		else {}
	}
}

pub fn initialise() {
	C.flanterm_set_callback(mut flanterm_ctx, voidptr(flanterm_callback))

	console_res = &Console{}
	console_res.stat.size = 0
	console_res.stat.blocks = 0
	console_res.stat.blksize = 512
	console_res.stat.rdev = resource.create_dev_id()
	console_res.stat.mode = 0o644 | stat.ifchr

	// Initialise termios
	console_res.termios.c_lflag = termios.isig | termios.icanon | termios.echo
	console_res.termios.c_cc[termios.vintr] = 0x03
	console_res.termios.ibaud = 38400
	console_res.termios.obaud = 38400

	console_termios = &console_res.termios

	console_res.status |= file.pollout

	fs.devtmpfs_add_device(console_res, 'console')

	spawn keyboard_handler()
}

struct Console {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	termios termios.Termios
}

fn (mut this Console) mmap(page u64, flags int) voidptr {
	return 0
}

fn (mut this Console) read(handle voidptr, void_buf voidptr, loc u64, count u64) ?i64 {
	latest_thread = proc.current_thread()

	mut buf := &u8(void_buf)

	for console_read_lock.test_and_acquire() == false {
		mut events := [&console_event]
		event.await(mut events, true) or {
			errno.set(errno.eintr)
			return none
		}
	}

	mut wait := true

	for i := u64(0); i < count; {
		if console_bigbuf_i != 0 {
			unsafe {
				buf[i] = console_bigbuf[0]
			}
			i++
			console_bigbuf_i--
			for j := u64(0); j < console_bigbuf_i; j++ {
				console_bigbuf[j] = console_bigbuf[j + 1]
			}
			if console_bigbuf_i == 0 && (console_res.status & file.pollin != 0) {
				console_res.status &= ~file.pollin
				event.trigger(mut console_res.event, false)
			}
			wait = false
		} else {
			if wait == true {
				console_read_lock.release()
				for {
					mut events := [&console_event]
					event.await(mut events, true) or {
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

fn (mut this Console) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	latest_thread = proc.current_thread()

	copy := unsafe { C.malloc(count) }
	defer {
		unsafe { C.free(copy) }
	}
	unsafe { C.memcpy(copy, buf, count) }
	term.print(copy, count)
	return i64(count)
}

fn (mut this Console) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	latest_thread = proc.current_thread()

	match request {
		ioctl.tiocgwinsz {
			mut w := unsafe { &ioctl.WinSize(argp) }
			w.ws_row = u16(terminal_rows)
			w.ws_col = u16(terminal_cols)
			w.ws_xpixel = u16(framebuffer_width)
			w.ws_ypixel = u16(framebuffer_height)
			return 0
		}
		ioctl.tcgets {
			mut t := unsafe { &termios.Termios(argp) }
			unsafe {
				*t = this.termios
			}
			return 0
		}
		// TODO: handle these differently
		ioctl.tcsets, ioctl.tcsetsw, ioctl.tcsetsf {
			mut t := unsafe { &termios.Termios(argp) }
			unsafe {
				this.termios = *t
			}
			return 0
		}
		else {
			return resource.default_ioctl(handle, request, argp)
		}
	}
}

fn (mut this Console) unref(handle voidptr) ? {
	katomic.dec(this.refcount)
}

fn (mut this Console) link(handle voidptr) ? {
	katomic.inc(this.stat.nlink)
}

fn (mut this Console) unlink(handle voidptr) ? {
	katomic.dec(this.stat.nlink)
}

fn (mut this Console) grow(handle voidptr, new_size u64) ? {
	return none
}
