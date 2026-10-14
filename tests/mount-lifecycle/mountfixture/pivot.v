// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn pivot_call(root &char, old &char) isize {
	return C.syscall(int(C.SYS_pivot_root), root, old)
}

fn pivot_refusal(kind int, root &char, old &char, expected int) {
	if expected != C.EPERM {
		first := C.open(root, C.O_PATH | C.O_DIRECTORY)
		second := C.open(old, C.O_PATH | C.O_DIRECTORY)
		check(first >= 0 && second >= 0 && C.close(first) == 0 && C.close(second) == 0, 250)
	}
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := pivot_call(root, old)
	failure := unsafe { *location }
	if result != -1 || failure != expected {
		unsafe { C.printf(c'MOUNT PIVOT RESULT: case=%d result=%ld errno=%d expected=%d\n', kind, result, failure, expected) }
		C.fflush(unsafe { nil })
	}
	check(result == -1 && failure == expected, 251 + kind)
}

fn pivot_denied(kind int, root &char, old &char) {
	child := C.fork()
	check(child >= 0, 258)
	if child == 0 {
		unsafe { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 258) }
		pivot_refusal(kind, root, old, C.EPERM)
		C._exit(0)
	}
	wait_child(child)
}

fn pivot_tree(path &char) {
	unsafe {
		check(C.mount(c'tmpfs', path, c'tmpfs', 0, nil) == 0, 259)
		mut name := [256]char{}
		check(C.snprintf(&name[0], 256, c'%s/marker', path) > 0, 259)
		marker(&name[0])
		for child in [&char(c'old'), &char(c'inbox')]! {
			check(C.snprintf(&name[0], 256, c'%s/%s', path, child) > 0, 259)
			directory(&name[0])
		}
	}
}

// A recursive bind and chroot give Linux's initramfs a pivotable root.
// Each caller is already in its own mount namespace; the parent's root stays.
fn pivot_prepare(kind int, variant int) {
	unsafe {
		mut alias := [256]char{}
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0
			&& C.snprintf(&alias[0], 256, c'/tmp/mount-lifecycle/pv-root-%d-%d', kind, variant) > 0, 260)
		directory(&alias[0])
		check(C.mount(c'/', &alias[0], nil, usize(C.MS_BIND | C.MS_REC), nil) == 0
			&& C.chroot(&alias[0]) == 0 && C.chdir(c'/') == 0, 260)
	}
}

fn pivot_repeated(kind int, root &char, old &char, live &char, marker_path &char, held int) {
	unsafe {
		mut before_root := C.stat{}
		mut before_new := C.stat{}
		mut before_old := C.stat{}
		mut before_live := C.stat{}
		check(C.stat(c'/', &before_root) == 0 && C.stat(root, &before_new) == 0
			&& C.stat(old, &before_old) == 0 && C.stat(live, &before_live) == 0, 261)
		pivot_denied(kind, root, old)
		for iteration in 0 .. 200 {
			pivot_refusal(kind, root, old, if kind == 5 { C.EBUSY } else if kind == 1 { C.ENOENT } else { C.EINVAL })
			check(same(c'/', &before_root) && same(c'.', &before_root) && same(root, &before_new)
				&& same(old, &before_old) && same(live, &before_live) && contents(marker_path), 261)
			if held >= 0 { identity_read(held) }
		}
	}
}

fn pivot_positive(root &char, old &char, old_relative &char, nested bool) {
	unsafe {
		mut previous := C.stat{}
		mut next := C.stat{}
		mut parent := C.stat{}
		mut path := [256]char{}
		check(C.stat(c'/', &previous) == 0 && C.stat(root, &next) == 0
			&& C.snprintf(&path[0], 256, c'%s/..', old) > 0 && C.stat(&path[0], &parent) == 0, 262)
		result := pivot_call(root, old)
		if result != 0 {
			C.printf(c'MOUNT PIVOT POSITIVE RESULT: result=%ld errno=%d root=%s old=%s\n', result, *C.__errno_location(), root, old)
			C.fflush(nil)
		}
		check(result == 0, 262)
		check(same(c'/', &next) && same(c'.', &next) && same(c'/..', &next) && contents(c'/marker'), 262)
		prefix := if nested { &char(c'/inbox/deep') } else { &char(c'/old') }
		check(same(prefix, &previous) && C.snprintf(&path[0], 256, c'%s%s', prefix, old_relative) > 0
			&& contents(&path[0]) && C.chdir(prefix) == 0 && same(c'..', &parent) && C.chdir(c'/') == 0, 262)
	}
}

fn pivot_case(kind int, variant int) {
	unsafe {
		pivot_prepare(kind, variant)
		mut base := [256]char{}
		mut live := [256]char{}
		mut new_path := [256]char{}
		mut old_path := [256]char{}
		mut marker_path := [256]char{}
		mut relative := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/pv-%d-%d', kind, variant) > 0, 263)
		directory(&base[0])
		check(C.snprintf(&relative[0], 256, c'%s/old-marker', &base[0]) > 0, 263)
		marker(&relative[0])
		check(C.snprintf(&live[0], 256, c'%s/new', &base[0]) > 0, 263)
		directory(&live[0])
		root_fd := C.open(c'/', C.O_PATH | C.O_DIRECTORY)
		check(root_fd >= 0, 263)
		if kind == 4 {
			check(C.snprintf(&new_path[0], 256, c'%s/sandbox', &base[0]) > 0, 263)
			directory(&new_path[0])
			check(C.chroot(&new_path[0]) == 0 && C.chdir(c'/') == 0, 263)
			directory(c'/new')
			check(C.snprintf(&live[0], 256, c'/new') > 0, 263)
		}
		if kind == 6 && variant == 2 {
			check(C.snprintf(&new_path[0], 256, c'%s/source', &base[0]) > 0, 263)
			directory(&new_path[0])
			check(C.mount(&new_path[0], &live[0], nil, usize(C.MS_BIND), nil) == 0
				&& C.snprintf(&marker_path[0], 256, c'%s/marker', &live[0]) > 0, 263)
			marker(&marker_path[0])
			check(C.snprintf(&old_path[0], 256, c'%s/old', &live[0]) > 0, 263)
			directory(&old_path[0])
		} else { pivot_tree(&live[0]) }
		check(C.snprintf(&new_path[0], 256, c'%s', &live[0]) > 0
			&& C.snprintf(&old_path[0], 256, c'%s/old', &live[0]) > 0
			&& C.snprintf(&marker_path[0], 256, c'%s/marker', &live[0]) > 0, 263)
		mut held := -1
		mut creator := -1
		mut ready := [2]i32{}
		mut stop := [2]i32{}
		if kind == 0 {
			check(C.snprintf(&new_path[0], 256, c'%s/child', &live[0]) > 0, 263)
			directory(&new_path[0])
			check(C.snprintf(&old_path[0], 256, c'%s/old', &new_path[0]) > 0, 263)
			directory(&old_path[0])
		} else if kind == 1 {
			check(C.mount(c'none', &live[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 263)
			held = C.open(&live[0], C.O_PATH | C.O_DIRECTORY)
			check(held >= 0 && C.umount2(&live[0], int(C.MNT_DETACH)) == 0, 263)
			pivot_tree(&live[0])
			check(C.snprintf(&new_path[0], 256, c'/proc/self/fd/%d', held) > 0
				&& C.snprintf(&old_path[0], 256, c'%s/old', &new_path[0]) > 0, 263)
		} else if kind == 2 {
			check(C.snprintf(&new_path[0], 256, c'%s/foreign', &base[0]) > 0, 263)
			directory(&new_path[0])
			check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 263)
			creator = C.fork()
			check(creator >= 0, 263)
			if creator == 0 {
				check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0
					&& C.unshare(int(C.CLONE_NEWNS)) == 0, 263)
				pivot_tree(&new_path[0])
				check(C.mount(c'none', &new_path[0], nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 263)
				fd := C.open(&new_path[0], C.O_PATH | C.O_DIRECTORY)
				number := i32(fd)
				mut token := u8(0)
				check(fd >= 0 && C.write(int(ready[1]), &number, sizeof(i32)) == sizeof(i32)
					&& C.read(int(stop[0]), &token, 1) == 1 && token == 1, 263)
				check(C.umount2(&new_path[0], int(C.MNT_DETACH)) == 0 && C.close(fd) == 0, 263)
				C._exit(0)
			}
			mut number := i32(-1)
			check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0
				&& C.read(int(ready[0]), &number, sizeof(i32)) == sizeof(i32) && number >= 0
				&& C.snprintf(&old_path[0], 256, c'/proc/%d/fd/%d', creator, number) > 0, 263)
			held = C.open(&old_path[0], C.O_PATH | C.O_DIRECTORY)
			check(held >= 0 && C.snprintf(&new_path[0], 256, c'/proc/self/fd/%d', held) > 0
				&& C.snprintf(&old_path[0], 256, c'%s/old', &new_path[0]) > 0, 263)
		} else if kind == 3 {
			check(C.snprintf(&old_path[0], 256, c'%s/alias', &base[0]) > 0, 263)
			directory(&old_path[0])
			check(C.mount(&live[0], &old_path[0], nil, usize(C.MS_BIND), nil) == 0
				&& C.snprintf(&old_path[0], 256, c'%s/alias/old', &base[0]) > 0, 263)
		} else if kind == 5 {
			check(C.snprintf(&old_path[0], 256, c'%s', &base[0]) > 0, 263)
		}
		if kind < 6 {
			pivot_repeated(kind, &new_path[0], &old_path[0], &live[0], &marker_path[0], held)
			if creator > 0 {
				token := u8(1)
				check(C.write(int(stop[1]), &token, 1) == 1 && C.close(int(stop[1])) == 0
					&& C.close(int(ready[0])) == 0, 263)
				wait_child(creator)
				pivot_refusal(kind, &new_path[0], &old_path[0], C.ENOENT)
				identity_read(held)
			}
			if held >= 0 { check(C.close(held) == 0, 263) }
			if kind == 4 {
				check(C.fchdir(root_fd) == 0 && C.chroot(c'.') == 0 && C.chdir(c'/') == 0
					&& C.snprintf(&live[0], 256, c'%s/sandbox/new', &base[0]) > 0, 263)
			}
		}
		check(C.close(root_fd) == 0 && C.snprintf(&old_path[0], 256, c'%s/old', &live[0]) > 0, 263)
		if kind == 6 && variant == 1 {
			check(C.snprintf(&old_path[0], 256, c'%s/inbox', &live[0]) > 0
				&& C.mount(c'tmpfs', &old_path[0], c'tmpfs', 0, nil) == 0
				&& C.snprintf(&old_path[0], 256, c'%s/inbox/deep', &live[0]) > 0, 263)
			directory(&old_path[0])
		}
		pivot_positive(&live[0], &old_path[0], &relative[0], kind == 6 && variant == 1)
	}
}

fn pivot_cases(selected int) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(c'/', &before) == 0, 264)
		for kind in 0 .. 7 {
			if selected >= 0 && kind != selected { continue }
			for variant in 0 .. if kind == 6 { 3 } else { 1 } {
				child := C.fork()
				check(child >= 0, 264)
				if child == 0 { pivot_case(kind, variant); C._exit(0) }
				wait_child(child)
				check(same(c'/', &before), 264)
			}
			C.printf(c'MOUNT PIVOT CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT PIVOT ADMISSION: PASS')
		C.fflush(nil)
	}
}
