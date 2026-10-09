// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module cgcontrol

import klock

// Admission never sleeps, allocates, takes a process lock or calls a reclaim
// hook. One lock makes checks and updates across a hierarchy indivisible.
// Groups are embedded in the mount-lifetime proc.CGroupAccount objects.
pub const devices = 32
const unlimited = ~u64(0)

pub struct Device {
pub mut:
	used bool
	id u64
	rbps u64
	wbps u64
	riops u64
	wiops u64
	rbytes u64
	wbytes u64
	rios u64
	wios u64
	read_until u64
	write_until u64
}

pub struct Group {
pub mut:
	parent &Group = unsafe { nil }
	accepting bool = true
	pids_max u64 = unlimited
	pids u64
	pids_peak u64
	pids_events u64
	memory_max u64 = unlimited
	memory_high u64 = unlimited
	swap_max u64 = unlimited
	swap u64
	swap_events u64
	anonymous u64
	kernel u64
	memory_peak u64
	memory_events u64
	high_events u64
	cpu_events u64
	io_events u64
	generation u64 = 1
	level int
	io [devices]Device
}

__global (controller_lock klock.Lock io_epoch u64 = 1)

pub fn snapshot(group &Group) Group {
	if group == unsafe { nil } { return Group{} }
	controller_lock.acquire()
	defer { controller_lock.release() }
	return if group == unsafe { nil } { Group{} } else { unsafe { *group } }
}

fn update(mut group Group) {
	usage := group.anonymous + group.kernel
	if usage > group.memory_peak { group.memory_peak = usage }
	level := if usage >= group.memory_max { 2 } else if usage > group.memory_high { 1 } else { 0 }
	if group.level != level { group.level = level; group.generation++ }
}

pub fn set_pids_max(mut group Group, limit u64) {
	controller_lock.acquire()
	defer { controller_lock.release() }
	group.pids_max = limit
	group.generation++
}

pub fn set_memory_limits(mut group Group, limit u64, high bool) {
	controller_lock.acquire()
	defer { controller_lock.release() }
	if high { group.memory_high = limit } else { group.memory_max = limit }
	group.generation++
	update(mut group)
}

pub fn sample_memory(mut group Group, bytes u64) {
	controller_lock.acquire()
	defer { controller_lock.release() }
	group.anonymous = bytes
	update(mut group)
}

pub fn forget_memory(group &Group, bytes u64) {
	if group == unsafe { nil } { return }
	controller_lock.acquire()
	defer { controller_lock.release() }
	mut current := unsafe { group }
	for current != unsafe { nil } {
		current.anonymous = if bytes < current.anonymous { current.anonymous - bytes } else { u64(0) }
		update(mut current)
		current = current.parent
	}
}

pub fn note_memory(mut group Group, high bool) {
	controller_lock.acquire()
	defer { controller_lock.release() }
	if high { group.high_events++ } else { group.memory_events++ }
	group.generation++
}

pub fn note_cpu(mut group Group) {
	controller_lock.acquire()
	defer { controller_lock.release() }
	group.cpu_events++
	group.generation++
}

pub fn reconfigured(mut group Group) {
	controller_lock.acquire()
	group.generation++
	controller_lock.release()
}

pub fn set_swap_max(mut group Group, limit u64) {
	controller_lock.acquire()
	defer { controller_lock.release() }
	group.swap_max = limit
	group.generation++
}

pub fn reserve_swap(group &Group, bytes u64) bool {
	if group == unsafe { nil } { return true }
	controller_lock.acquire()
	defer { controller_lock.release() }
	mut current := unsafe { group }
	for current != unsafe { nil } {
		if bytes > current.swap_max || current.swap > current.swap_max - bytes {
			current.swap_events++; current.generation++
			return false
		}
		current = current.parent
	}
	current = unsafe { group }
	for current != unsafe { nil } { current.swap += bytes; current = current.parent }
	return true
}

pub fn release_swap(group &Group, bytes u64) {
	if group == unsafe { nil } { return }
	controller_lock.acquire()
	defer { controller_lock.release() }
	mut current := unsafe { group }
	for current != unsafe { nil } {
		assert current.swap >= bytes
		current.swap -= bytes
		current = current.parent
	}
}

fn add_locked(group &Group, kernel u64, tasks u64) {
	mut current := unsafe { group }
	for current != unsafe { nil } {
		current.kernel += kernel
		current.pids += tasks
		if current.pids > current.pids_peak { current.pids_peak = current.pids }
		update(mut current)
		current = current.parent
	}
}

fn subtract_locked(group &Group, kernel u64, tasks u64) {
	mut current := unsafe { group }
	for current != unsafe { nil } {
		assert current.kernel >= kernel && current.pids >= tasks
		current.kernel -= kernel
		current.pids -= tasks
		update(mut current)
		current = current.parent
	}
}

fn fits_locked(group &Group, kernel u64, tasks u64) bool {
	mut current := unsafe { group }
	for current != unsafe { nil } {
		if tasks != 0 && !current.accepting { return false }
		if tasks != 0 && (tasks > current.pids_max || current.pids > current.pids_max - tasks) {
			current.pids_events++
			current.generation++
			return false
		}
		usage := current.anonymous + current.kernel
		if kernel != 0 && (kernel > current.memory_max || usage > current.memory_max - kernel) {
			current.memory_events++
			current.generation++
			return false
		}
		current = current.parent
	}
	return true
}

pub fn may_reserve(group &Group, kernel u64, tasks u64) bool {
	if group == unsafe { nil } { return true }
	controller_lock.acquire()
	defer { controller_lock.release() }
	return fits_locked(group, kernel, tasks)
}

pub fn reserve(group &Group, kernel u64, tasks u64) bool {
	if group == unsafe { nil } { return true }
	controller_lock.acquire()
	defer { controller_lock.release() }
	if !fits_locked(group, kernel, tasks) { return false }
	add_locked(group, kernel, tasks)
	return true
}

pub fn release(group &Group, kernel u64, tasks u64) {
	if group == unsafe { nil } { return }
	controller_lock.acquire()
	defer { controller_lock.release() }
	subtract_locked(group, kernel, tasks)
}

// Migration checks only new ancestors. A move within a full parent neither
// double counts the workload nor requires temporary spare quota. On failure
// membership and usage remain unchanged; denial events still record the failure.
pub fn move(from &Group, to &Group, kernel u64, tasks u64) bool {
	return move_workload(from, to, kernel, tasks, 0)
}

pub fn move_workload(from &Group, to &Group, kernel u64, tasks u64, anonymous u64) bool {
	if voidptr(from) == voidptr(to) { return true }
	controller_lock.acquire()
	defer { controller_lock.release() }
	mut current := unsafe { to }
	for current != unsafe { nil } {
		mut old := unsafe { from }
		mut common := false
		for old != unsafe { nil } {
			if voidptr(old) == voidptr(current) { common = true; break }
			old = old.parent
		}
		if !common && (anonymous > unlimited - kernel || !fits_one_locked(mut current, kernel + anonymous, tasks)) { return false }
		current = current.parent
	}
	// Anonymous charges move only through ancestors that change membership.
	// A shared full parent keeps exactly the same committed workload.
	current = unsafe { from }
	for current != unsafe { nil } {
		if !within(to, current) {
			current.anonymous = if anonymous < current.anonymous { current.anonymous - anonymous } else { u64(0) }
		}
		current = current.parent
	}
	current = unsafe { to }
	for current != unsafe { nil } {
		if !within(from, current) { current.anonymous += anonymous }
		current = current.parent
	}
	subtract_locked(from, kernel, tasks)
	add_locked(to, kernel, tasks)
	return true
}

fn within(group &Group, ancestor &Group) bool {
	mut current := unsafe { group }
	for current != unsafe { nil } {
		if voidptr(current) == voidptr(ancestor) { return true }
		current = current.parent
	}
	return false
}

fn fits_one_locked(mut current Group, kernel u64, tasks u64) bool {
	if tasks != 0 && !current.accepting { return false }
	if tasks != 0 && (tasks > current.pids_max || current.pids > current.pids_max - tasks) {
		current.pids_events++; current.generation++
		return false
	}
	usage := current.anonymous + current.kernel
	if kernel != 0 && (kernel > current.memory_max || usage > current.memory_max - kernel) {
		current.memory_events++; current.generation++
		return false
	}
	return true
}

pub fn retire(mut group Group) bool {
	controller_lock.acquire()
	defer { controller_lock.release() }
	if group.pids != 0 { return false }
	group.accepting = false
	group.generation++
	return true
}

// No allocating fields()/split() and no unchecked numeric conversion on
// user-controlled limits. Overflow must never turn a finite quota into max.
pub fn decimal(value string) ?u64 {
	if value.len == 0 { return none }
	mut result := u64(0)
	for c in value {
		if c < `0` || c > `9` || result > (unlimited - u64(c - `0`)) / 10 { return none }
		result = result * 10 + u64(c - `0`)
	}
	return result
}

pub fn dev_id(major u64, minor u64) ?u64 {
	if major > 0xfff || minor > 0xfffff { return none }
	return (minor & 0xff) | (major << 8) | ((minor & ~u64(0xff)) << 12)
}

pub fn dev_major(id u64) u64 { return (id >> 8) & 0xfff }
pub fn dev_minor(id u64) u64 { return (id & 0xff) | ((id >> 12) & 0xfffff00) }

pub fn set_io(mut group Group, limits Device) bool {
	controller_lock.acquire()
	defer { controller_lock.release() }
	mut slot := -1
	for i in 0 .. devices {
		if group.io[i].used && group.io[i].id == limits.id { slot = i; break }
		if !group.io[i].used && slot < 0 { slot = i }
	}
	if slot < 0 { return false }
	mut d := unsafe { &group.io[slot] }
	d.used = true; d.id = limits.id
	d.rbps = limits.rbps; d.wbps = limits.wbps
	d.riops = limits.riops; d.wiops = limits.wiops
	d.read_until = 0; d.write_until = 0
	group.generation++
	// A limit change releases outstanding delays, including max. Epochs
	// prevent a previously issued request from stranding its task forever.
	io_epoch++
	return true
}

pub fn epoch() u64 {
	controller_lock.acquire()
	defer { controller_lock.release() }
	return io_epoch
}

// Reconfiguration may clear one controller's debt while an ancestor still
// owns it. Changing a child or an unrelated group cannot bypass that quota.
pub fn io_pending(group &Group, now u64) bool {
	controller_lock.acquire()
	defer { controller_lock.release() }
	mut current := unsafe { group }
	for current != unsafe { nil } {
		for d in current.io {
			if d.used && (d.read_until > now || d.write_until > now) { return true }
		}
		current = current.parent
	}
	return false
}

fn duration(amount u64, rate u64) u64 {
	if rate == 0 || amount == 0 { return 0 }
	seconds := amount / rate
	if seconds > unlimited / 1000000000 { return unlimited }
	whole := seconds * 1000000000
	// Requests are bounded by the driver. Quotient/remainder avoids overflow
	// even when a controller is configured with UINT64_MAX bytes per second.
	remainder := amount % rate
	mut fraction := u64(0)
	if remainder <= unlimited / 1000000000 {
		product := remainder * 1000000000
		fraction = product / rate + if product % rate != 0 { u64(1) } else { u64(0) }
	} else {
		fraction = 1000000000 // conservative, never undercharge an oversized request
	}
	return if fraction > unlimited - whole { unlimited } else { whole + fraction }
}

// A completed request adds service debt to the issuing task; the scheduler
// pays it only at a boundary where no device/VM/filesystem lock is held.
// Parallel issuers share one virtual service clock at every ancestor.
pub fn account_io(group &Group, id u64, bytes u64, write bool, now u64) (u64, u64) {
	controller_lock.acquire()
	defer { controller_lock.release() }
	mut until := now
	mut current := unsafe { group }
	for current != unsafe { nil } {
		mut slot := -1
		for i in 0 .. devices {
			if current.io[i].used && current.io[i].id == id { slot = i; break }
			if !current.io[i].used && slot < 0 { slot = i }
		}
		if slot >= 0 {
			mut d := unsafe { &current.io[slot] }
			d.used = true; d.id = id
			mut service := u64(0)
			mut next := now
			if write {
				d.wbytes += bytes; d.wios++
				service = duration(bytes, d.wbps)
				op := duration(1, d.wiops)
				if op > service { service = op }
				if d.write_until > next { next = d.write_until }
			} else {
				d.rbytes += bytes; d.rios++
				service = duration(bytes, d.rbps)
				op := duration(1, d.riops)
				if op > service { service = op }
				if d.read_until > next { next = d.read_until }
			}
			if service != 0 {
				next = if service > unlimited - next { unlimited } else { next + service }
				if write { d.write_until = next } else { d.read_until = next }
				if next > until { until = next }
				current.io_events++; current.generation++
			}
		}
		current = current.parent
	}
	return until, io_epoch
}
