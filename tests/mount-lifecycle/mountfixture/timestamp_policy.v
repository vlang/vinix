// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <time.h>
#include <sys/time.h>
#include <utime.h>
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.timeval { tv_sec i64 tv_usec i64 }
struct C.utimbuf { actime i64 modtime i64 }
fn C.clock_gettime(i32, &C.timespec) i32
fn C.utime(&char, &C.utimbuf) i32
fn C.utimes(&char, &C.timeval) i32
fn C.futimesat(i32, &char, &C.timeval) i32

fn timestamp_equal(a C.timespec, b C.timespec) bool { return a.tv_sec == b.tv_sec && a.tv_nsec == b.tv_nsec }
fn timestamp_le(a C.timespec, b C.timespec) bool { return a.tv_sec < b.tv_sec || (a.tv_sec == b.tv_sec && a.tv_nsec <= b.tv_nsec) }
fn timestamp_identity(a &C.stat, b &C.stat) {
	check(a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
		&& a.st_mode == b.st_mode && a.st_uid == b.st_uid && a.st_gid == b.st_gid, 400)
}
fn timestamp_unchanged(fd int, before &C.stat) {
	mut after := C.stat{}
	check(C.fstat(fd, &after) == 0, 400)
	timestamp_identity(&after, before)
	check(timestamp_equal(after.st_atim, before.st_atim) && timestamp_equal(after.st_mtim, before.st_mtim)
		&& timestamp_equal(after.st_ctim, before.st_ctim), 400)
}
fn timestamp_call(operation int, dirfd int, path &char, legacy &char, fd int, values &C.timespec, form int) int {
	unsafe {
		match operation {
			4 {
				old := C.utimbuf{actime: values[0].tv_sec, modtime: values[1].tv_sec}
				return int(C.utime(legacy, &old))
			}
			5, 6 {
				old := [C.timeval{tv_sec: values[0].tv_sec, tv_usec: values[0].tv_nsec / 1000},
					C.timeval{tv_sec: values[1].tv_sec, tv_usec: values[1].tv_nsec / 1000}]!
				return if operation == 5 { int(C.utimes(legacy, &old[0])) } else { int(C.futimesat(i32(dirfd), path, &old[0])) }
			}
			else {
				where := if operation == 1 { &char(nil) } else if operation == 2 { &char(c'') } else { path }
				handle := if operation in [1, 2] { fd } else { dirfd }
				flags := if operation == 2 { int(C.AT_EMPTY_PATH) } else if operation == 3 { int(C.AT_SYMLINK_NOFOLLOW) } else { 0 }
				return int(C.syscall(int(C.SYS_utimensat), i32(handle), where, if form == 1 { voidptr(nil) } else { voidptr(values) }, i32(flags)))
			}
		}
	}
}
fn timestamp_result(operation int, dirfd int, path &char, legacy &char, fd int, values &C.timespec, form int, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := timestamp_call(operation, dirfd, path, legacy, fd, values, form)
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT TIMES RESULT: operation=%d form=%d result=%d errno=%d expected=%d\n', operation, form, result, failure, expected) }
	C.fflush(unsafe { nil })
	check(false, 401)
}
fn timestamp_legacy_path(dirfd int, path &char, output &char) {
	unsafe {
		if dirfd == int(C.AT_FDCWD) { check(C.snprintf(output, 512, c'%s', path) > 0, 402) }
		else { check(C.snprintf(output, 512, c'/proc/self/fd/%d/%s', i32(dirfd), path) > 0, 402) }
	}
}

fn timestamp_pair(wdir int, rdir int, writable &char, readonly &char, wlink &char, rlink &char, has_link bool) {
	unsafe {
		wfd := C.openat(wdir, writable, C.O_RDONLY)
		rfd := C.openat(rdir, readonly, C.O_RDONLY)
		link_fd := if has_link { C.openat(wdir, wlink, C.O_PATH | C.O_NOFOLLOW) } else { -1 }
		mut legacy_w := [512]char{}
		mut legacy_r := [512]char{}
		timestamp_legacy_path(wdir, writable, &legacy_w[0]); timestamp_legacy_path(rdir, readonly, &legacy_r[0])
		check(wfd >= 0 && rfd >= 0 && (!has_link || link_fd >= 0), 402)
		for iteration in 0 .. 200 {
			for operation in 0 .. 7 {
				if operation == 3 && !has_link { continue }
				for form in 0 .. if operation < 4 { 4 } else { 1 } {
					mut before := C.stat{}
					mut link_before := C.stat{}
					check(C.fstat(wfd, &before) == 0 && (!has_link || C.fstat(link_fd, &link_before) == 0), 402)
					mut values := [C.timespec{tv_sec: 1234000000 + iteration * 10 + operation, tv_nsec: 123456000},
						C.timespec{tv_sec: 1235000000 + iteration * 10 + operation, tv_nsec: 654321000}]!
					if operation == 4 { values[0].tv_nsec = 0; values[1].tv_nsec = 0 }
					if form == 2 { values[0].tv_nsec = i64(C.UTIME_NOW); values[1].tv_nsec = i64(C.UTIME_NOW) }
					if form == 3 { values[1].tv_nsec = i64(C.UTIME_OMIT) }
					rpath := if operation == 3 { rlink } else { readonly }
					wpath := if operation == 3 { wlink } else { writable }
					timestamp_result(operation, rdir, rpath, &legacy_r[0], rfd, &values[0], form, C.EROFS)
					timestamp_unchanged(wfd, &before); timestamp_unchanged(rfd, &before)
					if has_link { timestamp_unchanged(link_fd, &link_before) }
					mut earliest := C.timespec{}
					mut latest := C.timespec{}
					check(C.clock_gettime(i32(C.CLOCK_REALTIME), &earliest) == 0, 403)
					timestamp_result(operation, wdir, wpath, &legacy_w[0], wfd, &values[0], form, 0)
					check(C.clock_gettime(i32(C.CLOCK_REALTIME), &latest) == 0, 403)
					mut after := C.stat{}
					changed_fd := if operation == 3 { link_fd } else { wfd }
					old := if operation == 3 { &link_before } else { &before }
					check(C.fstat(changed_fd, &after) == 0, 403)
					timestamp_identity(&after, old)
					if form in [1, 2] {
						// Linux inode timestamps use a coarse real-time clock.
						// Allow its rounding below the precise observation.
						earliest.tv_sec--
						check(timestamp_le(earliest, after.st_atim) && timestamp_le(after.st_atim, latest)
							&& timestamp_le(earliest, after.st_mtim) && timestamp_le(after.st_mtim, latest), 403)
					} else {
						check(timestamp_equal(after.st_atim, values[0]) && timestamp_equal(after.st_mtim,
							if form == 3 { old.st_mtim } else { values[1] }), 403)
					}
					if operation == 3 { timestamp_unchanged(wfd, &before) }
					else if has_link { timestamp_unchanged(link_fd, &link_before) }
				}
			}
		}
		mut before := C.stat{}
		mut link_before := C.stat{}
		check(C.fstat(wfd, &before) == 0 && (!has_link || C.fstat(link_fd, &link_before) == 0), 404)
		child := C.fork()
		check(child >= 0, 404)
		if child == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 404)
			values := [C.timespec{tv_sec: 1234000011}, C.timespec{tv_sec: 1235000011}]!
			for operation in 0 .. 7 {
				if operation == 3 && !has_link { continue }
				timestamp_result(operation, wdir, if operation == 3 { wlink } else { writable }, &legacy_w[0], wfd, &values[0], 0, C.EPERM)
				timestamp_result(operation, rdir, if operation == 3 { rlink } else { readonly }, &legacy_r[0], rfd, &values[0], 0, C.EROFS)
				if operation < 3 {
					timestamp_result(operation, wdir, writable, &legacy_w[0], wfd, &values[0], 1, C.EACCES)
					timestamp_result(operation, rdir, readonly, &legacy_r[0], rfd, &values[0], 1, C.EROFS)
				}
			}
			C._exit(0)
		}
		wait_child(child)
		timestamp_unchanged(wfd, &before); timestamp_unchanged(rfd, &before)
		if has_link { timestamp_unchanged(link_fd, &link_before) }
		mut bytes := [8]u8{}
		check(C.read(wfd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0
			&& C.close(wfd) == 0 && C.close(rfd) == 0, 405)
		if has_link { check(C.close(link_fd) == 0, 405) }
	}
}

fn timestamp_cwd_pair(wdir int, rdir int) {
	unsafe {
		for iteration in 0 .. 200 {
			mut before := C.stat{}
			check(C.fstat(wdir, &before) == 0 && C.fchdir(rdir) == 0, 408)
			values := [C.timespec{tv_sec: 1234000000 + iteration, tv_nsec: 111111111}, C.timespec{tv_sec: 1235000000 + iteration, tv_nsec: 222222222}]!
			timestamp_result(2, int(C.AT_FDCWD), c'', c'', int(C.AT_FDCWD), &values[0], 0, C.EROFS)
			timestamp_unchanged(wdir, &before)
			check(C.fchdir(wdir) == 0, 408)
			timestamp_result(2, int(C.AT_FDCWD), c'', c'', int(C.AT_FDCWD), &values[0], 0, 0)
			mut after := C.stat{}
			check(C.fstat(wdir, &after) == 0 && timestamp_equal(after.st_atim, values[0]) && timestamp_equal(after.st_mtim, values[1]), 408)
			timestamp_identity(&after, &before)
		}
	}
}

fn timestamp_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 406)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/tp-%d', kind) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 406)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 406)
			timestamp_pair(peer.source_fd, peer.alias_fd, c'marker', c'marker', c'', c'', false)
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 406)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0
			&& C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 406)
		marker(&path[0])
		if kind == 3 {
			check(C.snprintf(&alias[0], 256, c'%s/file-alias', &base[0]) > 0, 406)
			marker(&alias[0])
			check(C.mount(&path[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 406)
			bind_policy_remount(&alias[0], true)
			timestamp_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &path[0], &alias[0], c'', c'', false)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			timestamp_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), &alias[0], &path[0], c'', c'', false)
			return
		}
		check(C.snprintf(&path[0], 256, c'%s/link', &source[0]) > 0 && C.symlink(c'marker', &path[0]) == 0
			&& C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 406)
		if kind == 6 { bind_policy_remount(&source[0], true) }
		else { bind_policy_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 406) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 406)
		if kind == 7 {
			timestamp_cwd_pair(source_fd, alias_fd)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			timestamp_cwd_pair(alias_fd, source_fd)
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 406)
			timestamp_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/marker', c'marker', c'/link', c'link', true)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			timestamp_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'marker', c'/marker', c'link', c'/link', true)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 406)
			timestamp_pair(source_fd, alias_fd, c'marker', c'marker', c'link', c'link', true)
		} else if kind == 6 {
			timestamp_pair(alias_fd, source_fd, c'marker', c'marker', c'link', c'link', true)
		} else {
			timestamp_pair(source_fd, alias_fd, c'marker', c'marker', c'link', c'link', true)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			timestamp_pair(alias_fd, source_fd, c'marker', c'marker', c'link', c'link', true)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 406)
	}
}

fn timestamp_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 407)
			if child == 0 { timestamp_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT TIMES CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT TIMES: PASS')
		C.fflush(nil)
	}
}
