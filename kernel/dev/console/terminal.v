// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module console

// The console as a terminal, the same on both architectures: its line
// discipline, reads and writes, and the ioctls a shell runs job control with
// -- which session it controls, its foreground process group, its window size.
// Each arch feeds it keystrokes from its own keyboards, and supplies
// caps_lock_on() and mirror_to_serial().

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
import krandom

const console_buffer_size = 1024
const console_bigbuf_size = 4096

__global (
	console_res       = &Console(unsafe { nil })
	// The one interface box every open of the console is handed.
	console_box       = &resource.Resource(unsafe { nil })
	console_read_lock klock.Lock
	console_event     eventstruct.Event
	console_buffer    [console_buffer_size]u8
	console_buffer_i  = u64(0)
	console_bigbuf    [console_bigbuf_size]u8
	console_bigbuf_i  = u64(0)
	console_decckm    = false
)

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

// The console device, with the termios a terminal starts with, in /dev.
fn setup_console() {
	console_res = &Console{}
	console_box = &resource.Resource(unsafe { console_res })
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

	console_res.status |= file.pollout

	fs.devtmpfs_add_device(console_box, 'console')
}

fn is_printable(c u8) bool {
	return c >= 0x20 && c <= 0x7e
}

fn add_to_buf_char(_c u8, echo bool, settings termios.Termios) {
	mut c := _c

	if c == `\r` && settings.c_iflag & termios.igncr != 0 {
		return
	}

	if c == `\n` && settings.c_iflag & termios.icrnl == 0 {
		c = `\r`
	} else if c == `\r` && settings.c_iflag & termios.icrnl != 0 {
		c = `\n`
	} else if c == `\r` && settings.c_iflag & termios.inlcr == 0 {
		c = `\n`
	} else if c == `\n` && settings.c_iflag & termios.inlcr != 0 {
		c = `\r`
	}

	if settings.c_lflag & termios.icanon != 0 {
		match c {
			`\n` {
				if console_buffer_i == console_buffer_size {
					return
				}
				console_buffer[console_buffer_i] = c
				console_buffer_i++
				if echo && settings.c_lflag & termios.echo != 0 {
					C.kprintf(c'%c', i32(c))
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
				if echo && settings.c_lflag & termios.echo != 0 {
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

	if echo && settings.c_lflag & termios.echo != 0 {
		if is_printable(c) {
			C.kprintf(c'%c', i32(c))
		} else if c >= 0x01 && c <= 0x1f {
			C.kprintf(c'^%c', i32(c + 0x40))
		}
	}
}

fn add_to_buf(ptr &u8, count u64, echo bool) {
	if console_res == unsafe { nil } { return }
	console_res.l.acquire()
	settings := console_res.termios
	group := console_res.foreground_pgid
	session := console_res.session
	proc.retain_job_identity(group, session)
	console_res.l.release()
	mut signals := u64(0)
	console_read_lock.acquire()
	for i := u64(0); i < count; i++ {
		c := unsafe { ptr[i] }
		krandom.add_event(u64(c))
		mut signal := 0
		if settings.c_lflag & termios.isig != 0 {
			if c == settings.c_cc[termios.vintr] { signal = userland.sigint }
			else if c == settings.c_cc[termios.vquit] { signal = userland.sigquit }
			else if c == settings.c_cc[termios.vsusp] { signal = userland.sigtstp }
		}
		if signal != 0 {
			signals |= u64(1) << (signal - 1)
			if settings.c_lflag & termios.noflsh == 0 {
				console_bigbuf_i = 0
				console_buffer_i = 0
				console_res.status &= ~file.pollin
			}
			continue
		}
		add_to_buf_char(c, echo, settings)
	}
	console_read_lock.release()
	event.trigger(mut console_event, false)
	for signal := 1; signal <= 64; signal++ {
		if signals & (u64(1) << (signal - 1)) != 0 { userland.signal_group(group, session, signal) }
	}
	proc.release_job_identity(group, session)
}

fn dec_private(_esc_val_count u64, esc_values &u32, final u64) {
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

// Opening a terminal without O_NOCTTY lets an eligible session leader
// acquire it. Device state is held while the process identity is claimed.
fn (mut this Console) set_job_identity_locked(session int, group int) {
	proc.replace_job_identity(this.foreground_pgid, this.session, group, session)
	this.session = session
	this.foreground_pgid = group
}

pub fn session_exit(device u64, session int) {
	if console_res == unsafe { nil } { return }
	console_res.l.acquire()
	if console_res.stat.rdev != device || console_res.session != session {
		console_res.l.release()
		return
	}
	group := console_res.foreground_pgid
	proc.retain_job_identity(group, session)
	proc.detach_terminal_members(device, session)
	console_res.set_job_identity_locked(0, 0)
	console_res.l.release()
	userland.signal_orphaned_job_group(group, session)
	proc.release_job_identity(group, session)
}

fn (mut this Console) open(flags int) ?&resource.Resource {
	if flags & resource.o_noctty == 0 {
		this.l.acquire()
		process := proc.current_thread().process
		if this.session == 0 && proc.claim_controlling_terminal(this.stat.rdev) {
			this.set_job_identity_locked(process.sid, process.pgid)
		}
		this.l.release()
	}
	return console_box
}

// The console, if `session` controls it: what /dev/tty stands for there.
pub fn session_terminal(device u64, session int) ?&resource.Resource {
	if console_res == unsafe { nil } || session == 0 {
		errno.set(errno.enxio)
		return none
	}
	console_res.l.acquire()
	matched := console_res.stat.rdev == device && console_res.session == session
		&& proc.controls_terminal(device, session)
	if matched { katomic.inc(mut &console_res.refcount) }
	console_res.l.release()
	if !matched { errno.set(errno.enxio); return none }
	// A new box on every open of /dev/tty was never freed.
	return console_box
}

fn (mut this Console) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

fn (mut this Console) job_check(signal int, only_tostop bool) u64 {
	this.l.acquire()
	session := this.session
	foreground := this.foreground_pgid
	apply := !only_tostop || this.termios.c_lflag & termios.tostop != 0
	this.l.release()
	return if apply { userland.terminal_job_check(this.stat.rdev, session, foreground, signal) } else { 0 }
}

fn (mut this Console) read(_handle voidptr, void_buf voidptr, _loc u64, count u64) ?i64 {
	if count == 0 {
		return 0
	}
	permission := this.job_check(userland.sigttin, false)
	if permission != 0 { errno.set(permission); return none }
	handle := unsafe { &file.Handle(_handle) }
	nonblocking := handle != unsafe { nil } && handle.flags & resource.o_nonblock != 0

	mut buf := unsafe { &u8(void_buf) }

	for console_read_lock.test_and_acquire() == false {
		if nonblocking {
			errno.set(errno.ewouldblock)
			return none
		}
		event.await_one(mut console_event, true) or {
			errno.set(proc.interrupted_errno)
			return none
		}
		allowed := this.job_check(userland.sigttin, false)
		if allowed != 0 { errno.set(allowed); return none }
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
				// The desktop polls this descriptor each frame. Do not wait
				// for a keystroke when the caller requested O_NONBLOCK.
				if nonblocking {
					console_read_lock.release()
					errno.set(errno.ewouldblock)
					return none
				}
				console_read_lock.release()
				for {
					event.await_one(mut console_event, true) or {
						errno.set(proc.interrupted_errno)
						return none
					}
					allowed := this.job_check(userland.sigttin, false)
					if allowed != 0 { errno.set(allowed); return none }
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

fn (mut this Console) write(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count == 0 { return 0 }
	permission := this.job_check(userland.sigttou, true)
	if permission != 0 { errno.set(permission); return none }

	copy := unsafe { malloc(count) }
	defer {
		unsafe { free(copy) }
	}
	unsafe { C.memcpy(copy, buf, count) }
	mirror_to_serial(copy, count)
	term.print(copy, count)
	return i64(count)
}

// How many bytes a reader could take right now.
fn (this &Console) input_pending() u64 {
	return console_bigbuf_i
}

fn (mut this Console) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	mut process := proc.current_thread().process
	if request == ioctl.tcsets || request == ioctl.tcsetsw || request == ioctl.tcsetsf
		|| request == ioctl.tcflsh || request == ioctl.tcsbrk || request == ioctl.tcxonc
		|| request == ioctl.tiocspgrp {
		permission := this.job_check(userland.sigttou, false)
		if permission != 0 { errno.set(permission); return none }
	}
	mut resize_group := 0
	mut resize_session := 0
	mut detach_group := 0
	mut detach_session := 0
	this.l.acquire()
	old_group := this.foreground_pgid
	old_session := this.session
	proc.retain_job_identity(old_group, old_session)
	defer {
		this.l.release()
		if resize_group != 0 { userland.signal_group(resize_group, resize_session, userland.sigwinch) }
		if detach_session != 0 {
			userland.signal_group(detach_group, detach_session, userland.sighup)
			userland.signal_group(detach_group, detach_session, userland.sigcont)
		}
		proc.release_job_identity(old_group, old_session)
	}

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
			mode := i32(if term.graphics_mode() { ioctl.kd_graphics } else { ioctl.kd_text })
			if !usercopy.copy_to_user(u64(argp), voidptr(&mode), sizeof(i32)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.kdgetled {
			leds := u8(if caps_lock_on() { ioctl.led_cap } else { 0 })
			if !usercopy.copy_to_user(u64(argp), voidptr(&leds), 1) {
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
				resize_group = this.foreground_pgid
				resize_session = this.session
			}
			return 0
		}
		ioctl.tcgets {
			settings := this.termios
			if !usercopy.copy_to_user(u64(argp), voidptr(&settings), termios.user_size()) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		// The three differ only in when they take effect. Nothing here buffers
		// output, so there is nothing to drain and they are the same.
		ioctl.tcsets, ioctl.tcsetsw, ioctl.tcsetsf {
			mut settings := this.termios
			if !usercopy.copy_from_user(voidptr(&settings), u64(argp), termios.user_size()) {
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
			if (this.session != 0 && this.session != process.sid)
				|| !proc.claim_controlling_terminal(this.stat.rdev) {
				errno.set(errno.eperm)
				return none
			}
			this.set_job_identity_locked(process.sid, process.pgid)
			return 0
		}
		ioctl.tiocnotty {
			if !userland.terminal_is_controlling(this.stat.rdev, this.session)
				|| !proc.release_controlling_terminal(this.stat.rdev) { errno.set(errno.enotty); return none }
			if this.session == process.pid {
				detach_group = this.foreground_pgid
				detach_session = this.session
				this.set_job_identity_locked(0, 0)
			}
			return 0
		}
		ioctl.tiocgsid {
			if !userland.terminal_is_controlling(this.stat.rdev, this.session) {
				errno.set(errno.enotty)
				return none
			}
			value := i32(proc.group_in(process.numbered_in, this.session))
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(i32)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocgpgrp {
			if !userland.terminal_is_controlling(this.stat.rdev, this.session) { errno.set(errno.enotty); return none }
			// Reporting no foreground group is what made every shell give up on
			// job control at startup.
			group := this.foreground_pgid
			// As the caller's pid namespace numbers the group.
			value := i32(proc.group_in(process.numbered_in, group))
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(i32)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocspgrp {
			mut value := i32(0)
			if !usercopy.copy_from_user(voidptr(&value), u64(argp), sizeof(i32)) {
				errno.set(errno.efault)
				return none
			}
			session := this.session
			this.l.release()
			group := userland.terminal_foreground_group(this.stat.rdev, session, int(value)) or { this.l.acquire(); return none }
			defer { proc.release_job_identity(group, session) }
			this.l.acquire()
			if this.session != session || !userland.terminal_is_controlling(this.stat.rdev, session) { errno.set(errno.enotty); return none }
			this.set_job_identity_locked(session, group)
			return 0
		}
		ioctl.fionread {
			value := i32(this.input_pending())
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(i32)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocoutq {
			// Writes go straight out, so nothing is ever queued.
			value := i32(0)
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(i32)) {
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

fn (mut this Console) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this Console) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Console) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Console) grow(_handle voidptr, _new_size u64) ? {
	return none
}
