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
import memory

#include "apple_dcp_backlight.h"

fn C.vinix_dcp_bl_state_size() u64
fn C.vinix_dcp_bl_init(state voidptr, layout u32, maximum u32, scale u32, initial u32, known int) int
fn C.vinix_dcp_bl_set_online(state voidptr, online int) int
fn C.vinix_dcp_bl_write(state voidptr, text voidptr, length u64) int
fn C.vinix_dcp_bl_prepare(state voidptr, swap voidptr, length u64, token &u64) int
fn C.vinix_dcp_bl_complete(state voidptr, token u64, accepted int) int
fn C.vinix_dcp_bl_publish(state voidptr, raw_nits u32) int
fn C.vinix_dcp_bl_format(state voidptr, text voidptr, capacity u64) int

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
	state   voidptr
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
// resource's lock. context, the resource and its C storage have boot lifetime.
//
// Intentionally NOT called by the existing simplified dcp.initialise().
// Publishing a device there would advertise hardware support that is absent.
pub fn register_panel(layout Layout, maximum u32, scale u32, initial_raw u32,
	initial_known bool, context voidptr, notify fn (voidptr)) ?&Backlight {
	if panel_registered || notify == unsafe { nil } {
		errno.set(errno.ebusy)
		return none
	}
	storage := memory.malloc(C.vinix_dcp_bl_state_size())
	if storage == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	known := if initial_known { 1 } else { 0 }
	result := C.vinix_dcp_bl_init(storage, u32(layout), maximum, scale, initial_raw, known)
	if result != 0 {
		memory.free(storage)
		set_error(result)
		return none
	}
	result_online := C.vinix_dcp_bl_set_online(storage, 1)
	if result_online != 0 {
		memory.free(storage)
		set_error(result_online)
		return none
	}
	mut res := &Backlight{
		state: storage
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
	mut token := u64(0)
	this.l.acquire()
	result := C.vinix_dcp_bl_prepare(this.state, swap, length, &token)
	this.l.release()
	if result < 0 {
		set_error(result)
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
	result := C.vinix_dcp_bl_complete(this.state, token, if accepted { 1 } else { 0 })
	this.l.release()
	return result == 0
}

// Call from the real IOMFB property-15 callback, after decoding its payload.
pub fn (mut this Backlight) publish_nits(raw_nits u32) bool {
	this.l.acquire()
	result := C.vinix_dcp_bl_publish(this.state, raw_nits)
	this.l.release()
	return result == 0
}

// Call offline before suspend/reset/fault. On recovery, restore the transport
// first, then go online; a previous user request is retained for reapplication.
// Do not allocate a new state on resume: old transaction tokens must stay stale.
pub fn (mut this Backlight) set_online(online bool) {
	this.l.acquire()
	result := C.vinix_dcp_bl_set_online(this.state, if online { 1 } else { 0 })
	this.l.release()
	if result == 0 && online {
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
	this.l.acquire()
	length := C.vinix_dcp_bl_format(this.state, &text[0], u64(text.len))
	this.l.release()
	if length < 0 {
		set_error(length)
		return none
	}
	if loc >= u64(length) {
		return 0
	}
	remaining := u64(length) - loc
	n := if count < remaining { count } else { remaining }
	unsafe { C.memcpy(buf, &text[int(loc)], n) }
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
	unsafe { C.memcpy(&text[0], buf, count) }
	this.l.acquire()
	result := C.vinix_dcp_bl_write(this.state, &text[0], count)
	this.l.release()
	if result != 0 {
		set_error(result)
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
