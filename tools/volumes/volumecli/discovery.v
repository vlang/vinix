// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

#include <dirent.h>

@[typedef]
struct C.DIR {}
struct C.dirent { d_name [256]char }
fn C.fdopendir(i32) &C.DIR
fn C.readdir(&C.DIR) &C.dirent
fn C.closedir(&C.DIR) i32
fn C.fstatat(i32, &char, &C.stat, i32) i32
fn C.S_ISBLK(u32) i32

// Nonmatching geometry cannot be the requested disk. Unreadable candidates
// with matching geometry fail the scan: uniqueness could not be established.
fn candidate_disk(fd i32, expected &DiskKey, mut key DiskKey, mut status Status) i32 {
	if C.ioctl(fd, u64(0x56560004), &status) != 0 {
		if unsafe { C.errno == C.ENOTTY } { return 0 }
		C.perror(c'vinix-volume: discovery status'); return -1
	}
	if status.version != 1 || status.reserved != 0 {
		plan_error(c'unsupported discovery status version'); return -1
	}
	if status.flags & (8 | 16) != 0 || status.start != 0
		|| status.bytes != expected.bytes || status.sector != expected.sector { return 0 }
	if status.flags & 2 != 0 { plan_error(c'discovery candidate is offline'); return -1 }
	mut bytes := [8192]u8{}
	mut count := i64(-1)
	for {
		count = C.pread(fd, &bytes[0], usize(expected.sector * 2), 0)
		if count >= 0 || unsafe { C.errno != C.EINTR } { break }
	}
	if count != i64(expected.sector * 2) { plan_error(c'cannot read discovery candidate identity'); return -1 }
	if !identify_disk(&bytes[0], int(count), status.bytes, status.sector, mut key) { return 0 }
	return if key_matches(expected, &key) { 1 } else { 0 }
}

@[direct_array_access]
fn discover_disk(plan &Plan, directory &char, writable bool, name &char) i32 {
	if !plan_valid(plan) { plan_error(c'invalid discovery plan'); return -1 }
	mut selected_status := Status{}
	return discover_disk_key(&plan.key, directory, writable, name, mut selected_status)
}

@[direct_array_access]
fn discover_disk_key(expected &DiskKey, directory &char, writable bool, name &char, mut selected_status Status) i32 {
	if !key_valid(expected) { plan_error(c'invalid discovery identity'); return -1 }
	dir_fd := C.open(directory, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if dir_fd < 0 { C.perror(c'vinix-volume: open device directory'); return -1 }
	stream := C.fdopendir(dir_fd)
	if stream == unsafe { nil } { C.close(dir_fd); C.perror(c'vinix-volume: read device directory'); return -1 }
	defer { C.closedir(stream) } // fdopendir owns dir_fd.
	mut selected := i32(-1)
	mut selected_id := u64(0)
	mut returned := false
	defer { if selected >= 0 && !returned { C.close(selected) } }
	mut entries := 0
	mut key := unsafe { &DiskKey(C.alloca(sizeof(DiskKey))) }
	unsafe { *key = DiskKey{} }
	for {
		unsafe { C.errno = 0 }
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if unsafe { C.errno != 0 } { C.perror(c'vinix-volume: device enumeration'); return -1 }
			break
		}
		child := unsafe { &entry.d_name[0] }
		if C.strcmp(child, c'.') == 0 || C.strcmp(child, c'..') == 0 { continue }
		entries++
		if entries > 4096 { plan_error(c'device directory exceeds discovery limit'); return -1 }
		mut info := C.stat{}
		if C.fstatat(dir_fd, child, &info, C.AT_SYMLINK_NOFOLLOW) != 0 {
			C.perror(c'vinix-volume: discovery entry changed'); return -1
		}
		if C.S_ISBLK(info.st_mode) == 0 { continue }
		mut fd := C.openat(dir_fd, child, C.O_RDONLY | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 { C.perror(c'vinix-volume: open discovery candidate'); return -1 }
		mut opened := C.stat{}
		if C.fstat(fd, &opened) != 0 || C.S_ISBLK(opened.st_mode) == 0 {
			C.close(fd); plan_error(c'discovery entry changed type'); return -1
		}
		mut status := Status{}
		result := candidate_disk(fd, expected, mut key, mut status)
		if result != 1 { C.close(fd); if result < 0 { return -1 }; continue }
		if selected >= 0 {
			C.close(fd)
			// Physical aliases share disk_id; clones with distinct backing
			// disks are ambiguous even when their table identity is identical.
			if selected_id != status.disk_id { plan_error(c'multiple physical disks match the plan'); return -1 }
			continue
		}
		if writable {
			write_fd := C.openat(dir_fd, child, C.O_RDWR | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW)
			if write_fd < 0 { C.close(fd); C.perror(c'vinix-volume: open discovered disk for restore'); return -1 }
			mut again := Status{}
			valid := C.fstat(write_fd, &opened) == 0 && C.S_ISBLK(opened.st_mode) != 0
				&& candidate_disk(write_fd, expected, mut key, mut again) == 1 && again.disk_id == status.disk_id
			C.close(fd)
			if !valid { C.close(write_fd); plan_error(c'discovered disk changed before writable open'); return -1 }
			fd = write_fd
			status = again
		}
		selected = fd
		selected_id = status.disk_id
		selected_status = status
		C.snprintf(name, 256, c'%s', child)
	}
	if selected < 0 { plan_error(c'no physical disk matches the plan'); return -1 }
	returned = true
	return selected
}

fn automatic_loaded(plan &Plan, restore bool) i32 {
	mut name := [256]char{}
	fd := discover_disk(plan, c'/dev', restore && plan_writable(plan), &name[0])
	if fd < 0 { return 1 }
	defer { C.close(fd) }
	C.printf(c'vinix-volume: matched /dev/%s\n', &name[0])
	return if restore { restore_loaded(fd, plan) } else { 0 }
}

fn automatic_plan(path &char, restore bool) i32 {
	mut plan := unsafe { &Plan(C.alloca(sizeof(Plan))) }
	unsafe { *plan = Plan{} }
	if !load_plan(path, mut plan) { return 1 }
	return automatic_loaded(plan, restore)
}

// Legacy plan, bundle and volumes.d form one preflighted set. Absence is normal.
// Configuration directories and every enabled file must be trusted.
fn boot_restore() i32 {
	etc := C.open(c'/etc', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if etc < 0 {
		if unsafe { C.errno == C.ENOENT } { return 0 }
		C.perror(c'vinix-volume: boot configuration directory'); return 1
	}
	defer { C.close(etc) }
	directory := C.openat(etc, c'vinix', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if directory < 0 {
		if unsafe { C.errno == C.ENOENT } { return 0 }
		C.perror(c'vinix-volume: boot plan directory'); return 1
	}
	defer { C.close(directory) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	if !load_boot_plans(directory, mut set) { return 1 }
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { erase_key(work, sizeof(VolumeSealFiles)) }
	loaded := load_boot_volume(etc, directory, mut *work)
	if loaded < 0 { return 1 }
	if set.count == 0 && loaded == 0 { return 0 }
	if !trusted_directory(etc, c'boot configuration directory must be owned by root and not writable by group or others')
		|| !trusted_directory(directory, c'boot plan directory must be owned by root and not writable by group or others') { return 1 }
	if loaded == 1 && !boot_volume_set_compatible(set, work) { return plan_error(c'boot encrypted mapping conflicts with the saved plain set') }
	if restore_plan_set(set) != 0 { return 1 }
	if loaded == 0 { return 0 }
	if !boot_volume_directories(etc, directory) { return 1 }
	return open_loaded_volume_seal_auto(mut *work, false)
}
