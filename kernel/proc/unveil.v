// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// unveil(2), as OpenBSD has it. The first call hides the whole filesystem
// from the process except the path it names, with the access it names: some
// of r(ead), w(rite), x (execute) and c(reate/remove). Every further call
// shows one more path, until unveil(NULL, NULL) locks the view. A file is
// judged by the unveiled path closest above it, so unveiling /usr/share with
// "r" and /usr/share/doc with "" leaves the documentation hidden.
//
// Paths are kept as absolute strings from the system root, through the
// process's mounts, which is what fs/policy.v computes for every file a call
// resolves; a chroot(2) after unveiling cannot rename them, and fs refuses
// the calls that could move the mounts under them. Symbolic links need no
// care: it is the file a lookup ends at that is judged, not the name that led
// there.
@[has_globals]
module proc

import klock

__global (
	// Serialises giving a process its first UnveilSet, which two of its
	// threads may try at once.
	unveil_create_lock klock.Lock
)

pub const unveil_read = u8(1)
pub const unveil_write = u8(2)
pub const unveil_exec = u8(4)
pub const unveil_create = u8(8)

// OpenBSD's own limit on unveiled paths per process.
pub const unveil_max_entries = 128

pub struct UnveilEntry {
pub mut:
	path  string
	perms u8
}

pub struct UnveilSet {
pub mut:
	l       klock.Lock
	entries []UnveilEntry
	// Set by unveil(NULL, NULL): the view can no longer change.
	locked bool
}

// The access an unveil permission string grants, or none for a character
// other than r, w, x and c.
pub fn unveil_parse(text string) ?u8 {
	mut perms := u8(0)
	for c in text {
		match c {
			`r` { perms |= unveil_read }
			`w` { perms |= unveil_write }
			`x` { perms |= unveil_exec }
			`c` { perms |= unveil_create }
			else { return none }
		}
	}
	return perms
}

// A set's entries are freed with it, in unveil_release(). Nothing slices them,
// so an entries array that grows gives its old buffer back.
fn new_unveil_set() &UnveilSet {
	mut entries := []UnveilEntry{cap: 8} @[freed]
	entries.flags |= .noslices
	return &UnveilSet{
		entries: entries
	}
}

fn unveil_set_of(mut process Process) &UnveilSet {
	unveil_create_lock.acquire()
	if process.unveil == unsafe { nil } {
		process.unveil = new_unveil_set()
	}
	unveil_create_lock.release()
	return process.unveil
}

// Show `path`, an absolute path as fs/policy.v spells it, with `perms`.
// Unveiling a path again changes its access. Answers an errno, or 0.
pub fn unveil_add(mut process Process, path string, perms u8) u64 {
	mut set := unveil_set_of(mut process)
	set.l.acquire()
	defer {
		set.l.release()
	}
	if set.locked {
		return pledge_eperm
	}
	for i := 0; i < set.entries.len; i++ {
		if set.entries[i].path == path {
			set.entries[i].perms = perms
			return 0
		}
	}
	if set.entries.len >= unveil_max_entries {
		return pledge_e2big
	}
	set.entries << UnveilEntry{
		path:  path.clone()
		perms: perms
	}
	return 0
}

// unveil(NULL, NULL). Called first, it leaves nothing in view at all.
pub fn unveil_lock(mut process Process) {
	mut set := unveil_set_of(mut process)
	set.l.acquire()
	set.locked = true
	set.l.release()
}

pub fn unveil_is_locked(process &Process) bool {
	set := process.unveil
	return set != unsafe { nil } && set.locked
}

// Whether `entry` is `path` or a directory above it.
@[inline]
fn unveil_covers(entry string, path string) bool {
	if entry == '/' {
		return true
	}
	if !path.starts_with(entry) {
		return false
	}
	return path.len == entry.len || path[entry.len] == `/`
}

// The unveil access that policy `access` needs.
fn unveil_needed(access u32) u8 {
	mut needed := u8(0)
	if access & policy_read != 0 {
		needed |= unveil_read
	}
	if access & (policy_write | policy_fattr | policy_chown) != 0 {
		needed |= unveil_write
	}
	if access & policy_exec != 0 {
		needed |= unveil_exec
	}
	if access & (policy_create | policy_device) != 0 {
		needed |= unveil_create
	}
	return needed
}

// Whether the process may make `access` to the file at `path`, an absolute
// path as fs/policy.v spells it. Answers 0, EACCES when the closest unveiled
// path above it does not grant the access, or ENOENT when none is unveiled
// there at all. An access that needs nothing in particular -- stat(2),
// access(2) with F_OK -- needs the path to be unveiled with anything but "":
// a shell looks a command up with stat() in a directory it may only execute
// from.
//
// OpenBSD looks a path up component by component, so that the directories
// above an unveiled path can be walked through but not otherwise looked at.
// Here only the file a lookup ends at is judged, which lets a directory above
// an unveiled path be inspected -- stat(2), chdir(2) -- as well: glibc's
// realpath() and getcwd() fallbacks stat every component, and OpenBSD has a
// realpath syscall to spare its libc the same trip.
pub fn unveil_verdict(process &Process, path string, access u32, is_dir bool) u64 {
	mut set := process.unveil
	if set == unsafe { nil } {
		return 0
	}
	needed := unveil_needed(access)
	set.l.acquire()
	defer {
		set.l.release()
	}
	mut best := -1
	mut best_len := -1
	mut above := false
	for i, entry in set.entries {
		if unveil_covers(entry.path, path) {
			if entry.path.len > best_len {
				best = i
				best_len = entry.path.len
			}
		} else if is_dir && unveil_covers(path, entry.path) {
			above = true
		}
	}
	if best >= 0 {
		perms := set.entries[best].perms
		if perms == 0 {
			return pledge_enoent
		}
		if needed & ~perms != 0 {
			return pledge_eacces
		}
		return 0
	}
	if above && access & ~policy_inspect == 0 {
		return 0
	}
	return pledge_enoent
}

// What the unveiled path closest above `path` grants; 0 for none.
fn unveil_perms_unlocked(set &UnveilSet, path string) u8 {
	mut best_len := -1
	mut perms := u8(0)
	for entry in set.entries {
		if entry.path.len > best_len && unveil_covers(entry.path, path) {
			best_len = entry.path.len
			perms = entry.perms
		}
	}
	return perms
}

// A hard link at `new_path` to the file at `target_path` may grant no access
// the file's own name does not. Answers 0 or EACCES.
pub fn unveil_link_verdict(process &Process, target_path string, new_path string) u64 {
	mut set := process.unveil
	if set == unsafe { nil } {
		return 0
	}
	set.l.acquire()
	defer {
		set.l.release()
	}
	granted := unveil_perms_unlocked(set, new_path) & (unveil_read | unveil_write | unveil_exec)
	if granted & ~unveil_perms_unlocked(set, target_path) != 0 {
		return pledge_eacces
	}
	return 0
}

// A child's own copy of its parent's view, which it may go on to narrow.
pub fn unveil_copy(set &UnveilSet) &UnveilSet {
	if set == unsafe { nil } {
		return unsafe { nil }
	}
	mut source := unsafe { set }
	source.l.acquire()
	defer {
		source.l.release()
	}
	mut entries := []UnveilEntry{cap: source.entries.len} @[freed]
	entries.flags |= .noslices
	mut copy := &UnveilSet{
		entries: entries
		locked:  source.locked
	}
	for entry in source.entries {
		copy.entries << UnveilEntry{
			path:  entry.path.clone()
			perms: entry.perms
		}
	}
	return copy
}

// Drop the process's view, leaving the whole filesystem in view: execve(2)
// without execpromises, and the reaper.
pub fn unveil_release(mut process Process) {
	mut set := process.unveil
	if set == unsafe { nil } {
		return
	}
	process.unveil = unsafe { nil }
	for i := 0; i < set.entries.len; i++ {
		unsafe { set.entries[i].path.free() }
	}
	unsafe {
		set.entries.free()
		free(set)
	}
}
