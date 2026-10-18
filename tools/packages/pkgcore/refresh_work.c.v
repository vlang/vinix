// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn refresh_parent(directory string) !int {
	fd := C.open(directory.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot capture refresh workspace parent') }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_uid != u32(C.geteuid()) || info.st_mode & 0o022 != 0 {
		C.close(fd); return error('unsafe refresh workspace parent')
	}
	return fd
}

// Only ENOENT means there is no abandoned workspace. Malformed aliases and
// directories refuse rather than being traversed or mistaken for absence.
fn capture_refresh_work(parent int) !(bool, StageTarget) {
	mut folder := C.stat{}
	mut info := C.stat{}
	if C.fstat(parent, unsafe { &folder }) != 0 { return error('cannot inspect refresh workspace parent') }
	if C.fstatat(parent, c'refresh', unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) != 0 {
		if C.errno == C.ENOENT { return false, StageTarget{} }
		return error('cannot inspect refresh workspace')
	}
	if info.st_mode & 0o170000 != 0o040000 || info.st_uid != u32(C.geteuid())
		|| info.st_mode & 0o022 != 0 || info.st_dev != folder.st_dev {
		return error('unsafe refresh workspace; retain it for inspection and restore an ordinary administrator-owned directory')
	}
	return true, StageTarget{name: 'refresh', device: u64(info.st_dev), inode: u64(info.st_ino)}
}
