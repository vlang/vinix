// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <sys/ioctl.h>
fn C.ioctl(i32, u64, voidptr) i32

fn mount_flags_get(fd int) int {
	unsafe {
		bits := &i32(C.alloca(sizeof(i32)))
		*bits = -1
		check(C.ioctl(i32(fd), u64(0x80086601), bits) == 0, 440)
		return int(*bits)
	}
}

fn mount_flags_set(fd int, value int, expected int) {
	unsafe {
		bits := &i32(C.alloca(sizeof(i32)))
		*bits = i32(value)
		location := C.__errno_location()
		*location = 0
		result := C.ioctl(i32(fd), u64(0x40086602), bits)
		failure := *location
		if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
		C.printf(c'MOUNT INODE FLAGS RESULT: value=%x result=%d errno=%d expected=%d\n', i32(value), result, failure, i32(expected))
		C.fflush(nil)
		check(false, 441)
	}
}

fn mount_flags_checks(writable int, readonly int) {
	unsafe {
		mut identity := C.stat{}
		check(C.fstat(writable, &identity) == 0 && mount_flags_get(writable) == 0 && mount_flags_get(readonly) == 0, 442)
		for iteration in 0 .. 16 {
			for wanted in [0x20, 0x10, 0x30, 0]! {
				mount_flags_set(writable, wanted, 0)
				check(mount_flags_get(writable) == wanted && mount_flags_get(readonly) == wanted, 442)
				mut before := C.stat{}
				check(C.fstat(writable, &before) == 0, 442)
				// Both an actual change and an unchanged value need a writable
				// attachment. In particular, clearing protection cannot use RO.
				mount_flags_set(readonly, wanted ^ 0x30, C.EROFS)
				mount_flags_set(readonly, wanted, C.EROFS)
				check(mount_flags_get(writable) == wanted && mount_flags_get(readonly) == wanted, 442)
				timestamp_unchanged(writable, &before); timestamp_unchanged(readonly, &before)
			}
		}
		child := C.fork()
		check(child >= 0, 443)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 443)
			for wanted in [0x20, 0x10, 0x30, 0]! {
				mount_flags_set(writable, wanted, C.EPERM)
				// Existing Vinix capability admission precedes mount policy.
				mount_flags_set(readonly, wanted, C.EPERM)
				check(mount_flags_get(writable) == 0 && mount_flags_get(readonly) == 0, 443)
			}
			C._exit(0)
		}
		wait_child(child)
		mut after := C.stat{}
		check(C.fstat(writable, &after) == 0, 443)
		timestamp_identity(&after, &identity)
		if identity.st_mode & C.S_IFMT == C.S_IFREG {
			mut bytes := [8]u8{}
			check(C.read(writable, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 443)
		}
	}
}

fn mount_flags_pair(wdir int, rdir int, writable &char, readonly &char) {
	unsafe {
		wfd := C.openat(wdir, writable, C.O_RDONLY)
		rfd := C.openat(rdir, readonly, C.O_RDONLY)
		check(wfd >= 0 && rfd >= 0, 444)
		mount_flags_checks(wfd, rfd)
		check(C.close(wfd) == 0 && C.close(rfd) == 0, 444)
	}
}

fn mount_flags_directory_pair(wdir int, rdir int) {
	mount_flags_pair(wdir, rdir, c'marker', c'marker')
	mount_flags_pair(wdir, rdir, c'protected-dir', c'protected-dir')
}

// The worker's existing retired-namespace fixture creates the marker. Make
// its directory before retiring too; no descriptor/context address escapes.
fn mount_flags_retired_worker(argument voidptr) voidptr {
	unsafe {
		mut peer := &TruncatePeer(argument)
		truncate_retired_worker(peer)
		check(C.mkdirat(i32(peer.source_fd), c'protected-dir', u32(0o700)) == 0, 445)
		return nil
	}
}
fn C.mkdirat(i32, &char, u32) i32

fn mount_flags_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 446)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/ip-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 446)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, mount_flags_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 445)
			mount_flags_directory_pair(peer.source_fd, peer.alias_fd)
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 445)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 446)
		marker(&path[0])
		if kind == 3 {
			check(C.snprintf(&alias[0], 256, c'%s/file-alias', &base[0]) > 0, 446)
			marker(&alias[0])
			check(C.mount(&path[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 446)
			bind_policy_remount(&alias[0], true)
			mount_flags_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &path[0], &alias[0])
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_flags_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &alias[0], &path[0])
			return
		}
		check(C.snprintf(&path[0], 256, c'%s/protected-dir', &source[0]) > 0, 446)
		directory(&path[0])
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 446)
		if kind == 6 { bind_policy_remount(&source[0], true) } else { bind_policy_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 446) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 446)
		if kind == 7 {
			for name in [&char(c'marker'), &char(c'protected-dir')]! {
				wfd := C.openat(source_fd, name, C.O_RDONLY)
				rfd := C.openat(alias_fd, name, C.O_RDONLY)
				check(wfd >= 0 && rfd >= 0 && C.unshare(int(C.CLONE_NEWNS)) == 0, 446)
				mount_flags_checks(wfd, rfd)
				check(C.close(wfd) == 0 && C.close(rfd) == 0, 446)
			}
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 446)
			for name in [&char(c'marker'), &char(c'protected-dir')]! {
				check(C.snprintf(&path[0], 256, c'/%s', name) > 0, 446)
				mount_flags_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &path[0], name)
			}
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			for name in [&char(c'marker'), &char(c'protected-dir')]! {
				check(C.snprintf(&path[0], 256, c'/%s', name) > 0, 446)
				mount_flags_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), name, &path[0])
			}
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 446)
			mount_flags_directory_pair(source_fd, alias_fd)
		} else if kind == 6 {
			mount_flags_directory_pair(alias_fd, source_fd)
		} else {
			mount_flags_directory_pair(source_fd, alias_fd)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_flags_directory_pair(alias_fd, source_fd)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 446)
	}
}

fn mount_flags_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 447)
			if child == 0 { mount_flags_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT INODE FLAGS CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT INODE FLAGS: PASS')
		C.fflush(nil)
	}
}
