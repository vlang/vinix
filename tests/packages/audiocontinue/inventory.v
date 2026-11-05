// SPDX-License-Identifier: GPL-2.0-or-later
module audiocontinue

import os
import time
import tests.packages.audioprepare

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <stdio.h>
#include <sys/stdio.h>
#include <unistd.h>

fn C.open(&char, i32, ...i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.renamex_np(&char, &char, u32) i32

pub struct Usage2 {
pub mut:
	allocated u64
	// Conservative 4KiB entry rounding, above the observed 1KiB du units.
	apparent u64
	raw_apparent u64
	entries int
}

pub fn hex2(text string, length int) bool {
	return text.len == length && text.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

pub fn relative2(path string) bool {
	return path != '' && !os.is_abs_path(path) && !path.contains('\\')
		&& !path.bytes().any(it < 32 || it == 127)
		&& path.split('/').all(it !in ['', '.', '..'])
}

pub fn canonical2(path string) ! {
	if !os.is_abs_path(path) || path != os.real_path(path) || path.contains('|')
		|| path.bytes().any(it < 32 || it == 127) {
		return error('requires canonical absolute path without V path separators: ' + path)
	}
}

pub fn ordinary2(path string, kind string) ! {
	canonical2(path)!
	bits := os.lstat(path)!.mode & 0o170000
	if (kind == 'file' && bits != 0o100000) || (kind == 'directory' && bits != 0o040000)
		|| kind !in ['file', 'directory'] { return error('nonordinary ' + kind + ': ' + path) }
}

pub fn digest2(path string) !string { return audioprepare.digest(path) }

pub fn under2(root string, path string) bool { return path == root || path.starts_with(root + '/') }

pub fn disjoint2(a string, b string) bool { return !under2(a, b) && !under2(b, a) }

pub fn leaf2(root string, relative string, kind string) !string {
	ordinary2(root, 'directory')!
	if !relative2(relative) { return error('invalid relative role leaf: ' + relative) }
	parts := relative.split('/')
	mut current := root
	for i, part in parts {
		current += '/' + part
		ordinary2(current, if i + 1 == parts.len { kind } else { 'directory' })!
	}
	return current
}

fn tick2(started i64, depth int, entries int) ! {
	if depth > 64 || entries > 250000 || time.sys_mono_now() - started > i64(300000) * 1000000 {
		return error('complete inventory exceeds depth, entry count or 300-second bound')
	}
}

fn same2(a os.Stat, b os.Stat) bool {
	return a.mode == b.mode && a.uid == b.uid && a.gid == b.gid && a.dev == b.dev
		&& a.inode == b.inode && a.nlink == b.nlink && a.size == b.size
		&& a.rdev == b.rdev && a.mtime == b.mtime && a.ctime == b.ctime
}

fn entry2(root string, path string, role string) !DonorEntry2 {
	full := if path == '' { root } else { root + '/' + path }
	before := os.lstat(full)!
	kind := before.mode & 0o170000
	if kind !in [u32(0o100000), u32(0o040000)] {
		return error('immutable inventories refuse links and special objects: ' + full)
	}
	sum := if kind == 0o100000 { digest2(full)! } else { '' }
	if !same2(before, os.lstat(full)!) { return error('input changed during inventory: ' + full) }
	return DonorEntry2{root: role, path: path,
		kind: if kind == 0o100000 { 'file' } else { 'directory' }, mode: before.mode,
		uid: before.uid, gid: before.gid, dev: before.dev, inode: before.inode,
		nlink: u64(before.nlink), size: before.size, mtime: before.mtime, ctime: before.ctime,
		sha256: sum}
}

fn visit2(root string, path string, role string, depth int, started i64, mut entries []DonorEntry2) ! {
	tick2(started, depth, entries.len)!
	if path != '' && !relative2(path) { return error('invalid inventory path') }
	full := if path == '' { root } else { root + '/' + path }
	before := os.lstat(full)!
	value := entry2(root, path, role)!
	entries << value
	if value.kind == 'directory' {
		mut names := os.ls(full)!
		names.sort()
		for name in names {
			visit2(root, if path == '' { name } else { path + '/' + name }, role, depth + 1, started, mut entries)!
		}
		if !same2(before, os.lstat(full)!) { return error('directory changed during inventory: ' + full) }
	}
}

pub fn inventory2(roots map[string]string) ![]DonorEntry2 {
	mut roles := roots.keys()
	roles.sort()
	mut entries := []DonorEntry2{}
	started := time.sys_mono_now()
	for role in roles {
		if !relative2(role) || role.contains('/') { return error('invalid immutable root role') }
		ordinary2(roots[role], 'directory')!
		for other, path in roots {
			if role != other && !disjoint2(roots[role], path) { return error('immutable roots overlap') }
		}
		visit2(roots[role], '', role, 0, started, mut entries)!
	}
	return entries
}

pub struct Observation2 {
pub:
	entries []DonorEntry2
	errors map[string]string
}

// Observation is deliberately independent per root. A damaged capture cannot
// suppress the intact store or the entries obtained before its own failure.
// Strict acceptance still uses inventory2 and requires complete equality.
pub fn observe_roots2(roots map[string]string) Observation2 {
	mut roles := roots.keys()
	roles.sort()
	mut entries := []DonorEntry2{}
	mut errors := map[string]string{}
	for role in roles {
		if !relative2(role) || role.contains('/') {
			errors[role] = 'invalid immutable root role'
			continue
		}
		ordinary2(roots[role], 'directory') or { errors[role] = err.msg(); continue }
		mut partial := []DonorEntry2{}
		visit2(roots[role], '', role, 0, time.sys_mono_now(), mut partial) or {
			errors[role] = err.msg()
		}
		entries << partial
	}
	return Observation2{entries: entries, errors: errors}
}

pub fn inode_key2(dev u64, inode u64) string { return dev.str() + '/' + inode.str() }

// An alias outside this complete immutable forest could be a mutable write
// path. Count all names, including historical capture/store aliases, exactly.
pub fn closed_aliases2(entries []DonorEntry2, single bool) ! {
	mut counts := map[string]u64{}
	for value in entries {
		if value.kind == 'file' { counts[inode_key2(value.dev, value.inode)]++ }
	}
	for value in entries {
		if value.kind == 'file' && (value.nlink == 0 || value.nlink != counts[inode_key2(value.dev, value.inode)]
			|| (single && value.nlink != 1)) {
			return error('immutable file has an uncontained or disallowed hard-link alias: ' + value.root + '/' + value.path)
		}
	}
}

fn owned_visit2(root string, path string, ignored []string, depth int, started i64,
	donor_ids map[string]bool, mut result []OwnedEntry2) ! {
	if path in ignored { return }
	tick2(started, depth, result.len)!
	value := entry2(root, path, 'state')!
	if value.kind == 'file' && (value.nlink != 1 || donor_ids[inode_key2(value.dev, value.inode)]) {
		return error('mutable output aliases another name or immutable donor: ' + path)
	}
	result << OwnedEntry2{path: path, kind: value.kind, mode: value.mode,
		uid: value.uid, gid: value.gid,
		dev: value.dev, inode: value.inode,
		// APFS includes regular children in a directory's nlink. Publishing the
		// sole excluded receipt changes it, just like the root size/times.
		nlink: if path == '' { 0 } else { value.nlink },
		size: if path == '' { 0 } else { value.size },
		mtime: if path == '' { 0 } else { value.mtime },
		ctime: if path == '' { 0 } else { value.ctime }, sha256: value.sha256}
	if value.kind == 'directory' {
		mut names := os.ls(if path == '' { root } else { root + '/' + path })!
		names.sort()
		for name in names {
			owned_visit2(root, if path == '' { name } else { path + '/' + name }, ignored,
				depth + 1, started, donor_ids, mut result)!
		}
		after := os.lstat(if path == '' { root } else { root + '/' + path })!
		if after.mode != value.mode || after.uid != value.uid || after.gid != value.gid
			|| after.dev != value.dev || after.inode != value.inode || u64(after.nlink) != value.nlink
			|| after.size != value.size || after.mtime != value.mtime || after.ctime != value.ctime {
			return error('owned directory changed during inventory: ' + path)
		}
	}
}

pub fn capture_owned2(root string, ignored []string, donor Donor2) ![]OwnedEntry2 {
	ordinary2(root, 'directory')!
	if ignored != []string{} && ignored != ['preparation2.json']
		&& ignored != ['preparation2.pending.json'] {
		return error('only one exact final or pending preparation receipt may be excluded')
	}
	mut ids := map[string]bool{}
	for value in donor.entries {
		if value.kind == 'file' { ids[inode_key2(value.dev, value.inode)] = true }
	}
	mut result := []OwnedEntry2{}
	owned_visit2(root, '', ignored, 0, time.sys_mono_now(), ids, mut result)!
	return result
}

// All candidate verification, cancellation, resource and deadline gates belong
// before this call. Exclusive rename is the last fallible operation. There is
// intentionally no post-publication I/O or refusal-write dependency.
fn publish_candidate2(root string) ! {
	pending := root + '/preparation2.pending.json'
	final := root + '/preparation2.json'
	if C.renamex_np(pending.str, final.str, u32(C.RENAME_EXCL)) != 0 {
		return error('exclusive preparation publication failed; retain pending evidence')
	}
}

pub fn write_new2(path string, text string) ! {
	canonical2(path)!
	ordinary2(os.dir(path), 'directory')!
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, i32(0o600))
	if fd < 0 { return error('requires exclusively new output: ' + path) }
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut offset := 0
	for offset < text.len {
		n := C.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 || n > isize(text.len - offset) { return error('write failed; retain partial output') }
		offset += int(n)
	}
	closed = true
	if C.close(fd) != 0 { return error('output close failed') }
	if os.lstat(path)!.nlink != 1 || os.read_file(path)! != text { return error('new output readback differs') }
}

pub fn copy_new2(source string, destination string, donor Donor2) ! {
	ordinary2(source, 'file')!
	canonical2(destination)!
	ordinary2(os.dir(destination), 'directory')!
	if os.exists(destination) || os.is_link(destination) { return error('copy requires fresh destination') }
	before := os.lstat(source)!
	sum := digest2(source)!
	os.cp(source, destination, fail_if_exists: true)!
	copy := os.lstat(destination)!
	if copy.nlink != 1 || (copy.dev == before.dev && copy.inode == before.inode)
		|| copy.mode != before.mode || digest2(destination)! != sum || !same2(before, os.lstat(source)!) {
		return error('copy is not independent and identical; retain outputs')
	}
	for value in donor.entries {
		if value.kind == 'file' && copy.dev == value.dev && copy.inode == value.inode {
			return error('fresh copy aliases an immutable donor')
		}
	}
}

fn usage_visit2(path string, device u64, depth int, started i64, mut result Usage2) ! {
	result.entries++
	tick2(started, depth, result.entries)!
	mut stat := C.stat{}
	if unsafe { C.lstat(&char(path.str), &stat) } != 0 || u64(stat.st_dev) != device
		|| stat.st_blocks < 0 || stat.st_size < 0 { return error('namespace lstat/device/size refused') }
	allocated := u64(stat.st_blocks) * 512
	size := u64(stat.st_size)
	if size > ~u64(0) - 4095 { return error('namespace rounding overflow') }
	charged := ((size + 4095) / 4096) * 4096
	if allocated > ~u64(0) - result.allocated || charged > ~u64(0) - result.apparent
		|| size > ~u64(0) - result.raw_apparent { return error('namespace sum overflow') }
	result.allocated += allocated
	result.apparent += charged
	result.raw_apparent += size
	if stat.st_mode & C.S_IFMT == C.S_IFDIR {
		for name in os.ls(path)! { usage_visit2(path + '/' + name, device, depth + 1, started, mut result)! }
	} else if stat.st_mode & C.S_IFMT != C.S_IFREG && stat.st_mode & C.S_IFMT != C.S_IFLNK {
		return error('nonordinary charged namespace object')
	}
}

pub fn usage2(roots []string) !Usage2 {
	if roots.len == 0 { return error('empty aggregate namespace') }
	device := os.lstat(roots[0])!.dev
	mut result := Usage2{}
	for root in roots {
		ordinary2(root, 'directory')!
		for other in roots { if other != root && !disjoint2(root, other) { return error('charged roots overlap') } }
		if roots.filter(it == root).len != 1 { return error('duplicate charged root') }
		usage_visit2(root, device, 0, time.sys_mono_now(), mut result)!
	}
	return result
}
