// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

// 0/1/3 attach tmpfs, a bind, or devpts onto a held directory. Operation 2
// instead binds that directory as a source onto a live local destination.
fn admission_operation(operation int, path &char, local &char, destination &char) int {
	unsafe {
		if operation == 0 { return C.mount(c'tmpfs', path, c'tmpfs', 0, nil) }
		if operation == 1 { return C.mount(local, path, nil, usize(C.MS_BIND), nil) }
		if operation == 2 { return C.mount(path, destination, nil, usize(C.MS_BIND), nil) }
		return C.mount(c'devpts', path, c'devpts', 0, c'newinstance')
	}
}

fn admission_refusal(kind int, path &char, local &char, destination &char, expected int) {
	if expected != C.EPERM {
		// Path lookup succeeds even when attaching to this mount is forbidden.
		fd := C.open(path, C.O_PATH | C.O_DIRECTORY)
		check(fd >= 0 && C.close(fd) == 0, 200)
	}
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := admission_operation(kind % 4, path, local, destination)
	failure := unsafe { *C.__errno_location() }
	if result != -1 || failure != expected {
		unsafe { C.printf(c'MOUNT ADMISSION RESULT: case=%d result=%d errno=%d expected=%d\n', kind, result, failure, expected) }
		C.fflush(unsafe { nil })
	}
	check(result == -1 && failure == expected, 210 + kind)
}

fn admission_denied_account(kind int, path &char, local &char, destination &char) {
	child := C.fork()
	check(child >= 0, 201)
	if child == 0 {
		unsafe { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 201) }
		admission_refusal(kind, path, local, destination, C.EPERM)
		C._exit(0)
	}
	wait_child(child)
}

fn admission_repeated(kind int, fd int, path &char, live &char, local &char, destination &char) {
	unsafe {
		mut target_before := C.stat{}
		mut live_before := C.stat{}
		mut local_before := C.stat{}
		mut destination_before := C.stat{}
		check(C.stat(path, &target_before) == 0 && C.stat(live, &live_before) == 0
			&& C.stat(local, &local_before) == 0 && C.stat(destination, &destination_before) == 0, 202)
		mut marker_path := [256]char{}
		check(C.snprintf(&marker_path[0], 256, c'%s/marker', local) > 0, 202)
		expected := if kind % 4 == 2 || kind >= 4 { C.EINVAL } else { C.ENOENT }
		admission_denied_account(kind, path, local, destination)
		for iteration in 0 .. 200 {
			admission_refusal(kind, path, local, destination, expected)
			check(same(path, &target_before) && same(live, &live_before) && same(local, &local_before)
				&& same(destination, &destination_before) && contents(&marker_path[0]), 202)
			identity_read(fd)
		}
		mut root_path := [256]char{}
		check(C.snprintf(&root_path[0], 256, c'/proc/self/fd/%d', fd) > 0 && C.chdir(&root_path[0]) == 0, 203)
		admission_refusal(kind, c'inbox', local, destination, expected)
		check(C.chdir(c'/') == 0, 203)
	}
}

// Live local fds can name a source or destination, including ordinary files.
// A fresh namespace repeats these operations with fds opened in that namespace.
fn admission_local(local &char, destination &char) {
	unsafe {
		mut source_path := [256]char{}
		mut target_path := [256]char{}
		mut marker_path := [256]char{}
		mut file_path := [256]char{}
		mut alias_path := [256]char{}
		mut before := C.stat{}
		check(C.stat(destination, &before) == 0, 204)
		source := C.open(local, C.O_PATH | C.O_DIRECTORY)
		target := C.open(destination, C.O_PATH | C.O_DIRECTORY)
		check(source >= 0 && target >= 0
			&& C.snprintf(&source_path[0], 256, c'/proc/self/fd/%d', source) > 0
			&& C.snprintf(&target_path[0], 256, c'/proc/self/fd/%d', target) > 0
			&& C.snprintf(&marker_path[0], 256, c'%s/marker', destination) > 0, 204)
		mut source_before := C.stat{}
		check(C.fstat(source, &source_before) == 0
			&& C.mount(&source_path[0], &target_path[0], nil, usize(C.MS_BIND), nil) == 0
			&& same(destination, &source_before) && contents(&marker_path[0])
			&& C.umount2(destination, 0) == 0 && same(destination, &before), 204)
		check(C.mount(c'tmpfs', &target_path[0], c'tmpfs', 0, nil) == 0 && !same(destination, &before), 205)
		marker(&marker_path[0])
		check(contents(&marker_path[0]) && C.umount2(destination, 0) == 0 && same(destination, &before), 205)
		check(C.mount(c'devpts', &target_path[0], c'devpts', 0, c'newinstance') == 0
			&& !same(destination, &before), 206)
		pts := C.open(destination, C.O_PATH | C.O_DIRECTORY)
		check(pts >= 0 && C.close(pts) == 0 && C.umount2(destination, 0) == 0
			&& same(destination, &before) && C.close(source) == 0 && C.close(target) == 0, 206)
		check(C.snprintf(&file_path[0], 256, c'%s/marker', local) > 0
			&& C.snprintf(&alias_path[0], 256, c'%s/alias', destination) > 0, 207)
		marker(&alias_path[0])
		file := C.open(&file_path[0], C.O_PATH)
		alias := C.open(&alias_path[0], C.O_PATH)
		mut file_before := C.stat{}
		check(file >= 0 && alias >= 0 && C.fstat(file, &file_before) == 0
			&& C.snprintf(&source_path[0], 256, c'/proc/self/fd/%d', file) > 0
			&& C.snprintf(&target_path[0], 256, c'/proc/self/fd/%d', alias) > 0
			&& C.mount(&source_path[0], &target_path[0], nil, usize(C.MS_BIND), nil) == 0
			&& same(&alias_path[0], &file_before) && contents(&alias_path[0])
			&& C.umount2(&alias_path[0], 0) == 0 && C.close(file) == 0 && C.close(alias) == 0, 207)
		check(C.unlink(&alias_path[0]) == 0, 207)
	}
}

fn admission_local_namespaces(local &char, destination &char) {
	admission_local(local, destination)
	unsafe {
		mut before := C.stat{}
		check(C.stat(destination, &before) == 0, 208)
		child := C.fork()
		check(child >= 0, 208)
		if child == 0 {
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 208)
			admission_local(local, destination)
			C._exit(0)
		}
		wait_child(child)
		check(same(destination, &before), 208)
	}
}

fn admission_case(kind int) {
	unsafe {
		mut base := [256]char{}
		mut live := [256]char{}
		mut local := [256]char{}
		mut destination := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/ad-%d', kind) > 0, 209)
		directory(&base[0])
		check(C.snprintf(&live[0], 256, c'%s/live', &base[0]) > 0
			&& C.snprintf(&local[0], 256, c'%s/local', &base[0]) > 0
			&& C.snprintf(&destination[0], 256, c'%s/destination', &base[0]) > 0, 209)
		directory(&live[0]); directory(&local[0]); directory(&destination[0])
		check(C.mount(c'tmpfs', &local[0], c'tmpfs', 0, nil) == 0
			&& C.snprintf(&path[0], 256, c'%s/marker', &local[0]) > 0, 209)
		marker(&path[0])
		mut ready := [2]i32{}
		mut stop := [2]i32{}
		mut child := -1
		if kind >= 4 {
			check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 209)
			child = C.fork()
			check(child >= 0, 209)
		}
		mut held := -1
		if kind < 4 || child == 0 {
			if child == 0 {
				check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0
					&& C.unshare(int(C.CLONE_NEWNS)) == 0, 209)
			}
			check(C.mount(c'tmpfs', &live[0], c'tmpfs', 0, nil) == 0
				&& C.snprintf(&path[0], 256, c'%s/marker', &live[0]) > 0, 209)
			marker(&path[0])
			check(C.snprintf(&path[0], 256, c'%s/inbox', &live[0]) > 0, 209)
			directory(&path[0])
			check(C.mount(c'none', &live[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 209)
			held = C.open(&live[0], C.O_PATH | C.O_DIRECTORY)
			check(held >= 0, 209)
			identity_read(held)
			if child == 0 {
				number := i32(held)
				mut token := u8(0)
				check(C.write(int(ready[1]), &number, sizeof(i32)) == sizeof(i32)
					&& C.read(int(stop[0]), &token, 1) == 1 && token == 1, 209)
				identity_read(held)
				check(C.close(held) == 0 && C.umount2(&live[0], int(C.MNT_DETACH)) == 0
					&& C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0, 209)
				C._exit(0)
			}
			check(C.umount2(&live[0], int(C.MNT_DETACH)) == 0
				&& C.mount(c'tmpfs', &live[0], c'tmpfs', 0, nil) == 0, 209)
		} else {
			mut number := i32(-1)
			check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0
				&& C.read(int(ready[0]), &number, sizeof(i32)) == sizeof(i32) && number >= 0
				&& C.snprintf(&path[0], 256, c'/proc/%d/fd/%d', child, number) > 0, 209)
			held = C.open(&path[0], C.O_PATH | C.O_DIRECTORY)
			check(held >= 0, 209)
		}
		check(C.snprintf(&path[0], 256, c'/proc/self/fd/%d/inbox', held) > 0, 209)
		admission_repeated(kind, held, &path[0], &live[0], &local[0], &destination[0])
		if child > 0 {
			token := u8(1)
			check(C.write(int(stop[1]), &token, 1) == 1 && C.close(int(stop[1])) == 0
				&& C.close(int(ready[0])) == 0, 209)
			wait_child(child)
			admission_refusal(kind, &path[0], &local[0], &destination[0],
				if kind % 4 == 2 { C.EINVAL } else { C.ENOENT })
			identity_read(held)
		}
		check(C.close(held) == 0, 209)
		admission_local_namespaces(&local[0], &destination[0])
		check(C.umount2(&local[0], 0) == 0, 209)
		if kind < 4 { check(C.umount2(&live[0], 0) == 0, 209) }
	}
}

fn admission_cases(selected int) {
	for kind in 0 .. 8 {
		if selected >= 0 && kind != selected { continue }
		admission_case(kind)
		unsafe { C.printf(c'MOUNT ADMISSION CASE: %d PASS\n', kind) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT ADMISSION: PASS')
	C.fflush(unsafe { nil })
}
