@[has_globals]
module console

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
import usercopy
import katomic
import sched
import aarch64.uart
import aarch64.virtio_input
import apple.spi_keyboard
import flanterm as _

const console_buffer_size = 1024
const console_bigbuf_size = 4096

__global (
	console_res       = &Console(unsafe { nil })
	console_read_lock klock.Lock
	console_event     eventstruct.Event
	console_buffer    [console_buffer_size]u8
	console_buffer_i  = u64(0)
	console_bigbuf    [console_bigbuf_size]u8
	console_bigbuf_i  = u64(0)
	console_termios   = &termios.Termios(unsafe { nil })
	console_decckm    = false
	// XXX this is a massive hack to allow ctrl-c and friends without process
	// groups
	latest_thread     = &proc.Thread(unsafe { nil })
)

fn is_printable(c u8) bool {
	return c >= 0x20 && c <= 0x7e
}

fn add_to_buf_char(_c u8, echo bool) {
	mut c := _c

	if c == `\r` && console_termios.c_iflag & termios.igncr != 0 {
		return
	}

	if c == `\n` && console_termios.c_iflag & termios.icrnl == 0 {
		c = `\r`
	} else if c == `\r` && console_termios.c_iflag & termios.icrnl != 0 {
		c = `\n`
	} else if c == `\r` && console_termios.c_iflag & termios.inlcr == 0 {
		c = `\n`
	} else if c == `\n` && console_termios.c_iflag & termios.inlcr != 0 {
		c = `\r`
	}

	if console_termios.c_lflag & termios.icanon != 0 {
		match c {
			`\n` {
				if console_buffer_i == console_buffer_size {
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
				to_backspace := if console_buffer[console_buffer_i] >= 0x01
					&& console_buffer[console_buffer_i] <= 0x1f {
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

		if console_buffer_i == console_buffer_size {
			return
		}
		console_buffer[console_buffer_i] = c
		console_buffer_i++
	} else {
		if console_res.status & file.pollin == 0 {
			console_res.status |= file.pollin
			event.trigger(mut console_res.event, false)
		}
		if console_bigbuf_i == console_bigbuf_size {
			return
		}
		console_bigbuf[console_bigbuf_i] = c
		console_bigbuf_i++
	}

	if echo && console_termios.c_lflag & termios.echo != 0 {
		if is_printable(c) {
			print('${c:c}')
		} else if c >= 0x01 && c <= 0x1f {
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

// Poll UART, VirtIO and the built-in Apple SPI keyboard into the console.
// Called from the scheduler's await() loop to avoid needing a separate thread.
pub fn poll_uart_input() {
	c := uart.getc()
	if c >= 0 {
		mut byte_val := u8(c)
		if byte_val == 0x7f {
			byte_val = `\b`
		}
		add_to_buf(&byte_val, 1, true)
	}
	// Poll virtio keyboard
	virtio_input.poll()
	if vi_outlen > 0 {
		add_to_buf(&vi_outbuf[0], vi_outlen, true)
		vi_outlen = 0
	}

	// The driver releases its lock before entering the console/termios path.
	mut apple_input := [128]u8{}
	apple_count := spi_keyboard.poll(&apple_input[0], u64(apple_input.len), console_decckm)
	if apple_count > 0 {
		add_to_buf(&apple_input[0], u64(apple_count), true)
	}
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

pub fn flanterm_callback(p voidptr, t u64, a u64, b u64, c u64) {
	C.printf(c'Flanterm callback called\n')

	match t {
		10 {
			dec_private(a, unsafe { &u32(b) }, c)
		}
		else {}
	}
}

pub fn initialise() {
	C.flanterm_set_callback(flanterm_ctx, voidptr(flanterm_callback))

	console_res = &Console{}
	console_res.stat.size = 0
	console_res.stat.blocks = 0
	console_res.stat.blksize = 512
	console_res.stat.rdev = resource.create_dev_id()
	console_res.stat.mode = 0o644 | stat.ifchr

	// Initialise termios
	console_res.termios.c_iflag = termios.brkint | termios.icrnl | termios.ixon | termios.imaxbel
	console_res.termios.c_oflag = termios.opost | termios.onlcr
	console_res.termios.c_cflag = termios.cs8 | termios.cread | termios.b38400
	console_res.termios.c_lflag = termios.isig | termios.icanon | termios.iexten | termios.echo | termios.echoe | termios.echok | termios.echoctl | termios.echoke
	console_res.termios.c_cc[termios.vintr] = termios.ctrl(`C`)
	console_res.termios.c_cc[termios.vquit] = termios.ctrl(`\\`)
	console_res.termios.c_cc[termios.verase] = 0x7f // termios.ctrl(`?`)
	console_res.termios.c_cc[termios.vkill] = termios.ctrl(`U`)
	console_res.termios.c_cc[termios.veof] = termios.ctrl(`D`)
	console_res.termios.c_cc[termios.vstart] = termios.ctrl(`Q`)
	console_res.termios.c_cc[termios.vstop] = termios.ctrl(`S`)
	console_res.termios.c_cc[termios.vsusp] = termios.ctrl(`Z`)
	console_res.termios.c_cc[termios.vreprint] = termios.ctrl(`R`)
	console_res.termios.c_cc[termios.vwerase] = termios.ctrl(`W`)
	console_res.termios.c_cc[termios.vlnext] = termios.ctrl(`V`)
	console_res.termios.c_cc[termios.vdiscard] = termios.ctrl(`O`)
	console_res.termios.c_cc[termios.vmin] = 1

	console_termios = &console_res.termios

	console_res.status |= file.pollout

	fs.devtmpfs_add_device(console_res, 'console')

	// Initialize only after console/termios setup and before polling starts.
	spi_keyboard.initialise()

	// Register UART polling callback with the scheduler's await() loop.
	// Under HVF, IRQ injection is broken, so we can't use a separate
	// UART polling thread (it would starve all other threads).
	sched.set_uart_poll_callback(voidptr(poll_uart_input))
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

	// Controlling-terminal state. A shell needs all three to run job control:
	// which session owns the terminal, which process group is in the
	// foreground, and the window size to report.
	session          int
	foreground_pgid  int
	winsize_rows     u16
	winsize_cols     u16
	winsize_xpixel   u16
	winsize_ypixel   u16
	winsize_explicit bool
}

fn (mut this Console) mmap(_handle voidptr, page u64, flags int) voidptr {
	return 0
}

fn (mut this Console) read(_handle voidptr, void_buf voidptr, loc u64, count u64) ?i64 {
	latest_thread = proc.current_thread()

	handle := unsafe { &file.Handle(_handle) }
	nonblocking := handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0

	mut buf := &u8(void_buf)

	for console_read_lock.test_and_acquire() == false {
		mut events := [&console_event]
		event.await(mut events, true) or {
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
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
			if console_bigbuf_i == 0 && console_res.status & file.pollin != 0 {
				console_res.status &= ~file.pollin
				event.trigger(mut console_res.event, false)
			}
			wait = false
		} else {
			if wait == true {
				// A reader that asked not to block gets told there is nothing
				// rather than being parked here. A compositor polling the
				// keyboard once a frame depends on this: without it the whole
				// desktop stops until the next keystroke.
				if nonblocking {
					console_read_lock.release()
					errno.set(errno.ewouldblock)
					return none
				}
				console_read_lock.release()
				for {
					mut events := [&console_event]
					event.await(mut events, true) or {
						unsafe { events.free() }
						errno.set(errno.eintr)
						return none
					}
					unsafe { events.free() }
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

	copy := unsafe { malloc(count) }
	defer {
		unsafe { free(copy) }
	}
	unsafe { C.memcpy(copy, buf, count) }
	uart.write(charptr(copy), count)
	term.print(copy, count)
	return i64(count)
}

// How many bytes a reader could take right now.
fn (this &Console) input_pending() u64 {
	return console_bigbuf_i
}

fn (mut this Console) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	latest_thread = proc.current_thread()

	mut process := proc.current_thread().process

	match request {
		// KDSETMODE's argument is the mode itself, not a pointer to it.
		ioctl.kdsetmode {
			mode := int(u64(argp) & 0xff)
			if mode == ioctl.kd_graphics {
				term.enter_graphics_mode(process.pid)
			} else if mode == ioctl.kd_text {
				term.leave_graphics_mode()
			} else {
				errno.set(errno.einval)
				return none
			}
			return 0
		}
		ioctl.kdgetmode {
			mode := if term.graphics_mode() { ioctl.kd_graphics } else { ioctl.kd_text }
			if !usercopy.copy_to_user(u64(argp), voidptr(&mode), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocgwinsz {
			mut size := ioctl.WinSize{}
			if this.winsize_explicit {
				size.ws_row = this.winsize_rows
				size.ws_col = this.winsize_cols
				size.ws_xpixel = this.winsize_xpixel
				size.ws_ypixel = this.winsize_ypixel
			} else {
				size.ws_row = u16(terminal_rows)
				size.ws_col = u16(terminal_cols)
				size.ws_xpixel = u16(framebuffer_width)
				size.ws_ypixel = u16(framebuffer_height)
			}
			if !usercopy.copy_to_user(u64(argp), voidptr(&size), sizeof(ioctl.WinSize)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocswinsz {
			mut size := ioctl.WinSize{}
			if !usercopy.copy_from_user(voidptr(&size), u64(argp), sizeof(ioctl.WinSize)) {
				errno.set(errno.efault)
				return none
			}
			changed := size.ws_row != this.winsize_rows || size.ws_col != this.winsize_cols
			this.winsize_rows = size.ws_row
			this.winsize_cols = size.ws_col
			this.winsize_xpixel = size.ws_xpixel
			this.winsize_ypixel = size.ws_ypixel
			this.winsize_explicit = true
			// A terminal that changes shape tells the foreground group, which
			// is how an editor learns to redraw.
			if changed && this.foreground_pgid != 0 {
				signal_foreground(this.foreground_pgid, u8(userland.sigwinch))
			}
			return 0
		}
		ioctl.tcgets {
			settings := this.termios
			if !usercopy.copy_to_user(u64(argp), voidptr(&settings), sizeof(termios.Termios)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		// The three differ only in when they take effect. Nothing here buffers
		// output, so there is nothing to drain and they are the same.
		ioctl.tcsets, ioctl.tcsetsw, ioctl.tcsetsf {
			mut settings := termios.Termios{}
			if !usercopy.copy_from_user(voidptr(&settings), u64(argp), sizeof(termios.Termios)) {
				errno.set(errno.efault)
				return none
			}
			this.termios = settings
			if request == ioctl.tcsetsf {
				discard_console_input()
			}
			return 0
		}
		ioctl.tiocsctty {
			// Only a session leader may claim a terminal, and only one that is
			// free or already its own.
			if process.sid != process.pid {
				errno.set(errno.eperm)
				return none
			}
			if this.session != 0 && this.session != process.sid {
				errno.set(errno.eperm)
				return none
			}
			this.session = process.sid
			this.foreground_pgid = process.pgid
			process.tty_session = process.sid
			return 0
		}
		ioctl.tiocnotty {
			if this.session == process.sid {
				this.session = 0
				this.foreground_pgid = 0
			}
			process.tty_session = 0
			return 0
		}
		ioctl.tiocgsid {
			if this.session == 0 {
				errno.set(errno.enotty)
				return none
			}
			value := this.session
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocgpgrp {
			// Reporting no foreground group is what made every shell give up on
			// job control at startup.
			mut value := this.foreground_pgid
			if value == 0 {
				value = process.pgid
			}
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocspgrp {
			mut value := int(0)
			if !usercopy.copy_from_user(voidptr(&value), u64(argp), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			if value <= 0 {
				errno.set(errno.einval)
				return none
			}
			this.foreground_pgid = value
			return 0
		}
		ioctl.fionread {
			value := int(this.input_pending())
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocoutq {
			// Writes go straight out, so nothing is ever queued.
			value := int(0)
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tcflsh {
			// argp is the selector itself here, not a pointer to one.
			selector := int(u64(argp))
			if selector == ioctl.tciflush || selector == ioctl.tcioflush {
				discard_console_input()
			}
			return 0
		}
		// Draining output and flow control have nothing to act on, but a
		// terminal is expected to accept them.
		ioctl.tcsbrk, ioctl.tcxonc, ioctl.tiocexcl, ioctl.tiocnxcl {
			return 0
		}
		else {
			return resource.default_ioctl(handle, request, argp)
		}
	}
}

// Throw away anything typed but not yet read.
fn discard_console_input() {
	console_read_lock.acquire()
	console_bigbuf_i = 0
	console_buffer_i = 0
	console_res.status &= ~file.pollin
	console_read_lock.release()
}

// Raise a signal in every process of a process group.
fn signal_foreground(pgid int, signal u8) {
	for i := 1; i < proc.max_pid; i++ {
		mut target := processes[i]
		if target == unsafe { nil } || target.pgid != pgid {
			continue
		}
		target.threads_lock.acquire()
		mut main_thread := &proc.Thread(unsafe { nil })
		if target.threads.len > 0 {
			main_thread = target.threads[0]
		}
		target.threads_lock.release()
		if main_thread != unsafe { nil } {
			userland.sendsig(main_thread, signal)
		}
	}
}

fn (mut this Console) unref(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this Console) link(handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Console) unlink(handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Console) grow(handle voidptr, new_size u64) ? {
	return none
}
