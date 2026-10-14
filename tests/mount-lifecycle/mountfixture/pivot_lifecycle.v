// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn life_result(kind int, stage &char, result int, expected int) {
	if result == expected { return }
	unsafe { C.printf(c'MOUNT PIVOT LIFE RESULT: case=%d stage=%s result=%d errno=%d expected=%d\n',
		kind, stage, result, *C.__errno_location(), expected) }
	C.fflush(unsafe { nil })
	check(false, 270 + kind)
}

fn life_fd_policy(kind int, fd int, prefix &char) {
	unsafe {
		check(C.mount(c'none', prefix, nil, usize(C.MS_REMOUNT | C.MS_BIND), nil) == 0, 275)
		writable := C.openat(fd, c'marker', C.O_WRONLY)
		if writable < 0 { life_result(kind, c'held-old-root-policy', writable, 0) }
		check(C.close(writable) == 0, 275)
		check(C.mount(c'none', prefix, nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 275)
		check(C.openat(fd, c'marker', C.O_WRONLY) == -1 && *C.__errno_location() == C.EROFS, 275)
	}
}

fn life_source_uncovered(kind int, fd int, before &C.stat) {
	child := C.openat(fd, c'new', C.O_PATH | C.O_DIRECTORY)
	mut after := C.stat{}
	check(child >= 0 && C.fstat(child, &after) == 0 && C.close(child) == 0, 276)
	life_result(kind, c'new-root-extracted', if after.st_dev == before.st_dev && after.st_ino == before.st_ino { 0 } else { -1 }, 0)
}

fn life_parent(kind int, fd int, before &C.stat) {
	unsafe {
		check(C.fchdir(fd) == 0, 277)
		life_result(kind, c'held-old-root-parent', if same(c'..', before) { 0 } else { -1 }, 0)
		check(C.chdir(c'/') == 0, 277)
	}
}

fn life_denied(prefix &char) {
	child := C.fork()
	check(child >= 0, 278)
	if child == 0 {
		unsafe {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 278)
			check(C.umount2(prefix, int(C.MNT_DETACH)) == -1 && *C.__errno_location() == C.EPERM, 278)
		}
		C._exit(0)
	}
	wait_child(child)
}

fn life_mount_refusal(fd int) {
	unsafe {
		mut path := [256]char{}
		check(C.snprintf(&path[0], 256, c'/proc/self/fd/%d/inbox', fd) > 0, 279)
		lookup := C.open(&path[0], C.O_PATH | C.O_DIRECTORY)
		check(lookup >= 0 && C.close(lookup) == 0, 279)
		check(C.mount(c'tmpfs', &path[0], c'tmpfs', 0, nil) == -1 && *C.__errno_location() == C.ENOENT, 279)
		identity_read(fd)
	}
}

fn life_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 280)
		mut base := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/pl-%d', kind) > 0, 280)
		directory(&base[0])
		check(C.snprintf(&path[0], 256, c'%s/root', &base[0]) > 0, 280)
		directory(&path[0])
		pivot_tree(&path[0])
		mut proc_path := [256]char{}
		check(C.snprintf(&proc_path[0], 256, c'%s/proc', &path[0]) > 0, 280)
		directory(&proc_path[0])
		check(C.mount(c'proc', &proc_path[0], c'proc', 0, nil) == 0
			&& C.chroot(&path[0]) == 0 && C.chdir(c'/') == 0, 280)
		directory(c'/new')
		covered := C.open(c'/new', C.O_PATH | C.O_DIRECTORY)
		mut source_before := C.stat{}
		check(covered >= 0 && C.fstat(covered, &source_before) == 0 && C.close(covered) == 0, 280)
		if kind == 2 {
			directory(c'/source')
			check(C.mount(c'/source', c'/new', nil, usize(C.MS_BIND), nil) == 0, 280)
			marker(c'/new/marker')
			directory(c'/new/old'); directory(c'/new/inbox')
		} else { pivot_tree(c'/new') }
		for name in [&char(c'proc'), &char(c'next'), &char(c'dst')]! {
			check(C.snprintf(&path[0], 256, c'/new/%s', name) > 0, 280)
			directory(&path[0])
		}
		check(C.mount(c'proc', c'/new/proc', c'proc', 0, nil) == 0, 280)
		directory(c'/retained')
		pivot_tree(c'/retained')
		check(C.mount(c'none', c'/retained', nil, usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 280)
		old_child := C.open(c'/retained', C.O_PATH | C.O_DIRECTORY)
		old := C.open(c'/', C.O_PATH | C.O_DIRECTORY)
		check(old >= 0 && old_child >= 0 && C.mount(c'none', c'/', nil,
			usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 280)
		identity_read(old); identity_read(old_child)
		mut parent := C.stat{}
		mut next := C.stat{}
		mut old_path := [256]char{}
		check(C.snprintf(&old_path[0], 256, c'/new/old') > 0, 280)
		if kind == 1 {
			check(C.mount(c'tmpfs', c'/new/inbox', c'tmpfs', 0, nil) == 0, 280)
			directory(c'/new/inbox/deep')
			check(C.snprintf(&old_path[0], 256, c'/new/inbox/deep') > 0
				&& C.stat(c'/new/inbox', &parent) == 0, 280)
		} else { check(C.stat(c'/new', &parent) == 0, 280) }
		check(C.stat(c'/new', &next) == 0 && pivot_call(c'/new', &old_path[0]) == 0
			&& same(c'/', &next) && same(c'.', &next), 280)
		prefix := if kind == 1 { &char(c'/inbox/deep') } else { &char(c'/old') }
		if kind == 0 { life_fd_policy(kind, old, prefix) }
		if kind == 1 { life_parent(kind, old, &parent) }
		if kind == 2 { life_source_uncovered(kind, old, &source_before) }
		if kind != 3 {
			life_fd_policy(kind, old, prefix)
			life_source_uncovered(kind, old, &source_before)
			life_parent(kind, old, &parent)
		}
		if kind == 0 {
			pivot_tree(c'/next')
			directory(c'/next/proc'); directory(c'/next/dst')
			check(C.mount(c'proc', c'/next/proc', c'proc', 0, nil) == 0 && pivot_call(c'/next', c'/next/old') == 0, 281)
			check(contents(c'/marker') && contents(c'/old/marker') && contents(c'/old/old/marker'), 281)
			life_fd_policy(kind, old, c'/old/old')
			check(C.stat(c'/old', &parent) == 0, 281)
			life_parent(kind, old, &parent)
		}
		life_denied(prefix)
		check(C.umount2(prefix, int(C.MNT_DETACH)) == 0 && contents(c'/marker'), 282)
		life_result(kind, c'new-root-after-detach', C.mount(c'tmpfs', c'/dst', c'tmpfs', 0, nil), 0)
		marker(c'/dst/marker')
		check(contents(c'/dst/marker') && C.umount2(c'/dst', 0) == 0, 282)
		for iteration in 0 .. 200 { life_mount_refusal(old); life_mount_refusal(old_child) }
		check(C.close(old) == 0 && C.close(old_child) == 0, 282)
	}
}

fn pivot_lifecycle_cases(selected int) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(c'/', &before) == 0, 283)
		for kind in 0 .. 4 {
			if selected >= 0 && kind != selected { continue }
			child := C.fork()
			check(child >= 0, 283)
			if child == 0 { life_case(kind); C._exit(0) }
			wait_child(child)
			check(same(c'/', &before), 283)
			C.printf(c'MOUNT PIVOT LIFE CASE: %d PASS\n', kind)
			C.fflush(nil)
		}
		C.puts(c'MOUNT PIVOT LIFECYCLE: PASS')
		C.fflush(nil)
	}
}
