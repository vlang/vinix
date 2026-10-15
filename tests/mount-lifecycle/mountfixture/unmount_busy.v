// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn busy_mount(path &char) {
	unsafe { check(C.mount(c'tmpfs', path, c'tmpfs', 0, nil) == 0, 2800) }
}

fn busy_preserved(parent &char, child &char) {
	unsafe {
		mut before_parent := C.stat{}
		mut before_child := C.stat{}
		mut parent_marker := [256]char{}
		mut child_marker := [256]char{}
		check(C.stat(parent, &before_parent) == 0 && C.stat(child, &before_child) == 0
			&& C.snprintf(&parent_marker[0], 256, c'%s/marker', parent) > 0
			&& C.snprintf(&child_marker[0], 256, c'%s/marker', child) > 0, 2801)
		for _ in 0 .. 200 {
			refused_unmount(parent, 0, C.EBUSY, 2802)
			check(same(parent, &before_parent) && same(child, &before_child)
				&& contents(&parent_marker[0]) && contents(&child_marker[0]), 2803)
		}
	}
}

fn busy_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 2804)
		busy_mount(c'/tmp/mount-lifecycle/busy')
		directory(c'/tmp/mount-lifecycle/busy/a')
		directory(c'/tmp/mount-lifecycle/busy/b')
		directory(c'/tmp/mount-lifecycle/busy/source')
		busy_mount(c'/tmp/mount-lifecycle/busy/a')
		marker(c'/tmp/mount-lifecycle/busy/a/marker')
		directory(c'/tmp/mount-lifecycle/busy/a/child')
		if kind == 3 {
			// The sibling bind shares an inode, but does not own a's child.
			check(C.mount(c'/tmp/mount-lifecycle/busy/a', c'/tmp/mount-lifecycle/busy/b', nil,
				usize(C.MS_BIND), nil) == 0, 2805)
		}
		if kind == 4 {
			marker(c'/tmp/mount-lifecycle/busy/source/marker')
			check(C.mount(c'/tmp/mount-lifecycle/busy/source', c'/tmp/mount-lifecycle/busy/a/child', nil,
				usize(C.MS_BIND), nil) == 0, 2805)
		} else if kind != 5 {
			busy_mount(c'/tmp/mount-lifecycle/busy/a/child')
			marker(c'/tmp/mount-lifecycle/busy/a/child/marker')
		}
		if kind == 0 {
			child := C.fork()
			check(child >= 0, 2806)
			if child == 0 {
				check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 2806)
				refused_unmount(c'/tmp/mount-lifecycle/busy/a', 0, C.EPERM, 2807)
				C._exit(0)
			}
			wait_child(child)
		}
		if kind == 1 || kind == 2 || kind == 7 {
			directory(c'/tmp/mount-lifecycle/busy/a/child/grand')
			busy_mount(c'/tmp/mount-lifecycle/busy/a/child/grand')
			marker(c'/tmp/mount-lifecycle/busy/a/child/grand/marker')
		}
		if kind == 2 {
			busy_mount(c'/tmp/mount-lifecycle/busy/b')
			marker(c'/tmp/mount-lifecycle/busy/b/marker')
			directory(c'/tmp/mount-lifecycle/busy/b/child')
			check(C.mount(c'/tmp/mount-lifecycle/busy/a/child', c'/tmp/mount-lifecycle/busy/b/child', nil,
				usize(C.MS_MOVE), nil) == 0 && C.umount2(c'/tmp/mount-lifecycle/busy/a', 0) == 0, 2808)
			busy_preserved(c'/tmp/mount-lifecycle/busy/b', c'/tmp/mount-lifecycle/busy/b/child')
			busy_preserved(c'/tmp/mount-lifecycle/busy/b/child', c'/tmp/mount-lifecycle/busy/b/child/grand')
			check(C.umount2(c'/tmp/mount-lifecycle/busy/b/child/grand', 0) == 0
				&& C.umount2(c'/tmp/mount-lifecycle/busy/b/child', 0) == 0
				&& C.umount2(c'/tmp/mount-lifecycle/busy/b', 0) == 0, 2809)
		} else if kind == 5 {
			// Only the copied namespace gets a child mount. Its parent survives
			// the original namespace removing its own attachment of the same id.
			mut ready := [2]i32{}
			mut stop := [2]i32{}
			check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 2810)
			child := C.fork()
			check(child >= 0, 2810)
			if child == 0 {
				check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0
					&& C.unshare(int(C.CLONE_NEWNS)) == 0, 2810)
				busy_mount(c'/tmp/mount-lifecycle/busy/a/child')
				marker(c'/tmp/mount-lifecycle/busy/a/child/marker')
				mut token := u8(1)
				check(C.write(int(ready[1]), &token, 1) == 1 && C.close(int(ready[1])) == 0
					&& C.read(int(stop[0]), &token, 1) == 1 && C.close(int(stop[0])) == 0, 2810)
				busy_preserved(c'/tmp/mount-lifecycle/busy/a', c'/tmp/mount-lifecycle/busy/a/child')
				check(C.umount2(c'/tmp/mount-lifecycle/busy/a/child', 0) == 0
					&& C.umount2(c'/tmp/mount-lifecycle/busy/a', 0) == 0, 2811)
				C._exit(0)
			}
			mut token := u8(0)
			check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0
				&& C.read(int(ready[0]), &token, 1) == 1 && C.close(int(ready[0])) == 0
				&& C.umount2(c'/tmp/mount-lifecycle/busy/a', 0) == 0
				&& C.write(int(stop[1]), &token, 1) == 1 && C.close(int(stop[1])) == 0, 2812)
			wait_child(child)
		} else if kind == 7 {
			held := C.open(c'/tmp/mount-lifecycle/busy/a/child', C.O_PATH | C.O_DIRECTORY)
			check(held >= 0 && C.umount2(c'/tmp/mount-lifecycle/busy/a', int(C.MNT_DETACH)) == 0, 2813)
			busy_mount(c'/tmp/mount-lifecycle/busy/a')
			marker(c'/tmp/mount-lifecycle/busy/a/marker')
			// Detached descendants and their saved routes do not belong to
			// this fresh attachment. Lazy detach still removes the whole tree.
			mut path := [256]char{}
			check(C.snprintf(&path[0], 256, c'/proc/self/fd/%d', held) > 0, 2813)
			refused_unmount(&path[0], 0, C.EINVAL, 2813)
			check(C.close(held) == 0 && C.umount2(c'/tmp/mount-lifecycle/busy/a', 0) == 0, 2813)
		} else {
			if kind == 3 { check(C.umount2(c'/tmp/mount-lifecycle/busy/b', 0) == 0, 2814) }
			if kind == 6 {
				child := C.fork()
				check(child >= 0, 2815)
				if child == 0 {
					check(C.unshare(int(C.CLONE_NEWNS)) == 0
						&& C.umount2(c'/tmp/mount-lifecycle/busy/a/child', 0) == 0
						&& C.umount2(c'/tmp/mount-lifecycle/busy/a', 0) == 0, 2815)
					C._exit(0)
				}
				wait_child(child)
			}
			busy_preserved(c'/tmp/mount-lifecycle/busy/a', c'/tmp/mount-lifecycle/busy/a/child')
			if kind == 1 {
				busy_preserved(c'/tmp/mount-lifecycle/busy/a/child', c'/tmp/mount-lifecycle/busy/a/child/grand')
				check(C.umount2(c'/tmp/mount-lifecycle/busy/a/child', int(C.MNT_DETACH)) == 0, 2816)
			} else { check(C.umount2(c'/tmp/mount-lifecycle/busy/a/child', 0) == 0, 2816) }
			check(C.umount2(c'/tmp/mount-lifecycle/busy/a', 0) == 0, 2816)
		}
		check(C.umount2(c'/tmp/mount-lifecycle/busy', 0) == 0, 2817)
	}
}

fn unmount_busy_cases(selected int) {
	unsafe { directory(c'/tmp/mount-lifecycle/busy') }
	for kind in 0 .. 8 {
		if selected >= 0 && selected != kind { continue }
		child := C.fork()
		check(child >= 0, 2818)
		if child == 0 { busy_case(kind); C._exit(0) }
		wait_child(child)
		unsafe { C.printf(c'MOUNT UNMOUNT BUSY CASE: %d PASS\n', kind) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT UNMOUNT BUSY: PASS')
	C.fflush(unsafe { nil })
}
