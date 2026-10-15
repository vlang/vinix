// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

struct UnmountPathPeer {
	kind int
	ready int
	stop int
	outside int
	namespace int
}

fn unmount_path_busy() {
	unsafe {
		mut before := C.stat{}
		check(C.stat(c'/tmp/mount-lifecycle/up/a', &before) == 0, 3000)
		for _ in 0 .. 200 {
			refused_unmount(c'/tmp/mount-lifecycle/up/a', 0, C.EBUSY, 3001)
			check(same(c'/tmp/mount-lifecycle/up/a', &before)
				&& contents(c'/tmp/mount-lifecycle/up/a/n/marker'), 3002)
		}
	}
}

fn unmount_path_tree() {
	unsafe {
		busy_mount(c'/tmp/mount-lifecycle/up/a')
		directory(c'/tmp/mount-lifecycle/up/a/n')
		marker(c'/tmp/mount-lifecycle/up/a/n/marker')
	}
}

fn unmount_path_thread(argument voidptr) voidptr {
	unsafe {
		peer := &UnmountPathPeer(argument)
		check(C.unshare(int(C.CLONE_FS)) == 0, 3003)
		if peer.kind == 6 { check(C.setns(peer.namespace, int(C.CLONE_NEWNS)) == 0, 3003) }
		if peer.kind == 5 {
			check(C.chroot(c'/tmp/mount-lifecycle/up/a') == 0 && contents(c'/n/marker'), 3003)
		} else {
			check(C.chdir(c'/tmp/mount-lifecycle/up/a/n') == 0 && contents(c'marker'), 3003)
		}
		alias_signal(peer.ready)
		alias_wait(peer.stop)
		if peer.kind == 5 {
			check(C.fchdir(peer.outside) == 0 && C.chroot(c'.') == 0, 3004)
		}
		check(C.chdir(c'/') == 0, 3004)
		return nil
	}
}

fn unmount_path_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3005)
		busy_mount(c'/tmp/mount-lifecycle/up')
		directory(c'/tmp/mount-lifecycle/up/a')
		directory(c'/tmp/mount-lifecycle/up/b')
		if kind != 7 { unmount_path_tree() }
		if kind == 0 {
			check(C.chdir(c'/tmp/mount-lifecycle/up/a/n') == 0, 3006)
			child := C.fork()
			check(child >= 0, 3006)
			if child == 0 {
				check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 3006)
				refused_unmount(c'/tmp/mount-lifecycle/up/a', 0, C.EPERM, 3006)
				C._exit(0)
			}
			wait_child(child)
			unmount_path_busy()
			check(contents(c'marker') && C.chdir(c'/') == 0, 3006)
		} else if kind == 2 {
			for direction in 0 .. 2 {
				check(C.mount(c'/tmp/mount-lifecycle/up/a', c'/tmp/mount-lifecycle/up/b', nil,
					usize(C.MS_BIND), nil) == 0, 3007)
				active := if direction == 0 { &char(c'/tmp/mount-lifecycle/up/a') } else { &char(c'/tmp/mount-lifecycle/up/b') }
				other := if direction == 0 { &char(c'/tmp/mount-lifecycle/up/b') } else { &char(c'/tmp/mount-lifecycle/up/a') }
				path := if direction == 0 { &char(c'/tmp/mount-lifecycle/up/a/n') } else { &char(c'/tmp/mount-lifecycle/up/b/n') }
				check(C.chdir(path) == 0 && C.umount2(other, 0) == 0, 3007)
				for _ in 0 .. 200 {
					refused_unmount(active, 0, C.EBUSY, 3007)
					check(contents(c'marker'), 3007)
				}
				check(C.chdir(c'/') == 0 && C.umount2(active, 0) == 0, 3007)
				if direction == 0 { unmount_path_tree() }
			}
		} else if kind == 4 || kind == 5 {
			mut ready := [2]i32{}
			mut stop := [2]i32{}
			outside := C.open(c'/', C.O_PATH | C.O_DIRECTORY)
			check(outside >= 0 && C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 3008)
			mut peer := &UnmountPathPeer(C.alloca(sizeof(UnmountPathPeer)))
			*peer = UnmountPathPeer{kind: kind, ready: int(ready[1]), stop: int(stop[0]), outside: outside}
			mut worker_handle := C.pthread_t{}
			check(C.pthread_create(&worker_handle, nil, unmount_path_thread, peer) == 0, 3008)
			alias_wait(int(ready[0]))
			unmount_path_busy()
			alias_signal(int(stop[1]))
			check(C.pthread_join(worker_handle, nil) == 0 && C.close(outside) == 0, 3008)
		} else if kind == 9 {
			child := C.fork()
			check(child >= 0, 3009)
			if child == 0 {
				check(C.chroot(c'/tmp/mount-lifecycle/up/a') == 0 && C.chdir(c'/n') == 0, 3009)
				C._exit(0)
			}
			mut info := [128]u8{}
			check(C.syscall(int(C.SYS_waitid), i32(C.P_PID), i32(child), &info[0], i32(C.WEXITED | C.WNOWAIT), nil) == 0, 3009)
			mut path := [128]char{}
			mut st := C.stat{}
			check(C.snprintf(&path[0], 128, c'/proc/%d', i32(child)) > 0 && C.stat(&path[0], &st) == 0
				&& C.umount2(c'/tmp/mount-lifecycle/up/a', 0) == 0, 3009)
			wait_child(child)
		} else {
			mut ready := [2]i32{}
			mut stop := [2]i32{}
			mut setup := [2]i32{}
			namespace := C.open(c'/proc/self/ns/mnt', C.O_RDONLY)
			outside := C.open(c'/', C.O_PATH | C.O_DIRECTORY)
			parent := C.syscall(int(C.SYS_getpid))
			check(namespace >= 0 && outside >= 0 && C.pipe(&ready[0]) == 0
				&& C.pipe(&stop[0]) == 0 && C.pipe(&setup[0]) == 0, 3010)
			child := C.fork()
			check(child >= 0, 3010)
			if child == 0 {
				check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0 && C.close(int(setup[1])) == 0, 3010)
				if kind == 7 {
					check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3011)
					mut number := i32(-1)
					// Tell the parent the table copy predates its new mount.
					check(C.write(int(ready[1]), c'X', 1) == 1
						&& C.read(int(setup[0]), &number, sizeof(i32)) == sizeof(i32), 3011)
					mut path := [256]char{}
					check(C.snprintf(&path[0], 256, c'/proc/%d/fd/%d', i32(parent), number) > 0, 3011)
					fd := C.open(&path[0], C.O_PATH | C.O_DIRECTORY)
					check(fd >= 0 && C.fchdir(fd) == 0 && C.close(fd) == 0, 3011)
				} else if kind == 6 {
					check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3012)
					mut peer := &UnmountPathPeer(C.alloca(sizeof(UnmountPathPeer)))
					*peer = UnmountPathPeer{kind: kind, ready: int(ready[1]), stop: int(stop[0]), namespace: namespace}
					mut worker_handle := C.pthread_t{}
					check(C.pthread_create(&worker_handle, nil, unmount_path_thread, peer) == 0
						&& C.pthread_join(worker_handle, nil) == 0, 3012)
					C._exit(0)
				} else if kind == 1 {
					check(C.chroot(c'/tmp/mount-lifecycle/up/a') == 0 && contents(c'/n/marker'), 3013)
				} else {
					check(C.chdir(c'/tmp/mount-lifecycle/up/a/n') == 0, 3013)
					if kind == 3 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3013) }
				}
				check(C.close(int(setup[0])) == 0, 3010)
				alias_signal(int(ready[1]))
				alias_wait(int(stop[0]))
				if kind == 1 { check(C.fchdir(outside) == 0 && C.chroot(c'.') == 0, 3013) }
				else { check(contents(c'marker'), 3013) }
				if kind == 3 { unmount_path_busy() }
				check(C.chdir(c'/') == 0, 3013)
				if kind == 3 { check(C.umount2(c'/tmp/mount-lifecycle/up/a', 0) == 0, 3013) }
				C._exit(0)
			}
			check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0 && C.close(int(setup[0])) == 0, 3010)
			if kind == 7 {
				mut token := u8(0)
				check(C.read(int(ready[0]), &token, 1) == 1, 3011)
				unmount_path_tree()
				fd := C.open(c'/tmp/mount-lifecycle/up/a/n', C.O_PATH | C.O_DIRECTORY)
				number := i32(fd)
				check(fd >= 0 && C.write(int(setup[1]), &number, sizeof(i32)) == sizeof(i32), 3011)
				alias_wait(int(ready[0]))
				check(C.close(fd) == 0, 3011)
			} else { alias_wait(int(ready[0])) }
			check(C.close(int(setup[1])) == 0, 3010)
			if kind == 3 { check(C.umount2(c'/tmp/mount-lifecycle/up/a', 0) == 0, 3014) }
			else if kind == 8 {
				check(C.umount2(c'/tmp/mount-lifecycle/up/a', int(C.MNT_DETACH)) == 0, 3014)
				unmount_path_tree()
				check(C.umount2(c'/tmp/mount-lifecycle/up/a', 0) == 0, 3014)
			} else { unmount_path_busy() }
			alias_signal(int(stop[1]))
			wait_child(child)
			check(C.close(namespace) == 0 && C.close(outside) == 0, 3010)
		}
		if kind !in [2, 3, 8, 9] { check(C.umount2(c'/tmp/mount-lifecycle/up/a', 0) == 0, 3015) }
		check(C.umount2(c'/tmp/mount-lifecycle/up', 0) == 0, 3015)
	}
}

fn unmount_path_cases(selected int) {
	unsafe { directory(c'/tmp/mount-lifecycle/up') }
	for kind in 0 .. 10 {
		if selected >= 0 && kind != selected { continue }
		child := C.fork()
		check(child >= 0, 3016)
		if child == 0 { unmount_path_case(kind); C._exit(0) }
		wait_child(child)
		unsafe { C.printf(c'MOUNT UNMOUNT PATH CASE: %d PASS\n', i32(kind)) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT UNMOUNT PATHS: PASS')
	C.fflush(unsafe { nil })
}
