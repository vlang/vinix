// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

#include <sys/file.h>
fn C.flock(i32, i32) i32

struct PlanEdit {
mut:
	directory i32 = -1
	source i32 = -1
	locked bool
	name [256]char
}

// Lock the directory inode, not the replaceable saved-file inode. All callers
// own partial state and must close it even when acquisition/opening fails.
@[direct_array_access]
fn open_plan_destination(path &char, mut edit PlanEdit, writing bool) bool {
	if edit.directory >= 0 || edit.source >= 0 { return false }
	edit.name = [256]char{}
	edit.locked = false
	mut parent := [4096]char{}
	mut length := 0
	mut slash := -1
	unsafe {
		for path[length] != 0 {
			if length >= 4095 { plan_error(c'plan path is too long'); return false }
			if path[length] == char(`/`) { slash = length }
			length++
		}
		basename := slash + 1
		if length == basename || length - basename > 255 { plan_error(c'invalid plan filename'); return false }
		for i := basename; i < length; i++ { edit.name[i - basename] = path[i] }
		if C.strcmp(&edit.name[0], c'.') == 0 || C.strcmp(&edit.name[0], c'..') == 0 { return false }
		if slash < 0 { parent[0] = char(`.`) }
		else if slash == 0 { parent[0] = char(`/`) }
		else { for i := 0; i < slash; i++ { parent[i] = path[i] } }
	}
	edit.directory = C.open(&parent[0], C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if edit.directory < 0 { C.perror(c'vinix-volume: open plan directory'); return false }
	if writing {
		for {
			if C.flock(edit.directory, C.LOCK_EX | C.LOCK_NB) == 0 { break }
			if unsafe { C.errno == C.EINTR } { continue }
			C.perror(c'vinix-volume: plan directory is busy or locking failed')
			return false
		}
		edit.locked = true
	}
	return true
}

fn open_plan_edit(path &char, mut edit PlanEdit, writing bool) bool {
	if !open_plan_destination(path, mut edit, writing) { return false }
	edit.source = C.openat(edit.directory, &edit.name[0], C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if edit.source < 0 { C.perror(c'vinix-volume: open saved bundle'); return false }
	return true
}

fn close_plan_edit(mut edit PlanEdit) {
	if edit.source >= 0 { C.close(edit.source); edit.source = -1 }
	// flock is released by the last close, including process termination. Never
	// unlock explicitly: the publisher's duplicate shares this open description.
	if edit.directory >= 0 { C.close(edit.directory); edit.directory = -1 }
	edit.locked = false
}

fn publish_edit_bytes(edit &PlanEdit, bytes &u8, size int) bool {
	if edit.directory < 0 || !edit.locked || size <= 0 { return false }
	directory := C.fcntl(edit.directory, C.F_DUPFD_CLOEXEC, 0)
	if directory < 0 { C.perror(c'vinix-volume: duplicate plan directory'); return false }
	return publish_bytes_at(directory, &edit.name[0], bytes, size)
}

fn publish_edit_bundle(edit &PlanEdit, set &PlanSet) bool {
	mut bytes := [8768]u8{}
	size := encode_bundle(set, &bytes[0])
	if size == 0 { plan_error(c'invalid volume bundle snapshot'); return false }
	return publish_edit_bytes(edit, &bytes[0], size)
}

fn publish_edit_plan(edit &PlanEdit, plan &Plan) bool {
	mut bytes := [2112]u8{}
	size := encode_plan(plan, &bytes[0])
	if size == 0 { plan_error(c'invalid volume snapshot'); return false }
	return publish_edit_bytes(edit, &bytes[0], size)
}
