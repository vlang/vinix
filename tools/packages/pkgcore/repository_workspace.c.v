// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn repository_workspace_parent(directory string, name string) !int {
	fd := C.open(directory.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot capture ${name} workspace parent') }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_uid != u32(C.geteuid()) || info.st_mode & 0o022 != 0 {
		C.close(fd); return error('unsafe ${name} workspace parent')
	}
	return fd
}

// Only ENOENT means there is no abandoned workspace. Malformed aliases and
// directories refuse rather than being traversed or mistaken for absence.
fn capture_repository_workspace(parent int, name string) !(bool, StageTarget) {
	mut folder := C.stat{}
	mut info := C.stat{}
	if C.fstat(parent, unsafe { &folder }) != 0 { return error('cannot inspect ${name} workspace parent') }
	if C.fstatat(parent, name.str, unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) != 0 {
		if C.errno == C.ENOENT { return false, StageTarget{} }
		return error('cannot inspect ${name} workspace')
	}
	if info.st_mode & 0o170000 != 0o040000 || info.st_uid != u32(C.geteuid())
		|| info.st_mode & 0o022 != 0 || info.st_dev != folder.st_dev {
		return error('unsafe ${name} workspace; retain it for inspection and restore an ordinary administrator-owned directory')
	}
	return true, StageTarget{name: name, device: u64(info.st_dev), inode: u64(info.st_ino)}
}

fn create_enrollment_workspace(parent int) !StageTarget {
	found, abandoned := capture_repository_workspace(parent, 'enrollment')!
	if found { retire_stage(parent, abandoned)! }
	// Creating relative to the captured parent stops a replaced state path
	// from receiving the new workspace. EEXIST never adopts a replacement.
	if C.mkdirat(parent, c'enrollment', 0o700) != 0 {
		return error('cannot create private enrollment workspace; check permissions and inspect existing entries')
	}
	present, target := capture_repository_workspace(parent, 'enrollment')!
	if !present { return error('cannot capture new enrollment workspace') }
	return target
}

fn check_enrollment_workspace(directory string, parent int, target StageTarget) ! {
	mut folder := C.stat{}
	if C.fstat(parent, unsafe { &folder }) != 0
		|| !atomic_parent_matches(directory, u64(folder.st_dev), u64(folder.st_ino)) {
		return error('enrollment workspace parent changed; restore it before retrying')
	}
	present, observed := capture_repository_workspace(parent, target.name)!
	if !present || observed != target {
		return error('enrollment workspace identity changed; retain it for inspection')
	}
}
