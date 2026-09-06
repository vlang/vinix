// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module backlight

import resource
import fs
import stat
import klock
import katomic
import errno
import file
import event.eventstruct
import gpu.dcp.backlight.core

// Wire-layout families. A DCP backend must select one from an explicitly
// supported firmware version, not from the model name or a >= comparison.
pub enum Layout {
	v12_3 = 1
	v13_3 = 2
}

pub struct Backlight {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
mut:
	state   core.State
	context voidptr
	notify  fn (voidptr) = unsafe { nil }
}

__global (
	panel_registered = false
)

fn set_error(code int) {
	match code {
		-1, -2 { errno.set(errno.einval) }
		-3 { errno.set(errno.enodev) }
		-4 { errno.set(errno.ebusy) }
		else { errno.set(errno.eio) }
	}
}

// All adapter entrypoints run in task context. An RTKit IRQ handler must
// enqueue work rather than call these methods while another task holds l.
//
// Boot-time registration only, after devtmpfs is mounted. The caller must
// already own a working DCP transport for the M1 Air's INTERNAL panel, have
// negotiated a supported firmware layout, matched the backlight service,
// and obtained the panel maximum and Brightness_Scale from firmware.
//
// notify must queue nonblocking work to submit a real brightness-only swap
// even when no compositor is drawing. It is always called WITHOUT this
// resource's lock. context, the resource and its V state have boot lifetime.
//
// Intentionally NOT called by the existing simplified dcp.initialise().
// Publishing a device there would advertise hardware support that is absent.
pub fn register_panel(layout Layout, maximum u32, scale u32, initial_raw u32,
	initial_known bool, context voidptr, notify fn (voidptr)) ?&Backlight {
	if panel_registered || notify == unsafe { nil } {
		errno.set(errno.ebusy)
		return none
	}
	mut state := core.State{}
	wire_layout := match layout {
		.v12_3 { core.Layout.v12_3 }
		.v13_3 { core.Layout.v13_3 }
	}
	result := state.initialise(wire_layout, maximum, scale, initial_raw, initial_known)
	if result != .ok {
		set_error(int(result))
		return none
	}
	if state.set_online(true) != .ok {
		errno.set(errno.eio)
		return none
	}
	mut res := &Backlight{
		state: state
		context: context
		notify: notify
	}
	res.stat.blksize = 192
	res.stat.rdev = resource.create_dev_id()
	res.stat.mode = 0o600 | stat.ifchr
	res.status = file.pollin | file.pollout
	panel_registered = true
	fs.devtmpfs_add_device(res, 'apple-panel-bl')
	return res
}

// Return 0 if there was no pending update, otherwise a nonzero completion
// token. The buffer MUST be the real versioned dcp_swap, not IomfbSwapDesc.
// The caller must make the modified bytes visible to DCP before sending RPC.
pub fn (mut this Backlight) prepare_swap(swap voidptr, length u64) ?u64 {
	if swap == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	// The codec only accesses the versioned swap, never following surfaces.
	n := if length > 0x468 { 0x468 } else { int(length) }
	mut bytes := unsafe { (&u8(swap)).vbytes(n) }
	this.l.acquire()
	result, token := this.state.prepare(mut bytes)
	this.l.release()
	if int(result) < 0 {
		set_error(int(result))
		return none
	}
	return token
}

// accepted means a matched SUCCESS response, not just a successful mailbox
// send. A timeout must first fault/quiesce the transport. After a failed
// transaction, pending state is retained; the transport decides when retry
// is safe. This function never retries or schedules work from IRQ context.
pub fn (mut this Backlight) complete_swap(token u64, accepted bool) bool {
	this.l.acquire()
	result := this.state.complete(token, accepted)
	this.l.release()
	return result == .ok
}

// Call from the real IOMFB property-15 callback, after decoding its payload.
pub fn (mut this Backlight) publish_nits(raw_nits u32) bool {
	this.l.acquire()
	result := this.state.publish(raw_nits)
	this.l.release()
	return result == .ok
}

// Call offline before suspend/reset/fault. On recovery, restore the transport
// first, then go online; a previous user request is retained for reapplication.
// Do not allocate a new state on resume: old transaction tokens must stay stale.
pub fn (mut this Backlight) set_online(online bool) {
	this.l.acquire()
	result := this.state.set_online(online)
	this.l.release()
	if result == .ok && online {
		this.notify(this.context)
	}
}

fn (mut this Backlight) mmap(handle voidptr, page u64, flags int) voidptr {
	return unsafe { nil }
}

fn (mut this Backlight) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count == 0 {
		return 0
	}
	mut text := [192]u8{}
	mut bytes := unsafe { (&text[0]).vbytes(text.len) }
	this.l.acquire()
	length := this.state.format(mut bytes) or {
		this.l.release()
		errno.set(errno.eio)
		return none
	}
	this.l.release()
	if loc >= u64(length) {
		return 0
	}
	remaining := u64(length) - loc
	n := if count < remaining { count } else { remaining }
	for i in 0 .. int(n) {
		unsafe { (&u8(buf))[i] = text[int(loc) + i] }
	}
	return i64(n)
}

// A successful write means the request was QUEUED, not measured/applied.
// Read actual_nits for the latest firmware report. Each write must contain
// one whole decimal value in nits, with at most one trailing newline.
fn (mut this Backlight) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count == 0 {
		return 0
	}
	if count > 16 {
		errno.set(errno.einval)
		return none
	}
	// Copy once so parsing does not re-read changing user memory while locked.
	mut text := [16]u8{}
	for i in 0 .. int(count) {
		text[i] = unsafe { (&u8(buf))[i] }
	}
	bytes := unsafe { (&text[0]).vbytes(int(count)) }
	this.l.acquire()
	result := this.state.write(bytes)
	this.l.release()
	if result != .ok {
		set_error(int(result))
		return none
	}
	this.notify(this.context)
	return i64(count)
}

fn (mut this Backlight) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Backlight) unref(handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this Backlight) link(handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Backlight) unlink(handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Backlight) grow(handle voidptr, new_size u64) ? {
	errno.set(errno.einval)
	return none
}
