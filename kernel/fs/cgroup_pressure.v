// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module fs

import cgcontrol
import errno
import event
import event.eventstruct
import katomic
import klock
import proc
import resource
import stat
import time

const cgroup_subscriptions = 128

struct CGroupPressureFile {
mut:
	stat stat.Stat
	refcount int
	l klock.Lock
	event eventstruct.Event
	status int
	can_mmap bool
	group &CGroup = unsafe { nil }
	acknowledged u64
	slot int
	buffer [768]u8
	length int
}

__global (
	cgroup_subscriptions_lock klock.Lock
	cgroup_pressure_files [cgroup_subscriptions]CGroupPressureFile
	cgroup_pressure_boxes [cgroup_subscriptions]resource.Resource
	cgroup_pressure_used [cgroup_subscriptions]bool
)

// Static storage gives each open description its own acknowledgement without
// allocating during pressure. dup/fork share it; independent opens do not.
fn open_cgroup_pressure(group &CGroup, metadata stat.Stat) ?&resource.Resource {
	cgroup_subscriptions_lock.acquire()
	defer { cgroup_subscriptions_lock.release() }
	for i in 0 .. cgroup_subscriptions {
		if cgroup_pressure_used[i] { continue }
		cgroup_pressure_files[i] = CGroupPressureFile{stat: metadata, group: unsafe { group }, slot: i, status: 1 | 2}
		cgroup_pressure_boxes[i] = resource.Resource(unsafe { &cgroup_pressure_files[i] })
		cgroup_pressure_used[i] = true
		return &cgroup_pressure_boxes[i]
	}
	errno.set(errno.enospc)
	return none
}

// The one-second maintenance worker publishes events outside all admission,
// page-map and scheduler locks. A snapshot also exposes events immediately.
pub fn cgroup_pressure_maintenance() {
	// Stable mount-lifetime records let recovery refresh anonymous charges even
	// when no process reads memory.current after unmap or changes membership.
	cgroup_hierarchy_lock.acquire()
	mut group := cgroup_accounts
	cgroup_hierarchy_lock.release()
	for group != unsafe { nil } {
		if group.account != unsafe { nil } {
			mut account := group.account
			sample := cgcontrol.snapshot(proc.cgroup_control(account))
			if sample.pids != 0 || sample.anonymous != 0 {
				limit := katomic.load(&account.memory_max)
				if limit != 0 { enforce_memory_max(mut account, 0, limit, time.monotonic_ns(), 0) }
				else { cgroup_memory_bytes(group) }
			}
		}
		group = group.next_account
	}
	cgroup_subscriptions_lock.acquire()
	defer { cgroup_subscriptions_lock.release() }
	for i in 0 .. cgroup_subscriptions {
		if !cgroup_pressure_used[i] { continue }
		mut subscription := unsafe { &cgroup_pressure_files[i] }
		if subscription.group.account == unsafe { nil } { continue }
		sample := cgcontrol.snapshot(proc.cgroup_control(subscription.group.account))
		subscription.l.acquire()
		if sample.generation != subscription.acknowledged {
			subscription.status = 1 | 2
			event.trigger(mut subscription.event, true)
		}
		subscription.l.release()
	}
}

fn (mut this CGroupPressureFile) text(value string) {
	for c in value {
		if this.length == this.buffer.len { return }
		this.buffer[this.length] = c
		this.length++
	}
}

fn (mut this CGroupPressureFile) number(value u64) {
	mut digits := [20]u8{}
	mut remaining := value
	mut index := digits.len
	for {
		index--
		digits[index] = `0` + u8(remaining % 10)
		remaining /= 10
		if remaining == 0 { break }
	}
	for index < digits.len && this.length < this.buffer.len {
		this.buffer[this.length] = digits[index]
		this.length++; index++
	}
}

fn (mut this CGroupPressureFile) field(label string, value u64) {
	this.text(label); this.number(value); this.text('\n')
}

fn (mut this CGroupPressureFile) refresh() {
	sample := cgcontrol.snapshot(proc.cgroup_control(this.group.account))
	this.length = 0
	this.text('level ')
	this.text(match sample.level { 2 { 'critical' } 1 { 'warning' } else { 'normal' } })
	this.text('\n')
	this.field('generation ', sample.generation)
	this.field('memory_current ', sample.anonymous + sample.kernel)
	this.field('memory_max ', sample.memory_max)
	this.field('memory_high ', sample.memory_high)
	this.field('memory_max_events ', sample.memory_events)
	this.field('memory_high_events ', sample.high_events)
	this.field('swap_current ', sample.swap)
	this.field('swap_max_events ', sample.swap_events)
	this.field('pids_current ', sample.pids)
	this.field('pids_max ', sample.pids_max)
	this.field('pids_max_events ', sample.pids_events)
	this.field('cpu_throttled_events ', sample.cpu_events)
	this.field('io_throttled_events ', sample.io_events)
	this.acknowledged = sample.generation
	this.status = 0
}

fn (mut this CGroupPressureFile) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	if count == 0 { return 0 }
	this.l.acquire()
	defer { this.l.release() }
	if loc == 0 { this.refresh() }
	if loc >= u64(this.length) { return 0 }
	amount := if count < u64(this.length) - loc { count } else { u64(this.length) - loc }
	unsafe { C.memcpy(buf, &this.buffer[0] + loc, amount) }
	return i64(amount)
}

fn (mut this CGroupPressureFile) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) { return }
	cgroup_subscriptions_lock.acquire()
	// Handle references outlive reads and detached poll/epoll listeners. The
	// group itself retains its existing mount/namespace lifetime.
	cgroup_pressure_used[this.slot] = false
	cgroup_subscriptions_lock.release()
}

fn (mut this CGroupPressureFile) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 { errno.set(errno.eperm); return none }
fn (mut this CGroupPressureFile) ioctl(handle voidptr, request u64, argp voidptr) ?int { return resource.default_ioctl(handle, request, argp) }
fn (mut this CGroupPressureFile) mmap(_handle voidptr, _page u64, _flags int) voidptr { return unsafe { nil } }
fn (mut this CGroupPressureFile) grow(_handle voidptr, _size u64) ? { errno.set(errno.eperm); return none }
fn (mut this CGroupPressureFile) link(_handle voidptr) ? { errno.set(errno.eperm); return none }
fn (mut this CGroupPressureFile) unlink(_handle voidptr) ? { errno.set(errno.eperm); return none }
