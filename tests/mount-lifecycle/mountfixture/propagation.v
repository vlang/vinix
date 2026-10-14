// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn propagation_call(path &char, flags usize) int {
	// Propagation ignores source, filesystem and data, including wxallowed.
	return unsafe { C.mount(c'ignored', path, c'ignored', flags, c'wxallowed') }
}

fn propagation_refusal(kind int, path &char, flags usize, expected int) {
	if expected != C.EPERM {
		fd := C.open(path, C.O_PATH)
		check(fd >= 0 && C.close(fd) == 0, 230)
	}
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := propagation_call(path, flags)
	failure := unsafe { *location }
	if result != -1 || failure != expected {
		unsafe { C.printf(c'MOUNT PROPAGATION RESULT: case=%d flags=%lu result=%d errno=%d expected=%d\n',
			kind, flags, result, failure, expected) }
		C.fflush(unsafe { nil })
	}
	check(result == -1 && failure == expected, 231 + kind)
}

fn propagation_denied(kind int, path &char, flags usize) {
	child := C.fork()
	check(child >= 0, 236)
	if child == 0 {
		unsafe { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 236) }
		propagation_refusal(kind, path, flags, C.EPERM)
		C._exit(0)
	}
	wait_child(child)
}

fn propagation_modes(path &char) {
	unsafe {
		for mode in [usize(C.MS_PRIVATE), usize(C.MS_SLAVE), usize(C.MS_SHARED), usize(C.MS_UNBINDABLE)]! {
			for extra in [usize(0), usize(C.MS_REC), usize(C.MS_SILENT), usize(C.MS_REC | C.MS_SILENT)]! {
				check(propagation_call(path, mode | extra) == 0, 237)
			}
		}
		check(propagation_call(path, usize(C.MS_PRIVATE)) == 0, 237)
	}
}

fn propagation_flags(root &char) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(root, &before) == 0, 238)
		propagation_denied(0, root, usize(C.MS_PRIVATE | C.MS_SHARED))
		modes := [usize(C.MS_PRIVATE), usize(C.MS_SLAVE), usize(C.MS_SHARED), usize(C.MS_UNBINDABLE)]!
		for iteration in 0 .. 200 {
			for mask in 1 .. 16 {
				if mask & (mask - 1) == 0 { continue }
				mut flags := usize(0)
				for index in 0 .. 4 { if mask & (1 << index) != 0 { flags |= modes[index] } }
				propagation_refusal(0, root, flags | usize(C.MS_REC | C.MS_SILENT), C.EINVAL)
			}
			for extra in [usize(C.MS_RDONLY), usize(C.MS_NOSUID), usize(C.MS_NODEV), usize(C.MS_NOEXEC),
				usize(C.MS_NOATIME), usize(C.MS_RELATIME), usize(C.MS_MOVE), usize(1 << 30)]! {
				propagation_refusal(0, root, usize(C.MS_PRIVATE) | extra, C.EINVAL)
			}
			check(same(root, &before), 238)
		}
		propagation_modes(root)
		check(same(root, &before), 238)
	}
}

fn propagation_children(kind int, root &char, fd int, detached bool) {
	unsafe {
		mut inbox := [256]char{}
		mut file := [256]char{}
		check(C.snprintf(&inbox[0], 256, c'%s/inbox', root) > 0
			&& C.snprintf(&file[0], 256, c'%s/marker', root) > 0, 239)
		mut before := C.stat{}
		check(C.stat(root, &before) == 0 && contents(&file[0]), 239)
		propagation_denied(kind, &inbox[0], usize(C.MS_PRIVATE))
		for iteration in 0 .. 200 {
			propagation_refusal(kind, &inbox[0], usize(C.MS_PRIVATE | C.MS_REC), C.EINVAL)
			propagation_refusal(kind, &file[0], usize(C.MS_SHARED), C.EINVAL)
			check(same(root, &before) && contents(&file[0]), 239)
		}
		check(C.chdir(root) == 0, 239)
		propagation_refusal(kind, c'inbox', usize(C.MS_PRIVATE), C.EINVAL)
		check(C.chdir(c'/') == 0, 239)
		if detached {
			propagation_denied(kind, root, usize(C.MS_PRIVATE))
			for iteration in 0 .. 200 {
				propagation_refusal(kind, root, usize(C.MS_PRIVATE | C.MS_REC), C.EINVAL)
				check(same(root, &before), 239)
			}
		} else { propagation_modes(root) }
		if fd >= 0 { identity_read(fd) }
	}
}

fn propagation_bind(root &char, base &char) {
	unsafe {
		mut source := [256]char{}
		mut alias := [256]char{}
		check(C.snprintf(&source[0], 256, c'%s/inbox', root) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', base) > 0, 240)
		directory(&alias[0])
		mut before := C.stat{}
		mut source_before := C.stat{}
		check(C.stat(&alias[0], &before) == 0 && C.stat(&source[0], &source_before) == 0, 240)
		for mode in [usize(C.MS_PRIVATE), usize(C.MS_SHARED), usize(C.MS_SLAVE),
			usize(C.MS_UNBINDABLE), usize(C.MS_PRIVATE | C.MS_SHARED)]! {
			// Bind dispatch precedes propagation; these flags do not turn it into
			// a propagation request or change the source to an unbindable mount.
			check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND) | mode, nil) == 0
				&& same(&alias[0], &source_before), 240)
			propagation_modes(&alias[0])
			propagation_refusal(4, &source[0], usize(C.MS_PRIVATE), C.EINVAL)
			check(C.umount2(&alias[0], 0) == 0 && same(&alias[0], &before), 240)
		}
		check(C.snprintf(&source[0], 256, c'%s/marker', root) > 0
			&& C.snprintf(&alias[0], 256, c'%s/file-alias', base) > 0, 240)
		marker(&alias[0])
		check(C.stat(&source[0], &source_before) == 0
			&& C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND | C.MS_PRIVATE), nil) == 0
			&& same(&alias[0], &source_before), 240)
		propagation_modes(&alias[0])
		propagation_refusal(4, &source[0], usize(C.MS_PRIVATE), C.EINVAL)
		check(C.umount2(&alias[0], 0) == 0 && C.unlink(&alias[0]) == 0, 240)
	}
}

fn propagation_case(kind int) {
	unsafe {
		mut base := [256]char{}
		mut live := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/pr-%d', kind) > 0, 241)
		directory(&base[0])
		check(C.snprintf(&live[0], 256, c'%s/live', &base[0]) > 0, 241)
		directory(&live[0])
		mut ready := [2]i32{}
		mut stop := [2]i32{}
		mut child := -1
		if kind == 3 {
			check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 241)
			child = C.fork()
			check(child >= 0, 241)
		}
		mut held := -1
		if kind != 3 || child == 0 {
			if child == 0 {
				check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0
					&& C.unshare(int(C.CLONE_NEWNS)) == 0, 241)
			}
			check(C.mount(c'tmpfs', &live[0], c'tmpfs', 0, nil) == 0
				&& C.snprintf(&path[0], 256, c'%s/marker', &live[0]) > 0, 241)
			marker(&path[0])
			check(C.snprintf(&path[0], 256, c'%s/inbox', &live[0]) > 0, 241)
			directory(&path[0])
			if kind in [2, 3] {
				check(C.mount(c'none', &live[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 241)
				held = C.open(&live[0], C.O_PATH | C.O_DIRECTORY)
				check(held >= 0, 241)
			}
			if child == 0 {
				number := i32(held)
				mut token := u8(0)
				check(C.write(int(ready[1]), &number, sizeof(i32)) == sizeof(i32)
					&& C.read(int(stop[0]), &token, 1) == 1 && token == 1, 241)
				identity_read(held)
				check(C.umount2(&live[0], int(C.MNT_DETACH)) == 0 && C.close(held) == 0, 241)
				C._exit(0)
			}
			if kind == 2 {
				check(C.umount2(&live[0], int(C.MNT_DETACH)) == 0
					&& C.mount(c'tmpfs', &live[0], c'tmpfs', 0, nil) == 0, 241)
			}
		} else {
			mut number := i32(-1)
			check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0
				&& C.read(int(ready[0]), &number, sizeof(i32)) == sizeof(i32) && number >= 0
				&& C.snprintf(&path[0], 256, c'/proc/%d/fd/%d', child, number) > 0, 241)
			held = C.open(&path[0], C.O_PATH | C.O_DIRECTORY)
			check(held >= 0, 241)
		}
		if kind == 0 { propagation_flags(&live[0]) }
		if kind == 1 { propagation_children(kind, &live[0], -1, false) }
		if kind in [2, 3] {
			check(C.snprintf(&path[0], 256, c'/proc/self/fd/%d', held) > 0, 241)
			if kind == 2 {
				propagation_denied(kind, &path[0], usize(C.MS_PRIVATE))
				propagation_refusal(kind, &path[0], usize(C.MS_PRIVATE | C.MS_REC), C.EINVAL)
			}
			propagation_children(kind, &path[0], held, kind == 2)
		}
		if kind == 4 { propagation_bind(&live[0], &base[0]) }
		if child > 0 {
			token := u8(1)
			check(C.write(int(stop[1]), &token, 1) == 1 && C.close(int(stop[1])) == 0
				&& C.close(int(ready[0])) == 0, 241)
			wait_child(child)
			propagation_children(kind, &path[0], held, true)
		}
		if held >= 0 { check(C.close(held) == 0, 241) }
		if kind != 3 { check(C.umount2(&live[0], 0) == 0, 241) }
	}
}

fn propagation_cases(selected int) {
	for kind in 0 .. 5 {
		if selected >= 0 && kind != selected { continue }
		propagation_case(kind)
		unsafe { C.printf(c'MOUNT PROPAGATION CASE: %d PASS\n', kind) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT PROPAGATION VALIDATION: PASS')
	C.fflush(unsafe { nil })
}
