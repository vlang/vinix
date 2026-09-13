// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module pty

import errno
import event
import event.eventstruct
import file
import fs
import ioctl
import katomic
import klock
import proc
import resource
import stat
import termios
import usercopy
import userland

// Unix98 pseudo terminals. /dev/ptmx is an open factory: each open creates a
// master resource and publishes its matching slave as /dev/pts/N.
const pty_buffer_size = u64(16 * 1024)
const pty_canonical_size = u64(4096)
const pty_max_pairs = 256

struct ByteQueue {
mut:
	data      &u8 = unsafe { nil }
	read_pos  u64
	write_pos u64
	used      u64
}

fn new_queue() ByteQueue {
	return ByteQueue{
		data: unsafe { malloc(pty_buffer_size) }
	}
}

fn (q &ByteQueue) room() u64 {
	return pty_buffer_size - q.used
}

fn (mut q ByteQueue) put(byte u8) bool {
	if q.used == pty_buffer_size {
		return false
	}
	unsafe { q.data[q.write_pos] = byte }
	q.write_pos++
	if q.write_pos == pty_buffer_size {
		q.write_pos = 0
	}
	q.used++
	return true
}

fn (mut q ByteQueue) read(buf voidptr, count u64) u64 {
	mut actual := count
	if actual > q.used {
		actual = q.used
	}
	if actual == 0 {
		return 0
	}

	before_wrap := if q.read_pos + actual > pty_buffer_size {
		pty_buffer_size - q.read_pos
	} else {
		actual
	}
	after_wrap := actual - before_wrap
	unsafe {
		C.memcpy(buf, voidptr(u64(q.data) + q.read_pos), before_wrap)
		if after_wrap != 0 {
			C.memcpy(voidptr(u64(buf) + before_wrap), q.data, after_wrap)
		}
	}
	q.read_pos = (q.read_pos + actual) % pty_buffer_size
	q.used -= actual
	return actual
}

fn (mut q ByteQueue) clear() {
	q.read_pos = 0
	q.write_pos = 0
	q.used = 0
}

struct PtyPair {
mut:
	l klock.Lock

	id   int
	path string

	master &PtyMaster = unsafe { nil }
	slave  &PtySlave = unsafe { nil }

	input  ByteQueue
	output ByteQueue

	// Bytes in a canonical line are not readable by the slave until a line
	// delimiter arrives. Keeping them outside input also makes POLLIN honest.
	canonical     [pty_canonical_size]u8
	canonical_len u64
	eof_pending   bool

	termios termios.Termios
	winsize ioctl.WinSize

	locked           bool = true
	master_open      bool = true
	closing_master   bool
	slave_open_count int
	slave_was_open   bool
	session          int
	foreground_pgid  int
}

struct Ptmx {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

struct PtyMaster {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	pair     &PtyPair = unsafe { nil }
}

struct PtySlave {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	pair     &PtyPair = unsafe { nil }
}

__global (
	ptmx_res    = &Ptmx(unsafe { nil })
	pty_id_lock klock.Lock
	pty_ids     [pty_max_pairs]bool
)

fn allocate_id() ?int {
	pty_id_lock.acquire()
	defer {
		pty_id_lock.release()
	}
	for i := 0; i < pty_max_pairs; i++ {
		if !pty_ids[i] {
			pty_ids[i] = true
			return i
		}
	}
	errno.set(errno.enospc)
	return none
}

fn release_id(id int) {
	if id < 0 || id >= pty_max_pairs {
		return
	}
	pty_id_lock.acquire()
	pty_ids[id] = false
	pty_id_lock.release()
}

fn initialise_termios(mut settings termios.Termios) {
	settings.c_iflag = termios.brkint | termios.icrnl | termios.ixon | termios.imaxbel
	settings.c_oflag = termios.opost | termios.onlcr
	settings.c_cflag = termios.cs8 | termios.cread | termios.b38400
	settings.c_lflag = termios.isig | termios.icanon | termios.iexten | termios.echo | termios.echoe | termios.echok | termios.echoctl | termios.echoke
	settings.c_cc[termios.vintr] = termios.ctrl(`C`)
	settings.c_cc[termios.vquit] = termios.ctrl(`\\`)
	settings.c_cc[termios.verase] = 0x7f
	settings.c_cc[termios.vkill] = termios.ctrl(`U`)
	settings.c_cc[termios.veof] = termios.ctrl(`D`)
	settings.c_cc[termios.vstart] = termios.ctrl(`Q`)
	settings.c_cc[termios.vstop] = termios.ctrl(`S`)
	settings.c_cc[termios.vsusp] = termios.ctrl(`Z`)
	settings.c_cc[termios.vreprint] = termios.ctrl(`R`)
	settings.c_cc[termios.vwerase] = termios.ctrl(`W`)
	settings.c_cc[termios.vlnext] = termios.ctrl(`V`)
	settings.c_cc[termios.vdiscard] = termios.ctrl(`O`)
	settings.c_cc[termios.vmin] = 1
}

fn initialise_stat(mut info stat.Stat, mode u32) {
	info.size = 0
	info.blocks = 0
	info.blksize = 512
	info.rdev = resource.create_dev_id()
	info.mode = mode | stat.ifchr
}

pub fn initialise() {
	ptmx_res = &Ptmx{}
	initialise_stat(mut ptmx_res.stat, 0o666)
	ptmx_res.status = file.pollout
	fs.devtmpfs_add_device(ptmx_res, 'ptmx')
}

// refresh_status_locked derives readiness from the two queues and endpoint
// lifetime. Callers hold pair.l and trigger the resource events afterwards.
fn (mut pair PtyPair) refresh_status_locked() {
	mut master_status := 0
	if pair.output.used != 0 {
		master_status |= file.pollin
	}
	if pair.master_open && pair.input.room() > pair.canonical_len {
		master_status |= file.pollout
	}
	if pair.slave_was_open && pair.slave_open_count == 0 {
		master_status |= file.pollhup
	}
	pair.master.status = master_status

	mut slave_status := 0
	if pair.input.used != 0 || pair.eof_pending {
		slave_status |= file.pollin
	}
	if pair.master_open && pair.output.room() != 0 {
		slave_status |= file.pollout
	}
	if !pair.master_open {
		slave_status |= file.pollhup
	}
	pair.slave.status = slave_status
}

fn wake_pair(mut pair PtyPair) {
	event.trigger(mut pair.master.event, false)
	event.trigger(mut pair.slave.event, false)
}

fn (mut this Ptmx) open(_flags int) ?&resource.Resource {
	id := allocate_id()?
	mut pair := &PtyPair{
		id: id
		path: 'pts/${id}'
		input: new_queue()
		output: new_queue()
	}
	initialise_termios(mut pair.termios)

	mut master := &PtyMaster{
		pair: pair
	}
	mut slave := &PtySlave{
		// The pathname owns this first reference. Opening the slave adds an
		// open-file-description reference through file.fd_create_from_resource.
		refcount: 1
		pair: pair
	}
	initialise_stat(mut master.stat, 0o666)
	initialise_stat(mut slave.stat, 0o620)
	pair.master = master
	pair.slave = slave
	pair.refresh_status_locked()

	fs.devtmpfs_add_device(slave, pair.path)
	return &resource.Resource(*master)
}

fn (mut this PtySlave) open(flags int) ?&resource.Resource {
	mut pair := this.pair
	pair.l.acquire()
	if pair.locked || !pair.master_open {
		pair.l.release()
		errno.set(errno.eio)
		return none
	}
	pair.slave_open_count++
	pair.slave_was_open = true

	// Opening a terminal without O_NOCTTY lets an eligible session leader
	// acquire it. openpty users pass O_NOCTTY and claim it explicitly later.
	mut process := proc.current_thread().process
	if flags & resource.o_noctty == 0 && process.sid == process.pid && process.tty_session == 0
		&& pair.session == 0 {
		pair.session = process.sid
		pair.foreground_pgid = process.pgid
		process.tty_session = process.sid
	}
	pair.refresh_status_locked()
	pair.l.release()
	wake_pair(mut pair)
	return &resource.Resource(*this)
}

fn (pair &PtyPair) input_room_locked() u64 {
	room := pair.input.room()
	return if room > pair.canonical_len { room - pair.canonical_len } else { 0 }
}

fn output_byte_locked(mut pair PtyPair, byte u8) bool {
	if pair.termios.c_oflag & termios.opost != 0 && byte == `\n`
		&& pair.termios.c_oflag & termios.onlcr != 0 {
		if pair.output.room() < 2 {
			return false
		}
		pair.output.put(`\r`)
		pair.output.put(`\n`)
		return true
	}
	return pair.output.put(byte)
}

fn echo_byte_locked(mut pair PtyPair, byte u8) {
	if pair.termios.c_lflag & termios.echo == 0 {
		return
	}
	if byte < 0x20 && byte != `\n` && byte != `\t`
		&& pair.termios.c_lflag & termios.echoctl != 0 {
		pair.output.put(`^`)
		pair.output.put(byte + 0x40)
		return
	}
	output_byte_locked(mut pair, byte)
}

fn erase_echo_locked(mut pair PtyPair, erased u8) {
	if pair.termios.c_lflag & termios.echo == 0 {
		return
	}
	if pair.termios.c_lflag & termios.echoe == 0 {
		echo_byte_locked(mut pair, pair.termios.c_cc[termios.verase])
		return
	}
	width := if erased < 0x20 && pair.termios.c_lflag & termios.echoctl != 0 { 2 } else { 1 }
	for _ in 0 .. width {
		pair.output.put(`\b`)
		pair.output.put(` `)
		pair.output.put(`\b`)
	}
}

fn flush_canonical_locked(mut pair PtyPair) {
	for i := u64(0); i < pair.canonical_len; i++ {
		pair.input.put(pair.canonical[i])
	}
	pair.canonical_len = 0
}

// Returns a signal number when an ISIG character was consumed.
fn input_byte_locked(mut pair PtyPair, incoming u8) u8 {
	mut byte := incoming
	if byte == `\r` {
		if pair.termios.c_iflag & termios.igncr != 0 {
			return 0
		}
		if pair.termios.c_iflag & termios.icrnl != 0 {
			byte = `\n`
		}
	} else if byte == `\n` && pair.termios.c_iflag & termios.inlcr != 0 {
		byte = `\r`
	}

	if pair.termios.c_lflag & termios.isig != 0 {
		mut signal := u8(0)
		if byte == pair.termios.c_cc[termios.vintr] {
			signal = u8(userland.sigint)
		} else if byte == pair.termios.c_cc[termios.vquit] {
			signal = u8(userland.sigquit)
		} else if byte == pair.termios.c_cc[termios.vsusp] {
			signal = u8(userland.sigtstp)
		}
		if signal != 0 {
			echo_byte_locked(mut pair, byte)
			output_byte_locked(mut pair, `\n`)
			if pair.termios.c_lflag & termios.noflsh == 0 {
				pair.input.clear()
				pair.canonical_len = 0
				pair.eof_pending = false
			}
			return signal
		}
	}

	if pair.termios.c_lflag & termios.icanon == 0 {
		if pair.input.put(byte) {
			echo_byte_locked(mut pair, byte)
		}
		return 0
	}

	if byte == pair.termios.c_cc[termios.verase] || byte == `\b` {
		if pair.canonical_len != 0 {
			erased := pair.canonical[pair.canonical_len - 1]
			pair.canonical_len--
			erase_echo_locked(mut pair, erased)
		}
		return 0
	}
	if byte == pair.termios.c_cc[termios.vkill] {
		for pair.canonical_len != 0 {
			erased := pair.canonical[pair.canonical_len - 1]
			pair.canonical_len--
			erase_echo_locked(mut pair, erased)
		}
		if pair.termios.c_lflag & termios.echok != 0 {
			output_byte_locked(mut pair, `\n`)
		}
		return 0
	}
	if byte == pair.termios.c_cc[termios.veof] {
		if pair.canonical_len == 0 {
			pair.eof_pending = true
		} else {
			flush_canonical_locked(mut pair)
		}
		return 0
	}

	delimiter := byte == `\n` || (pair.termios.c_cc[termios.veol] != 0
		&& byte == pair.termios.c_cc[termios.veol])
	// Reserve one byte for a canonical delimiter. Once a line reaches that
	// limit, additional text is discarded until newline instead of making the
	// PTY impossible to unblock with the very newline it is waiting for.
	limit := if delimiter { pty_canonical_size } else { pty_canonical_size - 1 }
	if pair.canonical_len < limit {
		pair.canonical[pair.canonical_len] = byte
		pair.canonical_len++
		echo_byte_locked(mut pair, byte)
	}
	if delimiter {
		flush_canonical_locked(mut pair)
	}
	return 0
}

fn signal_group(pgid int, signal u8) {
	if pgid <= 0 {
		return
	}
	proc.lock_table()
	defer {
		proc.unlock_table()
	}
	for pid := 1; pid < proc.max_pid; pid++ {
		mut target := proc.process_at(pid)
		if target == unsafe { nil } || target.pgid != pgid {
			continue
		}
		target.threads_lock.acquire()
		mut target_thread := &proc.Thread(unsafe { nil })
		if target.threads.len != 0 {
			target_thread = target.threads[0]
		}
		target.threads_lock.release()
		if target_thread != unsafe { nil } {
			userland.sendsig(target_thread, signal)
		}
	}
}

fn (mut this PtyMaster) read(handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count == 0 {
		return 0
	}
	open_handle := unsafe { &file.Handle(handle) }
	mut pair := this.pair
	pair.l.acquire()
	for pair.output.used == 0 {
		if pair.slave_was_open && pair.slave_open_count == 0 {
			pair.l.release()
			return 0
		}
		if open_handle.flags & resource.o_nonblock != 0 {
			pair.l.release()
			errno.set(errno.eagain)
			return none
		}
		pair.l.release()
		mut events := [&this.event]
		event.await(mut events, true) or {
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
		pair.l.acquire()
	}
	read := pair.output.read(buf, count)
	pair.refresh_status_locked()
	pair.l.release()
	wake_pair(mut pair)
	return i64(read)
}

fn (mut this PtyMaster) write(handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count == 0 {
		return 0
	}
	open_handle := unsafe { &file.Handle(handle) }
	bytes := unsafe { &u8(buf) }
	mut pair := this.pair
	mut written := u64(0)
	mut raised_signal := u8(0)
	pair.l.acquire()
	for written < count {
		for pair.input_room_locked() == 0 {
			if pair.slave_was_open && pair.slave_open_count == 0 {
				pair.l.release()
				if written != 0 {
					return i64(written)
				}
				errno.set(errno.eio)
				return none
			}
			if open_handle.flags & resource.o_nonblock != 0 {
				pair.l.release()
				if written != 0 {
					return i64(written)
				}
				errno.set(errno.eagain)
				return none
			}
			pair.l.release()
			mut events := [&this.event]
			event.await(mut events, true) or {
				unsafe { events.free() }
				errno.set(errno.eintr)
				return none
			}
			unsafe { events.free() }
			pair.l.acquire()
		}
		byte := unsafe { bytes[written] }
		signal := input_byte_locked(mut pair, byte)
		if signal != 0 {
			raised_signal = signal
		}
		written++
	}
	pgid := pair.foreground_pgid
	pair.refresh_status_locked()
	pair.l.release()
	wake_pair(mut pair)
	if raised_signal != 0 {
		signal_group(pgid, raised_signal)
	}
	return i64(written)
}

fn (mut this PtySlave) read(handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count == 0 {
		return 0
	}
	open_handle := unsafe { &file.Handle(handle) }
	mut pair := this.pair
	pair.l.acquire()
	mut minimum := u64(1)
	if pair.termios.c_lflag & termios.icanon == 0 {
		minimum = u64(pair.termios.c_cc[termios.vmin])
		if minimum > count {
			minimum = count
		}
		if minimum == 0 && pair.input.used == 0 {
			pair.l.release()
			return 0
		}
	}
	for pair.input.used < minimum {
		if pair.eof_pending {
			pair.eof_pending = false
			pair.refresh_status_locked()
			pair.l.release()
			wake_pair(mut pair)
			return 0
		}
		if !pair.master_open {
			pair.l.release()
			return 0
		}
		if open_handle.flags & resource.o_nonblock != 0 {
			pair.l.release()
			errno.set(errno.eagain)
			return none
		}
		pair.l.release()
		mut events := [&this.event]
		event.await(mut events, true) or {
			unsafe { events.free() }
			errno.set(errno.eintr)
			return none
		}
		unsafe { events.free() }
		pair.l.acquire()
	}
	read := pair.input.read(buf, count)
	pair.refresh_status_locked()
	pair.l.release()
	wake_pair(mut pair)
	return i64(read)
}

fn (mut this PtySlave) write(handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count == 0 {
		return 0
	}
	open_handle := unsafe { &file.Handle(handle) }
	bytes := unsafe { &u8(buf) }
	mut pair := this.pair
	mut written := u64(0)
	pair.l.acquire()
	for written < count {
		byte := unsafe { bytes[written] }
		needed := if pair.termios.c_oflag & termios.opost != 0 && byte == `\n`
			&& pair.termios.c_oflag & termios.onlcr != 0 {
			u64(2)
		} else {
			u64(1)
		}
		for pair.output.room() < needed {
			if !pair.master_open {
				pair.l.release()
				if written != 0 {
					return i64(written)
				}
				errno.set(errno.eio)
				return none
			}
			if open_handle.flags & resource.o_nonblock != 0 {
				pair.l.release()
				if written != 0 {
					return i64(written)
				}
				errno.set(errno.eagain)
				return none
			}
			pair.l.release()
			mut events := [&this.event]
			event.await(mut events, true) or {
				unsafe { events.free() }
				errno.set(errno.eintr)
				return none
			}
			unsafe { events.free() }
			pair.l.acquire()
		}
		output_byte_locked(mut pair, byte)
		written++
	}
	pair.refresh_status_locked()
	pair.l.release()
	wake_pair(mut pair)
	return i64(written)
}

fn copy_termios_to_user(pair &PtyPair, argp voidptr) bool {
	settings := pair.termios
	return usercopy.copy_to_user(u64(argp), voidptr(&settings), sizeof(termios.Termios))
}

fn set_termios_from_user(mut pair PtyPair, request u64, argp voidptr) bool {
	mut settings := termios.Termios{}
	if !usercopy.copy_from_user(voidptr(&settings), u64(argp), sizeof(termios.Termios)) {
		return false
	}
	was_canonical := pair.termios.c_lflag & termios.icanon != 0
	pair.termios = settings
	if was_canonical && settings.c_lflag & termios.icanon == 0 {
		flush_canonical_locked(mut pair)
	}
	if request == ioctl.tcsetsf {
		pair.input.clear()
		pair.canonical_len = 0
		pair.eof_pending = false
	}
	return true
}

fn terminal_ioctl(mut pair PtyPair, slave_side bool, request u64, argp voidptr) ?int {
	match request {
		ioctl.tcgets {
			if !copy_termios_to_user(pair, argp) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tcsets, ioctl.tcsetsw, ioctl.tcsetsf {
			if !set_termios_from_user(mut pair, request, argp) {
				errno.set(errno.efault)
				return none
			}
			pair.refresh_status_locked()
			return 0
		}
		ioctl.tiocgwinsz {
			winsize := pair.winsize
			if !usercopy.copy_to_user(u64(argp), voidptr(&winsize), sizeof(ioctl.WinSize)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocswinsz {
			mut winsize := ioctl.WinSize{}
			if !usercopy.copy_from_user(voidptr(&winsize), u64(argp), sizeof(ioctl.WinSize)) {
				errno.set(errno.efault)
				return none
			}
			changed := winsize.ws_row != pair.winsize.ws_row || winsize.ws_col != pair.winsize.ws_col
			pair.winsize = winsize
			if changed {
				signal_group(pair.foreground_pgid, u8(userland.sigwinch))
			}
			return 0
		}
		ioctl.tiocgpgrp {
			value := pair.foreground_pgid
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
			pair.foreground_pgid = value
			return 0
		}
		ioctl.tiocgsid {
			if pair.session == 0 {
				errno.set(errno.enotty)
				return none
			}
			value := pair.session
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocsctty {
			if !slave_side {
				errno.set(errno.enotty)
				return none
			}
			mut process := proc.current_thread().process
			if process.sid != process.pid || (pair.session != 0 && pair.session != process.sid) {
				errno.set(errno.eperm)
				return none
			}
			pair.session = process.sid
			pair.foreground_pgid = process.pgid
			process.tty_session = process.sid
			return 0
		}
		ioctl.tiocnotty {
			mut process := proc.current_thread().process
			if process.tty_session != pair.session || pair.session == 0 {
				errno.set(errno.enotty)
				return none
			}
			process.tty_session = 0
			if process.sid == pair.session {
				pair.session = 0
				pair.foreground_pgid = 0
			}
			return 0
		}
		ioctl.fionread {
			value := int(if slave_side { pair.input.used } else { pair.output.used })
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocoutq {
			value := int(if slave_side {
				pair.output.used
			} else {
				pair.input.used + pair.canonical_len
			})
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tcflsh {
			selector := int(u64(argp))
			if selector == ioctl.tciflush || selector == ioctl.tcioflush {
				pair.input.clear()
				pair.canonical_len = 0
				pair.eof_pending = false
			}
			if selector == ioctl.tcoflush || selector == ioctl.tcioflush {
				pair.output.clear()
			}
			pair.refresh_status_locked()
			return 0
		}
		ioctl.tcsbrk, ioctl.tcxonc, ioctl.tiocexcl, ioctl.tiocnxcl {
			return 0
		}
		else {
			errno.set(errno.enotty)
			return none
		}
	}
}

fn (mut this PtyMaster) ioctl(_handle voidptr, request u64, argp voidptr) ?int {
	mut pair := this.pair
	pair.l.acquire()
	defer {
		pair.l.release()
	}
	match request {
		ioctl.tiocgptn {
			value := u32(pair.id)
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(u32)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		ioctl.tiocsptlck {
			mut value := int(0)
			if !usercopy.copy_from_user(voidptr(&value), u64(argp), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			pair.locked = value != 0
			return 0
		}
		ioctl.tiocgptlck {
			value := if pair.locked { 1 } else { 0 }
			if !usercopy.copy_to_user(u64(argp), voidptr(&value), sizeof(int)) {
				errno.set(errno.efault)
				return none
			}
			return 0
		}
		else {
			return terminal_ioctl(mut pair, false, request, argp)
		}
	}
}

fn (mut this PtySlave) ioctl(_handle voidptr, request u64, argp voidptr) ?int {
	mut pair := this.pair
	pair.l.acquire()
	defer {
		pair.l.release()
	}
	return terminal_ioctl(mut pair, true, request, argp)
}

fn destroy_pair(pair &PtyPair) {
	release_id(pair.id)
	unsafe {
		pair.path.free()
		free(pair.input.data)
		free(pair.output.data)
		free(pair.master)
		free(pair.slave)
		free(pair)
	}
}

fn (mut this PtyMaster) unref(_handle voidptr) ? {
	mut pair := this.pair
	pair.l.acquire()
	katomic.dec(mut &this.refcount)
	closed := this.refcount == 0 && pair.master_open
	mut pgid := 0
	if closed {
		pair.master_open = false
		// Slave closes may race the hangup signals and pathname removal below.
		// Keep the pair alive until this unref has finished using it.
		pair.closing_master = true
		pgid = pair.foreground_pgid
		pair.refresh_status_locked()
	}
	pair.l.release()
	if !closed {
		return
	}
	wake_pair(mut pair)
	if pgid != 0 {
		signal_group(pgid, u8(userland.sighup))
		signal_group(pgid, u8(userland.sigcont))
	}
	// Keep the VFS node alive while a slave descriptor still points at it. If
	// only the node reference remains, remove it now. closing_master prevents
	// the recursive slave unref from freeing the pair beneath this function.
	pair.l.acquire()
	if pair.slave.refcount == 1 {
		pair.l.release()
		fs.devtmpfs_remove_device(pair.path)
		pair.l.acquire()
	}
	pair.closing_master = false
	destroy := pair.slave.refcount == 0
	pair.l.release()
	if destroy {
		destroy_pair(pair)
	}
}

fn (mut this PtySlave) unref(handle voidptr) ? {
	mut pair := this.pair
	pair.l.acquire()
	katomic.dec(mut &this.refcount)
	if handle != unsafe { nil } && pair.slave_open_count > 0 {
		pair.slave_open_count--
	}
	pair.refresh_status_locked()
	remove_path := handle != unsafe { nil } && !pair.master_open && !pair.closing_master
		&& this.refcount == 1
	destroy := !pair.master_open && !pair.closing_master && this.refcount == 0
	pair.l.release()
	if destroy {
		destroy_pair(pair)
	} else if remove_path {
		// devtmpfs_remove_device drops the node's last resource reference and
		// re-enters unref with a nil handle, which then destroys the pair.
		fs.devtmpfs_remove_device(pair.path)
	} else {
		wake_pair(mut pair)
	}
}

fn (mut this Ptmx) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.enxio)
	return none
}

fn (mut this Ptmx) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.enxio)
	return none
}

fn (mut this Ptmx) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Ptmx) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this PtyMaster) link(_handle voidptr) ? {}

fn (mut this PtySlave) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Ptmx) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this PtyMaster) unlink(_handle voidptr) ? {}

fn (mut this PtySlave) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Ptmx) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this PtyMaster) grow(_handle voidptr, _new_size u64) ? {}

fn (mut this PtySlave) grow(_handle voidptr, _new_size u64) ? {}

fn (mut this Ptmx) grow(_handle voidptr, _new_size u64) ? {}

fn (mut this PtyMaster) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

fn (mut this PtySlave) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

fn (mut this Ptmx) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}
