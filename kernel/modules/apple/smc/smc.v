// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module smc

import aarch64.cpu
import apple.mailbox
import devicetree
import errno
import event
import event.eventstruct
import file
import fs
import katomic
import klock
import memory
import resource
import sched
import stat
import time
import usercopy

#include "apple_smc.h"

fn C.vinix_smc_state_size() u64
fn C.vinix_smc_boot(state voidptr, context voidptr,
	send fn (voidptr, u64, u8) int, recv fn (voidptr, &u64, &u8) int,
	clock fn (voidptr) u64, relax fn (voidptr),
	frequency u64, sram_base u64, sram_size u64) int
fn C.vinix_smc_poll(state voidptr, budget u32) int
fn C.vinix_smc_refresh(state voidptr) int
fn C.vinix_smc_sample_time(state voidptr) u64
fn C.vinix_smc_format_capacity(percent int, output &u8) int
fn C.vinix_smc_error(result int) &char
fn C.vinix_smc_counter() u64

struct Snapshot {
mut:
	bytes  [4]u8
	length int
}

// One Resource is shared by all opens. Each Handle gets its own small text
// snapshot, retained across short reads and freed on the last close (including
// dup/fork). A status bar should reopen the device for each new sample.
struct Battery {
mut:
	stat      stat.Stat
	refcount  int
	l         klock.Lock
	event     eventstruct.Event
	status    int
	can_mmap  bool
	mbox      mailbox.Mailbox
	state     voidptr // Protocol state: exclusively owned by service() after probe.
	sample    int = -7
	sampled_at u64
	frequency u64
	snapshots map[u64]Snapshot
}

__global (
	battery_device = &Battery(unsafe { nil })
)

fn send(context voidptr, word u64, endpoint u8) int {
	mut dev := unsafe { &Battery(context) }
	if dev.mbox.send(mailbox.MboxMsg{data0: word, data1: u64(endpoint)}) {
		return 1
	}
	return 0
}

fn recv(context voidptr, word &u64, endpoint &u8) int {
	mut dev := unsafe { &Battery(context) }
	msg := dev.mbox.recv() or { return 0 }
	unsafe {
		*word = msg.data0
		*endpoint = mailbox.msg_endpoint(&msg)
	}
	return 1
}

fn clock(_ voidptr) u64 {
	return C.vinix_smc_counter()
}

fn relax(_ voidptr) {
	// WFE could sleep indefinitely: the ASC mailbox has no interrupt handler
	// installed here. The protocol core supplies real deadlines and loop caps.
	cpu.isb()
}

fn enabled(node &devicetree.DTNode) bool {
	devicetree.get_property(node, 'status') or { return true }
	values := devicetree.get_string_list(node, 'status') or { return false }
	return values.len == 1 && (values[0] == 'okay' || values[0] == 'ok')
}

// Called only after DT parsing, scheduler/timer initialization and /dev mount.
// Never guess register addresses on a missing or incompatible device tree.
// Every path out of here says why. A machine that reaches the desktop and
// shows `--%` has nothing else to go on: the battery is simply absent, and
// which of the eight steps below declined to register it is not otherwise
// recoverable without a serial port this machine does not have.
pub fn initialise() {
	if battery_device != unsafe { nil } {
		return
	}
	if !devicetree.is_available() {
		println('apple-smc: no device tree; battery not registered')
		return
	}
	node := devicetree.find_compatible('apple,t8103-smc') or {
		println('apple-smc: no compatible M1 SMC; battery not registered')
		return
	}
	if !enabled(node) {
		println('apple-smc: SMC node disabled in the device tree')
		return
	}
	sram := devicetree.get_named_reg(node, 'sram') or {
		println('apple-smc: missing translated SRAM resource')
		return
	}
	channels := devicetree.get_u32_array(node, 'mboxes') or {
		println('apple-smc: SMC node has no mboxes property')
		return
	}
	if channels.len != 1 {
		println('apple-smc: expected one zero-argument mailbox')
		return
	}
	provider := devicetree.find_phandle(channels[0]) or {
		println('apple-smc: mailbox phandle resolves to no node')
		return
	}
	if !enabled(provider) {
		println('apple-smc: mailbox provider disabled in the device tree')
		return
	}
	cells := devicetree.get_u32(provider, '#mbox-cells') or {
		println('apple-smc: mailbox provider has no #mbox-cells')
		return
	}
	compatible := devicetree.get_string_list(provider, 'compatible') or {
		println('apple-smc: mailbox provider has no compatible property')
		return
	}
	if cells != 0 || 'apple,asc-mailbox-v4' !in compatible {
		println('apple-smc: unsupported mailbox provider')
		return
	}
	regs := devicetree.get_translated_reg_ranges(provider) or {
		println('apple-smc: mailbox registers do not translate to an address')
		return
	}
	if regs.len != 1 || regs[0].base == 0 || regs[0].size < 0x1000
		|| regs[0].base > ~u64(0) - 0xfff {
		println('apple-smc: invalid mailbox register range')
		return
	}

	mut dev := &Battery{
		mbox: mailbox.new_mailbox(regs[0].base)
		state: memory.malloc(C.vinix_smc_state_size())
		snapshots: map[u64]Snapshot{}
	}
	result := C.vinix_smc_boot(dev.state, voidptr(dev), send, recv, clock, relax,
		cpu.read_cntfrq_el0(), sram.base, sram.size)
	if result < 0 {
		C.printf(c'apple-smc: probe failed: %s\n', C.vinix_smc_error(result))
		// No DMA allocations were made and no firmware buffer points at dev.
		unsafe {
			free(dev.state)
			free(dev)
		}
		return
	}

	initial := C.vinix_smc_refresh(dev.state)
	dev.sample = initial
	dev.sampled_at = C.vinix_smc_sample_time(dev.state)
	dev.frequency = cpu.read_cntfrq_el0()
	battery_device = dev
	if initial == -4 { // VINIX_SMC_NO_KEY: no supported battery on this machine.
		println('apple-smc: BRSC unavailable; battery not registered')
		spawn service()
		return
	}

	dev.stat.size = 0
	dev.stat.blksize = 4
	dev.stat.rdev = resource.create_dev_id()
	dev.stat.mode = 0o444 | stat.ifchr
	dev.status = file.pollin
	fs.devtmpfs_add_device(dev, 'battery')
	// Publish all Resource fields before starting the polling worker.
	// System endpoint traffic must be serviced even without userspace readers.
	spawn service()
	if initial >= 0 {
		C.printf(c'apple-smc: /dev/battery: %d%%\n', initial)
	} else {
		C.printf(c'apple-smc: /dev/battery: %s\n', C.vinix_smc_error(initial))
	}
}

fn service() {
	mut dev := battery_device
	// Reuse both the timer and its listener array rather than allocating ten
	// times per second. event.await consumes a pending timer event before sleep.
	mut timer := time.new_timer(time.TimeSpec{tv_nsec: 100_000_000})
	mut events := [&timer.event]
	for {
		event.await(mut events, true) or {}
		timer.disarm()
		// No Resource spinlock during firmware waits: Vinix spinlocks mask
		// interrupts. This worker alone owns the mutable protocol state.
		result := C.vinix_smc_poll(dev.state, 64)
		capacity := if result >= 0 { C.vinix_smc_refresh(dev.state) } else { result }
		sampled_at := C.vinix_smc_sample_time(dev.state)
		dev.l.acquire()
		dev.sample = capacity
		dev.sampled_at = sampled_at
		dev.l.release()
		if result < 0 {
			C.printf(c'apple-smc: battery service stopped: %s\n', C.vinix_smc_error(result))
			break
		}
		timer.when = time.TimeSpec{tv_nsec: 100_000_000}
		timer.arm()
	}
	unsafe {
		events.free()
		free(timer)
	}
	sched.dequeue_and_die()
}

fn (mut this Battery) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count == 0 || loc >= 4 {
		return 0
	}
	if handle == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	this.l.acquire()
	defer { this.l.release() }
	key := u64(handle)
	mut sample := this.snapshots[key] or {
		percent := this.sample
		if percent < 0 {
			errno.set(u64(if percent == -4 { errno.enodev } else { errno.eio }))
			return none
		}
		if C.vinix_smc_counter() - this.sampled_at >= 2 * this.frequency {
			errno.set(errno.eio)
			return none
		}
		mut value := Snapshot{}
		value.length = C.vinix_smc_format_capacity(percent, &value.bytes[0])
		if value.length < 0 {
			errno.set(errno.eio)
			return none
		}
		this.snapshots[key] = value
		value
	}
	if loc >= u64(sample.length) {
		return 0
	}
	remaining := u64(sample.length) - loc
	n := if count < remaining { count } else { remaining }
	if !usercopy.copy_to_user(u64(buf), voidptr(&sample.bytes[int(loc)]), n) {
		errno.set(errno.efault)
		return none
	}
	return i64(n)
}

fn (mut this Battery) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.eperm)
	return none
}

fn (mut this Battery) ioctl(_handle voidptr, _request u64, _argp voidptr) ?int {
	errno.set(errno.enotty)
	return none
}

fn (mut this Battery) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this Battery) grow(_handle voidptr, _size u64) ? {
	errno.set(errno.eperm)
	return none
}

fn (mut this Battery) unref(handle voidptr) ? {
	this.l.acquire()
	this.snapshots.delete(u64(handle))
	this.l.release()
	katomic.dec(mut &this.refcount)
}

fn (mut this Battery) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Battery) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}
