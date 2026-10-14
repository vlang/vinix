// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn C.pipe(&i32) int

// Operations 0/1 alter an existing attachment, 2 moves a source descriptor,
// and 3 moves the live local source onto a descriptor's child directory.
fn identity_operation(operation int, path &char, local &char, destination &char) int {
	unsafe {
		if operation == 0 { return C.umount2(path, 0) }
		if operation == 1 { return C.mount(c'none', path, nil, usize(C.MS_REMOUNT | C.MS_BIND), nil) }
		if operation == 2 { return C.mount(path, destination, nil, usize(C.MS_MOVE), nil) }
		return C.mount(local, path, nil, usize(C.MS_MOVE), nil)
	}
}

fn identity_refusal(kind int, operation int, path &char, local &char, destination &char, expected int) {
	if operation == 3 && expected != C.EPERM {
		// ENOENT must describe the missing namespace attachment, not a missing
		// target directory: ordinary lookup through the held description works.
		fd := C.open(path, C.O_PATH | C.O_DIRECTORY)
		check(fd >= 0 && C.close(fd) == 0, 109)
	}
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := identity_operation(operation, path, local, destination)
	failure := unsafe { *C.__errno_location() }
	if result != -1 || failure != expected {
		unsafe { C.printf(c'MOUNT IDENTITY RESULT: case=%d operation=%d result=%d errno=%d expected=%d\n',
			kind, operation, result, failure, expected) }
		C.fflush(unsafe { nil })
	}
	check(result == -1 && failure == expected, 110 + kind)
}

fn identity_read(fd int) {
	unsafe {
		readfd := C.openat(fd, c'marker', C.O_RDONLY)
		mut bytes := [8]u8{}
		check(readfd >= 0 && C.read(readfd, &bytes[0], 8) == 8
			&& C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0 && C.close(readfd) == 0, 101)
		result := C.openat(fd, c'forbidden', C.O_CREAT | C.O_WRONLY, u32(0o600))
		failure := *C.__errno_location()
		if result != -1 || failure != C.EROFS {
			C.printf(c'MOUNT IDENTITY READONLY: fd=%d result=%d errno=%d expected=%d\n', fd, result, failure, C.EROFS)
			C.fflush(nil)
		}
		check(result == -1 && failure == C.EROFS, 102)
		// Refusal must precede file creation and truncation, not just writes on
		// an opened description. The existing marker must stay intact too.
		check(C.openat(fd, c'forbidden', C.O_RDONLY) == -1 && *C.__errno_location() == C.ENOENT, 102)
		for flags in [int(C.O_WRONLY), int(C.O_RDWR), int(C.O_RDONLY | C.O_TRUNC)]! {
			opened := C.openat(fd, c'marker', flags)
			failure_open := *C.__errno_location()
			if opened != -1 || failure_open != C.EROFS {
				C.printf(c'MOUNT IDENTITY OPEN: fd=%d flags=%d result=%d errno=%d expected=%d\n',
					fd, flags, opened, failure_open, C.EROFS)
				C.fflush(nil)
			}
			check(opened == -1 && failure_open == C.EROFS, 102)
		}
	}
}

fn identity_denied_account(kind int, operation int, path &char, local &char, destination &char) {
	child := C.fork()
	check(child >= 0, 103)
	if child == 0 {
		unsafe { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 103) }
		identity_refusal(kind, operation, path, local, destination, C.EPERM)
		C._exit(0)
	}
	wait_child(child)
}

fn identity_local_operations(local &char, destination &char) {
	unsafe {
		fd := C.open(local, C.O_PATH | C.O_DIRECTORY)
		mut path := [256]char{}
		check(fd >= 0 && C.snprintf(&path[0], 256, c'/proc/self/fd/%d', fd) > 0, 104)
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0
			&& C.mount(c'none', &path[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 104)
		identity_read(fd)
		check(C.mount(c'none', &path[0], nil, usize(C.MS_REMOUNT | C.MS_BIND), nil) == 0, 104)
		writefd := C.openat(fd, c'allowed', C.O_CREAT | C.O_WRONLY, u32(0o600))
		check(writefd >= 0 && C.write(writefd, c'MOUNT-OK', 8) == 8 && C.close(writefd) == 0, 104)
		check(C.mount(&path[0], destination, nil, usize(C.MS_MOVE), nil) == 0
			&& same(destination, &before), 105)
		// A descriptor tracks the moved attachment and remains a valid target.
		check(C.close(fd) == 0 && C.umount2(destination, 0) == 0, 105)
	}
}

fn detached_identity(kind int) {
	unsafe {
		mut base := [256]char{}
		mut live := [256]char{}
		mut local := [256]char{}
		mut destination := [256]char{}
		mut marker_path := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/id-%d', kind) > 0, 100)
		directory(&base[0])
		check(C.snprintf(&live[0], 256, c'%s/live', &base[0]) > 0
			&& C.snprintf(&local[0], 256, c'%s/local', &base[0]) > 0
			&& C.snprintf(&destination[0], 256, c'%s/destination', &base[0]) > 0, 100)
		directory(&live[0]); directory(&local[0]); directory(&destination[0])
		check(C.mount(c'tmpfs', &live[0], c'tmpfs', 0, nil) == 0, 100)
		check(C.snprintf(&marker_path[0], 256, c'%s/marker', &live[0]) > 0, 100)
		marker(&marker_path[0])
		check(C.snprintf(&path[0], 256, c'%s/inbox', &live[0]) > 0, 100)
		directory(&path[0])
		old := C.open(&live[0], C.O_PATH | C.O_DIRECTORY)
		check(old >= 0 && C.mount(c'none', &live[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 100)
		identity_read(old)
		check(C.umount2(&live[0], int(C.MNT_DETACH)) == 0
			&& C.mount(c'tmpfs', &live[0], c'tmpfs', 0, nil) == 0, 100)
		marker(&marker_path[0])
		check(C.mount(c'tmpfs', &local[0], c'tmpfs', 0, nil) == 0, 100)
		check(C.snprintf(&path[0], 256, c'%s/marker', &local[0]) > 0, 100)
		marker(&path[0])
		mut replacement := C.stat{}
		mut local_before := C.stat{}
		check(C.stat(&live[0], &replacement) == 0 && C.stat(&local[0], &local_before) == 0, 100)
		operation := if kind == 2 { 3 } else { kind }
		expected := if operation == 3 { C.ENOENT } else { C.EINVAL }
		check(C.snprintf(&path[0], 256, if operation == 3 { c'/proc/self/fd/%d/inbox' } else { c'/proc/self/fd/%d' }, old) > 0, 100)
		identity_denied_account(kind, operation, &path[0], &local[0], &destination[0])
		for iteration in 0 .. 200 {
			identity_refusal(kind, operation, &path[0], &local[0], &destination[0], expected)
			identity_read(old)
			check(same(&live[0], &replacement) && same(&local[0], &local_before)
				&& contents(&marker_path[0]), 106)
		}
		check(C.snprintf(&path[0], 256, c'/proc/self/fd/%d', old) > 0
			&& C.chdir(&path[0]) == 0, 106)
		identity_refusal(kind, operation, if operation == 3 { c'inbox' } else { c'.' },
			&local[0], &destination[0], expected)
		// Moving the detached description itself must also be refused.
		identity_refusal(kind, 2, &path[0], &local[0], &destination[0], C.EINVAL)
		check(C.chdir(c'/') == 0 && C.close(old) == 0, 106)
		identity_local_operations(&local[0], &destination[0])
		check(C.umount2(&live[0], 0) == 0, 106)
	}
}

fn foreign_identity(kind int) {
	unsafe {
		mut base := [256]char{}
		mut foreign := [256]char{}
		mut local := [256]char{}
		mut destination := [256]char{}
		mut marker_path := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/id-%d', kind) > 0, 100)
		directory(&base[0])
		check(C.snprintf(&foreign[0], 256, c'%s/foreign', &base[0]) > 0
			&& C.snprintf(&local[0], 256, c'%s/local', &base[0]) > 0
			&& C.snprintf(&destination[0], 256, c'%s/destination', &base[0]) > 0, 100)
		directory(&foreign[0]); directory(&local[0]); directory(&destination[0])
		check(C.mount(c'tmpfs', &local[0], c'tmpfs', 0, nil) == 0, 100)
		check(C.snprintf(&marker_path[0], 256, c'%s/marker', &local[0]) > 0, 100)
		marker(&marker_path[0])
		mut local_before := C.stat{}
		check(C.stat(&local[0], &local_before) == 0, 100)
		mut ready := [2]i32{}
		mut stop := [2]i32{}
		check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 107)
		child := C.fork()
		check(child >= 0, 107)
		if child == 0 {
			check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0
				&& C.unshare(int(C.CLONE_NEWNS)) == 0, 107)
			check(C.mount(c'tmpfs', &foreign[0], c'tmpfs', 0, nil) == 0
				&& C.snprintf(&path[0], 256, c'%s/marker', &foreign[0]) > 0, 107)
			marker(&path[0])
			check(C.snprintf(&path[0], 256, c'%s/inbox', &foreign[0]) > 0, 107)
			directory(&path[0])
			check(C.mount(c'none', &foreign[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 107)
			mut fd := i32(C.open(&foreign[0], C.O_PATH | C.O_DIRECTORY))
			check(fd >= 0 && C.write(int(ready[1]), &fd, sizeof(i32)) == sizeof(i32), 107)
			mut token := u8(0)
			check(C.read(int(stop[0]), &token, 1) == 1 && token == 1, 107)
			identity_read(int(fd))
			check(C.close(int(fd)) == 0 && C.umount2(&foreign[0], int(C.MNT_DETACH)) == 0
				&& C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0, 107)
			C._exit(0)
		}
		check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0, 107)
		mut number := i32(-1)
		check(C.read(int(ready[0]), &number, sizeof(i32)) == sizeof(i32) && number >= 0
			&& C.snprintf(&path[0], 256, c'/proc/%d/fd/%d', child, number) > 0, 107)
		fd := C.open(&path[0], C.O_PATH | C.O_DIRECTORY)
		check(fd >= 0 && C.snprintf(&path[0], 256, if kind == 6 { c'/proc/self/fd/%d/inbox' } else { c'/proc/self/fd/%d' }, fd) > 0, 107)
		operation := kind - 3
		expected := C.EINVAL
		identity_denied_account(kind, operation, &path[0], &local[0], &destination[0])
		for iteration in 0 .. 200 {
			identity_refusal(kind, operation, &path[0], &local[0], &destination[0], expected)
			identity_read(fd)
			check(same(&local[0], &local_before) && contents(&marker_path[0]), 108)
		}
		mut root_path := [256]char{}
		check(C.snprintf(&root_path[0], 256, c'/proc/self/fd/%d', fd) > 0 && C.chdir(&root_path[0]) == 0, 108)
		identity_refusal(kind, operation, if operation == 3 { c'inbox' } else { c'.' },
			&local[0], &destination[0], expected)
		check(C.chdir(c'/') == 0, 108)
		token := u8(1)
		check(C.write(int(stop[1]), &token, 1) == 1 && C.close(int(stop[1])) == 0
			&& C.close(int(ready[0])) == 0, 108)
		wait_child(child)
		// The description still reads the old data and retains read-only policy
		// after the mount namespace itself has retired.
		identity_refusal(kind, operation, &path[0], &local[0], &destination[0],
			if operation == 3 { C.ENOENT } else { expected })
		identity_read(fd)
		check(C.close(fd) == 0, 108)
		identity_local_operations(&local[0], &destination[0])
	}
}

fn identity_cases(selected int) {
	for kind in 0 .. 7 {
		if selected >= 0 && kind != selected { continue }
		if kind < 3 { detached_identity(kind) } else { foreign_identity(kind) }
		unsafe { C.printf(c'MOUNT IDENTITY CASE: %d PASS\n', kind) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT IDENTITIES: PASS')
	C.fflush(unsafe { nil })
}
