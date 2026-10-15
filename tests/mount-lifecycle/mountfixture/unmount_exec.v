// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn unmount_exec_signal(fd int) { check(C.write(fd, c'X', 1) == 1, 3112) }

fn unmount_exec_wait(fd int) {
	mut token := u8(0)
	check(C.read(fd, &token, 1) == 1 && token == `X`, 3112)
}

fn unmount_exec_launch(path &char, kind int, ready int, stop int, fd int) {
	unsafe {
		mut kind_text := [32]char{}
		mut ready_text := [32]char{}
		mut stop_text := [32]char{}
		mut fd_text := [32]char{}
		check(C.snprintf(&kind_text[0], 32, c'%d', i32(kind)) > 0
			&& C.snprintf(&ready_text[0], 32, c'%d', i32(ready)) > 0
			&& C.snprintf(&stop_text[0], 32, c'%d', i32(stop)) > 0
			&& C.snprintf(&fd_text[0], 32, c'%d', i32(fd)) > 0, 3100)
		arguments := [&char(c'unmount-exec'), &char(c'--mount-unmount-exec'),
			&kind_text[0], &ready_text[0], &stop_text[0], &fd_text[0], &char(nil)]!
		environment := [&char(nil)]!
		if fd >= 0 {
			C.syscall(int(C.SYS_execveat), i32(fd), c'', &arguments[0], &environment[0], i32(C.AT_EMPTY_PATH))
		} else { C.syscall(int(C.SYS_execve), path, &arguments[0], &environment[0]) }
		check(false, 3100)
	}
}

fn unmount_exec_entry(argc i32, argv &&char) {
	unsafe {
		if argc != 6 || C.strcmp(argv[1], c'--mount-unmount-exec') != 0 { return }
		kind := int(C.atoi(argv[2]))
		ready := int(C.atoi(argv[3]))
		stop := int(C.atoi(argv[4]))
		fd := C.atoi(argv[5])
		check(kind >= 0 && kind <= 8 && ready >= 0 && stop >= 0, 3101)
		if kind == 0 {
			check(C.getuid() == 1000 && C.geteuid() == 1000, 3101)
			refused_unmount(c'/tmp/mount-lifecycle/ue/a', 0, C.EPERM, 3101)
		}
		if kind == 1 {
			check(fd >= 0 && C.syscall(int(C.SYS_fcntl), fd, i32(C.F_GETFD), i32(0)) == -1
				&& *C.__errno_location() == C.EBADF, 3101)
		}
		if kind == 2 {
			// The executable still belongs to the original attachment. Its
			// copied namespace mount is unused and may unmount independently.
			check(C.unshare(int(C.CLONE_NEWNS)) == 0
				&& C.umount2(c'/tmp/mount-lifecycle/ue/a', 0) == 0, 3102)
		}
		unmount_exec_signal(ready)
		unmount_exec_wait(stop)
		if kind == 7 {
			unmount_exec_launch(c'/tmp/mount-lifecycle/ue/outside', 8, ready, stop, -1)
		}
		// Continue executing and read the image after refusal or lazy detach.
		image := C.open(c'/proc/self/exe', C.O_RDONLY)
		mut signature := [4]u8{}
		check(image >= 0 && C.read(image, &signature[0], 4) == 4 && C.close(image) == 0
			&& signature[0] == 127 && signature[1] == `E` && signature[2] == `L` && signature[3] == `F`, 3103)
		C._exit(0)
	}
}

fn unmount_exec_busy(path &char, marker_path &char) {
	unsafe {
		mut before := C.stat{}
		check(C.stat(path, &before) == 0, 3104)
		for _ in 0 .. 200 {
			refused_unmount(path, 0, C.EBUSY, 3104)
			check(same(path, &before) && contents(marker_path), 3104)
		}
	}
}

fn unmount_exec_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 3105)
		busy_mount(c'/tmp/mount-lifecycle/ue')
		directory(c'/tmp/mount-lifecycle/ue/a')
		directory(c'/tmp/mount-lifecycle/ue/b')
		busy_mount(c'/tmp/mount-lifecycle/ue/a')
		marker(c'/tmp/mount-lifecycle/ue/a/marker')
		descriptor_exec_copy(c'/tmp/mount-lifecycle/ue/a/image')
		if kind == 7 { descriptor_exec_copy(c'/tmp/mount-lifecycle/ue/outside') }
		if kind in [3, 4] {
			check(C.mount(c'/tmp/mount-lifecycle/ue/a', c'/tmp/mount-lifecycle/ue/b', nil,
				usize(C.MS_BIND), nil) == 0, 3105)
		}
		active := if kind == 4 { &char(c'/tmp/mount-lifecycle/ue/b') } else { &char(c'/tmp/mount-lifecycle/ue/a') }
		mark := if kind == 4 { &char(c'/tmp/mount-lifecycle/ue/b/marker') } else { &char(c'/tmp/mount-lifecycle/ue/a/marker') }
		path := if kind == 4 { &char(c'/tmp/mount-lifecycle/ue/b/image') } else { &char(c'/tmp/mount-lifecycle/ue/a/image') }
		mut ready := [2]i32{}
		mut stop := [2]i32{}
		check(C.pipe(&ready[0]) == 0 && C.pipe(&stop[0]) == 0, 3106)
		child := C.fork()
		check(child >= 0, 3106)
		if child == 0 {
			check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0, 3106)
			fd := if kind == 1 { C.open(path, C.O_PATH | C.O_CLOEXEC) } else { -1 }
			if kind == 1 { check(fd >= 0 && C.unlink(path) == 0, 3106) }
			if kind == 0 { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 3106) }
			unmount_exec_launch(path, kind, int(ready[1]), int(stop[0]), fd)
			C._exit(1)
		}
		check(C.close(int(ready[1])) == 0 && C.close(int(stop[0])) == 0, 3106)
		unmount_exec_wait(int(ready[0]))
		if kind in [3, 4] {
			other := if kind == 3 { &char(c'/tmp/mount-lifecycle/ue/b') } else { &char(c'/tmp/mount-lifecycle/ue/a') }
			check(C.umount2(other, 0) == 0, 3107)
		}
		if kind == 5 {
			check(C.umount2(active, int(C.MNT_DETACH)) == 0, 3107)
			busy_mount(active)
			marker(mark)
			check(C.umount2(active, 0) == 0, 3107)
		} else { unmount_exec_busy(active, mark) }
		unmount_exec_signal(int(stop[1]))
		if kind == 7 {
			// Same PID, new executable, still alive: the old image no longer
			// pins the mount, even before process teardown.
			unmount_exec_wait(int(ready[0]))
			check(C.umount2(active, 0) == 0, 3108)
			unmount_exec_signal(int(stop[1]))
		}
		if kind == 6 {
			mut info := [128]u8{}
			check(C.syscall(int(C.SYS_waitid), i32(C.P_PID), i32(child), &info[0],
				i32(C.WEXITED | C.WNOWAIT), nil) == 0, 3109)
			mut name := [128]char{}
			mut st := C.stat{}
			check(C.snprintf(&name[0], 128, c'/proc/%d', i32(child)) > 0
				&& C.stat(&name[0], &st) == 0 && C.umount2(active, 0) == 0, 3109)
		}
		wait_child(child)
		check(C.close(int(ready[0])) == 0 && C.close(int(stop[1])) == 0, 3106)
		if kind !in [5, 6, 7] { check(C.umount2(active, 0) == 0, 3110) }
		check(C.umount2(c'/tmp/mount-lifecycle/ue', 0) == 0, 3110)
	}
}

fn unmount_exec_cases(selected int) {
	unsafe { directory(c'/tmp/mount-lifecycle/ue') }
	for kind in 0 .. 8 {
		if selected >= 0 && kind != selected { continue }
		child := C.fork()
		check(child >= 0, 3111)
		if child == 0 { unmount_exec_case(kind); C._exit(0) }
		wait_child(child)
		unsafe { C.printf(c'MOUNT UNMOUNT EXEC CASE: %d PASS\n', i32(kind)) }
		C.fflush(unsafe { nil })
	}
	C.puts(c'MOUNT UNMOUNT EXEC: PASS')
	C.fflush(unsafe { nil })
}
