// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module volumecli

#include <errno.h>
#include <alloca.h>
#include <string.h>
#include <sys/stat.h>

struct C.stat {
mut:
	st_mode u32
	st_size i64
	st_uid u32
}

@[c_extern] __global C.errno i32
fn C.fstat(i32, &C.stat) i32
fn C.S_ISREG(u32) i32
fn C.read(i32, voidptr, usize) i64
fn C.write(i32, voidptr, usize) i64
fn C.pread(i32, voidptr, usize, i64) i64
fn C.fsync(i32) i32
fn C.openat(i32, &char, i32, ...voidptr) i32
fn C.renameat(i32, &char, i32, &char) i32
fn C.unlinkat(i32, &char, i32) i32
fn C.snprintf(&char, usize, &char, ...voidptr) i32
fn C.getpid() i32
fn C.alloca(usize) voidptr

fn plan_error(message &char) i32 { C.printf(c'vinix-volume: %s\n', message); return 1 }

fn query_status(fd i32, mut status Status) bool {
	if C.ioctl(fd, u64(0x56560004), &status) != 0 { C.perror(c'vinix-volume: status'); return false }
	if status.version != 1 || status.reserved != 0 || status.flags & 2 != 0 {
		plan_error(c'unsupported or offline block device'); return false
	}
	return true
}

fn probe_disk(fd i32, mut key DiskKey, mut status Status) bool {
	if !query_status(fd, mut status) { return false }
	if status.flags & (8 | 16) != 0 || status.start != 0 || status.bytes < status.sector * 2
		|| status.sector < 512 || status.sector > 4096 {
		plan_error(c'plans require a whole physical disk with supported geometry'); return false
	}
	mut sectors := [8192]u8{}
	size := status.sector * 2
	mut read := i64(-1)
	for {
		read = C.pread(fd, &sectors[0], usize(size), 0)
		if read >= 0 || unsafe { C.errno != C.EINTR } { break }
	}
	if read != i64(size) { C.perror(c'vinix-volume: disk identity read'); return false }
	if !identify_disk(&sectors[0], int(size), status.bytes, status.sector, mut key) {
		plan_error(c'disk needs a valid GPT GUID or a nonzero MBR disk signature'); return false
	}
	return true
}

@[direct_array_access]
fn load_plan(path &char, mut plan Plan) bool {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open plan'); return false }
	defer { C.close(fd) }
	return read_plan(fd, mut plan, false)
}

@[direct_array_access]
fn read_plan(fd i32, mut plan Plan, trusted bool) bool {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 { C.perror(c'vinix-volume: stat plan'); return false }
	if C.S_ISREG(info.st_mode) == 0 || info.st_size < plan_header_bytes || info.st_size > plan_max_bytes {
		plan_error(c'plan must be a bounded regular file'); return false
	}
	if trusted && (info.st_uid != 0 || info.st_mode & 0o022 != 0) {
		plan_error(c'boot plan must be owned by root and not writable by group or others'); return false
	}
	mut bytes := [2112]u8{}
	mut done := i64(0)
	for done < info.st_size {
		read := C.read(fd, unsafe { &bytes[done] }, usize(info.st_size - done))
		if read < 0 && unsafe { C.errno == C.EINTR } { continue }
		if read <= 0 { plan_error(c'short plan read'); return false }
		done += read
	}
	mut extra := u8(0)
	for {
		read := C.read(fd, &extra, 1)
		if read < 0 && unsafe { C.errno == C.EINTR } { continue }
		if read != 0 { plan_error(c'plan changed or has trailing bytes'); return false }
		break
	}
	if !decode_plan(&bytes[0], int(done), mut plan) {
		plan_error(c'invalid plan version, checksum, geometry or mapping'); return false
	}
	return true
}

// Anchor temporary creation and rename to the same directory descriptor.
// File contents and the directory entry are both flushed before success.
@[direct_array_access]
fn publish_plan(path &char, plan &Plan) bool {
	mut bytes := [2112]u8{}
	size := encode_plan(plan, &bytes[0])
	if size == 0 { plan_error(c'invalid volume snapshot'); return false }
	mut parent := [4096]char{}
	mut name := [256]char{}
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
		for i := basename; i < length; i++ { name[i - basename] = path[i] }
		if C.strcmp(&name[0], c'.') == 0 || C.strcmp(&name[0], c'..') == 0 { return false }
		if slash < 0 { parent[0] = char(`.`) }
		else if slash == 0 { parent[0] = char(`/`) }
		else { for i := 0; i < slash; i++ { parent[i] = path[i] } }
	}
	directory := C.open(&parent[0], C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if directory < 0 { C.perror(c'vinix-volume: open plan directory'); return false }
	defer { C.close(directory) }
	mut temporary := [64]char{}
	mut fd := i32(-1)
	for attempt := 0; attempt < 64; attempt++ {
		C.snprintf(&temporary[0], 64, c'.vinix-volume-%ld-%u', i64(C.getpid()), u32(attempt))
		fd = C.openat(directory, &temporary[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, u32(0o600))
		if fd >= 0 || unsafe { C.errno != C.EEXIST } { break }
	}
	if fd < 0 { C.perror(c'vinix-volume: create temporary plan'); return false }
	defer {
		if fd >= 0 { C.close(fd) }
		C.unlinkat(directory, &temporary[0], 0)
	}
	mut done := 0
	for done < size {
		written := C.write(fd, unsafe { &bytes[done] }, usize(size - done))
		if written < 0 && unsafe { C.errno == C.EINTR } { continue }
		if written <= 0 { C.perror(c'vinix-volume: write plan'); return false }
		done += int(written)
	}
	if C.fsync(fd) != 0 { C.perror(c'vinix-volume: flush plan'); return false }
	closed := C.close(fd)
	fd = -1
	if closed != 0 { C.perror(c'vinix-volume: close plan'); return false }
	if C.renameat(directory, &temporary[0], directory, &name[0]) != 0 {
		C.perror(c'vinix-volume: publish plan'); return false
	}
	if C.fsync(directory) != 0 { C.perror(c'vinix-volume: plan published but directory flush failed'); return false }
	return true
}

fn volume_path(slot u32, buffer &char) { C.snprintf(buffer, 64, c'/dev/mapper/vinix%u', slot) }

@[direct_array_access]
fn save_plan(device &char, path &char) i32 {
	fd := C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { C.perror(c'vinix-volume: open disk'); return 1 }
	defer { C.close(fd) }
	mut plan := unsafe { &Plan(C.alloca(sizeof(Plan))) }
	unsafe { *plan = Plan{} }
	mut parent := Status{}
	if !probe_disk(fd, mut plan.key, mut parent) { return 1 }
	for slot := u32(0); slot < 64; slot++ {
		mut name := [64]char{}
		volume_path(slot, &name[0])
		view := C.open(&name[0], C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if view < 0 {
			if unsafe { C.errno == C.ENOENT } { continue }
			C.perror(c'vinix-volume: open mapping'); return 1
		}
		mut status := Status{}
		valid := query_status(view, mut status)
		C.close(view)
		if !valid { return 1 }
		if status.disk_id != parent.disk_id { continue }
		if status.flags & 8 == 0 || status.slot != slot || status.sector != parent.sector {
			return plan_error(c'mapper slot has incompatible metadata')
		}
		plan.rows[plan.count] = Request{slot: slot, offset: status.start, length: status.bytes, flags: status.flags & 1}
		plan.count++
	}
	mut after := unsafe { &DiskKey(C.alloca(sizeof(DiskKey))) }
	unsafe { *after = DiskKey{} }
	mut status := Status{}
	if !probe_disk(fd, mut after, mut status) || !key_matches(unsafe { &plan.key }, after) || status.disk_id != parent.disk_id {
		return plan_error(c'disk identity changed while saving')
	}
	if !publish_plan(path, plan) { return 1 }
	C.printf(c'saved %u volume mappings\n', plan.count)
	return 0
}

fn mapping_matches(status &Status, parent &Status, row &Request) bool {
	return status.flags & 8 != 0 && status.slot == row.slot && status.disk_id == parent.disk_id
		&& status.start == row.offset && status.bytes == row.length && status.sector == parent.sector
		&& status.flags & 1 == row.flags
}

@[direct_array_access]
fn plan_writable(plan &Plan) bool {
	for i := u32(0); i < plan.count; i++ { if plan.rows[i].flags == 0 { return true } }
	return false
}

@[direct_array_access]
fn restore_plan(device &char, path &char) i32 {
	mut plan := unsafe { &Plan(C.alloca(sizeof(Plan))) }
	unsafe { *plan = Plan{} }
	if !load_plan(path, mut plan) { return 1 }
	flags := i32(if plan_writable(plan) { C.O_RDWR } else { C.O_RDONLY }) | i32(C.O_CLOEXEC | C.O_NOFOLLOW)
	fd := C.open(device, flags)
	if fd < 0 { C.perror(c'vinix-volume: open disk'); return 1 }
	defer { C.close(fd) }
	return restore_loaded(fd, plan)
}

@[direct_array_access]
fn restore_loaded(fd i32, plan &Plan) i32 {
	mut state := unsafe { &RestoreState(C.alloca(sizeof(RestoreState))) }
	unsafe { *state = RestoreState{} }
	if !prepare_restore(fd, plan, mut state) { return 1 }
	return apply_restore(fd, plan, state)
}

struct RestoreState {
mut:
	parent Status
	present [64]bool
}

fn verify_restore_disk(fd i32, plan &Plan, parent &Status) bool {
	mut key := unsafe { &DiskKey(C.alloca(sizeof(DiskKey))) }
	unsafe { *key = DiskKey{} }
	mut status := Status{}
	if !probe_disk(fd, mut key, mut status) || !key_matches(key, unsafe { &plan.key }) || status.disk_id != parent.disk_id {
		plan_error(c'disk identity changed before restore'); return false
	}
	return true
}

// Separate preflight from mutation so a plan set can check every disk and
// occupied slot before creating the first mapping on any disk.
@[direct_array_access]
fn prepare_restore(fd i32, plan &Plan, mut state RestoreState) bool {
	mut key := unsafe { &DiskKey(C.alloca(sizeof(DiskKey))) }
	unsafe { *key = DiskKey{} }
	state = RestoreState{}
	if !probe_disk(fd, mut key, mut state.parent) { return false }
	if !key_matches(key, unsafe { &plan.key }) { plan_error(c'plan disk identity or geometry does not match'); return false }
	// Also check unlisted managed extents: a conflict on a later disk must
	// not be discovered only after an earlier disk has acquired mappings.
	for slot := u32(0); slot < 64; slot++ {
		mut name := [64]char{}
		volume_path(slot, &name[0])
		view := C.open(&name[0], C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if view < 0 {
			if unsafe { C.errno == C.ENOENT } { continue }
			C.perror(c'vinix-volume: open mapping'); return false
		}
		mut status := Status{}
		valid := query_status(view, mut status)
		C.close(view)
		if !valid { return false }
		for i := u32(0); i < plan.count; i++ {
			row := plan.rows[i]
			if row.slot == slot {
				if !mapping_matches(unsafe { &status }, unsafe { &state.parent }, unsafe { &plan.rows[i] }) {
					plan_error(c'plan conflicts with an existing mapping'); return false
				}
				state.present[i] = true
			} else if status.flags & 8 != 0 && status.disk_id == state.parent.disk_id {
				if status.start > plan.key.bytes || status.bytes > plan.key.bytes - status.start {
					plan_error(c'existing mapping has incompatible geometry'); return false
				}
				if row.offset < status.start + status.bytes && status.start < row.offset + row.length {
					plan_error(c'plan overlaps an unlisted mapping'); return false
				}
			}
		}
	}
	return verify_restore_disk(fd, plan, unsafe { &state.parent })
}

@[direct_array_access]
fn apply_restore(fd i32, plan &Plan, state &RestoreState) i32 {
	for i := u32(0); i < plan.count; i++ {
		if state.present[i] { continue }
		if C.ioctl(fd, u64(0x56560001), &plan.rows[i]) != 0 {
			C.perror(c'vinix-volume: restore stopped; previously created mappings remain'); return 1
		}
	}
	C.printf(c'restored %u volume mappings\n', plan.count)
	return 0
}
