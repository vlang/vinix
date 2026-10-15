// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn mount_rename_result(odir int, old &char, ndir int, name &char, operation int, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	flags := if operation == 2 { 1 } else if operation == 3 { 2 } else { 0 }
	result := if operation == 0 {
		C.syscall(int(C.SYS_renameat), i32(odir), old, i32(ndir), name)
	} else {
		C.syscall(int(C.SYS_renameat2), i32(odir), old, i32(ndir), name, i32(flags))
	}
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT RENAME RESULT: operation=%d result=%ld errno=%d expected=%d\n', i32(operation), i64(result), failure, i32(expected)) }
	C.fflush(unsafe { nil })
	check(false, 480)
}

fn mount_rename_entry(dirfd int, path &char, form int, source bool) {
	unsafe {
		if form == 0 {
			fd := C.openat(dirfd, path, C.O_CREAT | C.O_EXCL | C.O_WRONLY, u32(0o600))
			value := if source { &char(c'MOUNT-OK') } else { &char(c'DEST-OLD') }
			check(fd >= 0 && C.write(fd, value, 8) == 8 && C.close(fd) == 0, 481)
		} else if form == 1 {
			mount_symlink_result(if source { c'marker' } else { c'missing' }, dirfd, path, 0)
		} else { check(C.mkdirat(i32(dirfd), path, u32(0o700)) == 0, 481) }
	}
}

fn mount_rename_identity(dirfd int, path &char, original &C.stat) {
	mut value := C.stat{}
	check(mount_symlink_stat(dirfd, path, &value) == 0, 482)
	timestamp_identity(&value, original)
}

fn mount_rename_held(fd int, form int, original &C.stat, source bool, replaced bool) {
	unsafe {
		mut value := C.stat{}
		check(C.fstat(fd, &value) == 0 && value.st_dev == original.st_dev && value.st_ino == original.st_ino
			&& value.st_mode == original.st_mode && value.st_uid == original.st_uid && value.st_gid == original.st_gid, 483)
		if form != 2 { check(value.st_nlink == if replaced { u64(0) } else { original.st_nlink }, 483) }
		if form == 0 {
			mut bytes := [8]u8{}
			check(C.read(fd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], if source { c'MOUNT-OK' } else { c'DEST-OLD' }, 8) == 0, 483)
		}
	}
}

fn mount_rename_pair(wdir int, rdir int, writable &char, readonly &char, round int) {
	unsafe {
		check(C.syscall(int(C.SYS_fchmodat), i32(wdir), writable, u32(0o755)) == 0, 484)
		wparent := C.openat(wdir, writable, C.O_PATH | C.O_DIRECTORY)
		rparent := C.openat(rdir, readonly, C.O_PATH | C.O_DIRECTORY)
		check(wparent >= 0 && rparent >= 0, 484)
		mut wa := [512]char{}
		mut wb := [512]char{}
		mut ra := [512]char{}
		mut rb := [512]char{}
		for iteration in 0 .. 16 {
			for form in 0 .. 3 {
				for operation in 0 .. 4 {
					check(C.snprintf(&wa[0], 512, c'%s/old-%d-%d-%d-%d', writable, i32(round), i32(iteration), i32(form), i32(operation)) > 0
						&& C.snprintf(&wb[0], 512, c'%s/new-%d-%d-%d-%d', writable, i32(round), i32(iteration), i32(form), i32(operation)) > 0
						&& C.snprintf(&ra[0], 512, c'%s/old-%d-%d-%d-%d', readonly, i32(round), i32(iteration), i32(form), i32(operation)) > 0
						&& C.snprintf(&rb[0], 512, c'%s/new-%d-%d-%d-%d', readonly, i32(round), i32(iteration), i32(form), i32(operation)) > 0, 484)
					mount_rename_entry(wdir, &wa[0], form, true)
					if operation != 2 { mount_rename_entry(wdir, &wb[0], form, false) }
					a := C.openat(wdir, &wa[0], if form == 0 { C.O_RDONLY } else { C.O_PATH | C.O_NOFOLLOW })
					b := if operation == 2 { -1 } else { C.openat(wdir, &wb[0], if form == 0 { C.O_RDONLY } else { C.O_PATH | C.O_NOFOLLOW }) }
					mut original := C.stat{}
					mut target := C.stat{}
					mut before := C.stat{}
					check(a >= 0 && C.fstat(a, &original) == 0 && C.fstat(wparent, &before) == 0, 484)
					if operation != 2 { check(b >= 0 && C.fstat(b, &target) == 0, 484) }
					mount_rename_result(rdir, &ra[0], rdir, &rb[0], operation, C.EROFS)
					// A completed authorized iteration reports an old kernel's
					// false writable refusal before the permission checks.
					if iteration == 1 {
						child := C.fork()
						check(child >= 0, 485)
						if child == 0 {
							check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 485)
							mount_rename_result(wdir, &wa[0], wdir, &wb[0], operation, C.EACCES)
							mount_rename_result(rdir, &ra[0], rdir, &rb[0], operation, C.EROFS)
							C._exit(0)
						}
						wait_child(child)
					}
					timestamp_unchanged(wparent, &before); timestamp_unchanged(rparent, &before); timestamp_unchanged(a, &original)
					mount_rename_identity(rdir, &ra[0], &original)
					if operation != 2 {
						timestamp_unchanged(b, &target)
						mount_rename_identity(rdir, &rb[0], &target)
					} else { mount_symlink_absent(wdir, rdir, &wb[0], &rb[0]) }
					mount_rename_result(wdir, &wa[0], wdir, &wb[0], operation, 0)
					mount_rename_identity(wdir, &wb[0], &original); mount_rename_identity(rdir, &rb[0], &original)
					if form == 1 { mount_symlink_value(wdir, &wb[0], c'marker', &original) }
					if operation == 3 {
						mount_rename_identity(wdir, &wa[0], &target); mount_rename_identity(rdir, &ra[0], &target)
						if form == 1 { mount_symlink_value(wdir, &wa[0], c'missing', &target) }
					} else { mount_symlink_absent(wdir, rdir, &wa[0], &ra[0]) }
					mount_rename_held(a, form, &original, true, false)
					if operation != 2 { mount_rename_held(b, form, &target, false, operation != 3); check(C.close(b) == 0, 486) }
					if operation == 3 { mount_unlink_result(wdir, &wa[0], form == 2, 0) }
					mount_unlink_result(wdir, &wb[0], form == 2, 0)
					check(C.close(a) == 0, 486)
				}
			}
		}
		mut path := [512]char{}
		check(C.snprintf(&path[0], 512, c'%s/marker', writable) > 0, 486)
		data := C.openat(wdir, &path[0], C.O_RDONLY)
		mut bytes := [8]u8{}
		check(data >= 0 && C.read(data, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0
			&& C.close(data) == 0 && C.close(wparent) == 0 && C.close(rparent) == 0, 486)
	}
}

fn mount_rename_identity_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 487)
		mut base := [256]char{}
		mut source := [256]char{}
		mut other := [256]char{}
		mut path := [512]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/rp-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0 && C.snprintf(&other[0], 256, c'%s/other', &base[0]) > 0, 487)
		directory(&base[0]); directory(&source[0]); directory(&other[0])
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&path[0], 512, c'%s/marker', &source[0]) > 0, 487)
		marker(&path[0])
		if kind == 8 {
			check(C.mount(&source[0], &other[0], nil, usize(C.MS_BIND), nil) == 0, 487)
			src := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
			dst := C.open(&other[0], C.O_PATH | C.O_DIRECTORY)
			check(src >= 0 && dst >= 0, 487)
			mount_rename_entry(src, c'target', 0, false)
			mut original := C.stat{}
			mut target := C.stat{}
			mut before := C.stat{}
			check(mount_symlink_stat(src, c'marker', &original) == 0 && mount_symlink_stat(src, c'target', &target) == 0 && C.fstat(src, &before) == 0, 487)
			for operation in 0 .. 4 {
				name := if operation == 2 { &char(c'blocked') } else { &char(c'target') }
				mount_rename_result(src, c'marker', dst, name, operation, C.EXDEV)
				mount_rename_result(dst, c'marker', src, name, operation, C.EXDEV)
				mount_rename_identity(src, c'marker', &original); mount_rename_identity(dst, c'target', &target)
				mount_symlink_absent(src, dst, c'blocked', c'blocked')
				timestamp_unchanged(src, &before); timestamp_unchanged(dst, &before)
			}
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 488)
			fresh := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
			check(fresh >= 0, 488)
			for operation in 0 .. 4 {
				name := if operation == 2 { &char(c'blocked') } else { &char(c'target') }
				mount_rename_result(src, c'marker', fresh, name, operation, C.EXDEV)
				mount_rename_result(fresh, c'marker', src, name, operation, C.EXDEV)
				mount_rename_identity(src, c'marker', &original); mount_rename_identity(fresh, c'target', &target)
				mount_symlink_absent(src, fresh, c'blocked', c'blocked')
				timestamp_unchanged(src, &before); timestamp_unchanged(fresh, &before)
			}
			for fd in [src, fresh]! {
				mount_rename_result(fd, c'marker', fd, c'local', 0, 0)
				mount_rename_result(fd, c'local', fd, c'marker', 1, 0)
			}
			check(C.close(src) == 0 && C.close(dst) == 0 && C.close(fresh) == 0, 488)
		} else {
			check(C.snprintf(&path[0], 512, c'%s/a', &source[0]) > 0 && C.mkdir(&path[0], u32(0o755)) == 0, 489)
			a := C.open(&path[0], C.O_PATH | C.O_DIRECTORY)
			check(C.snprintf(&path[0], 512, c'%s/b', &source[0]) > 0 && C.mkdir(&path[0], u32(0o755)) == 0, 489)
			b := C.open(&path[0], C.O_PATH | C.O_DIRECTORY)
			check(a >= 0 && b >= 0 && C.mkdirat(i32(a), c'child', u32(0o700)) == 0, 489)
			held := C.openat(a, c'child', C.O_PATH | C.O_DIRECTORY)
			mut ap := C.stat{}
			mut bp := C.stat{}
			check(held >= 0 && C.fstat(a, &ap) == 0 && C.fstat(b, &bp) == 0, 489)
			for _ in 0 .. 16 {
				mount_rename_result(a, c'child', b, c'moved', 0, 0)
				check(C.fstat(b, &bp) == 0, 489)
				mount_rename_identity(held, c'..', &bp)
				mount_rename_result(b, c'moved', a, c'child', 1, 0)
				check(C.fstat(a, &ap) == 0, 489)
				mount_rename_identity(held, c'..', &ap)
			}
			check(C.snprintf(&path[0], 512, c'%s/a/covered', &source[0]) > 0 && C.mkdir(&path[0], u32(0o755)) == 0
				&& C.mount(c'tmpfs', &path[0], c'tmpfs', 0, nil) == 0, 489)
			mount_rename_entry(b, c'target', 2, true)
			mut cover := C.stat{}
			mut original := C.stat{}
			check(mount_symlink_stat(a, c'covered', &cover) == 0 && mount_symlink_stat(b, c'target', &original) == 0, 489)
			for operation in [0, 1, 3]! {
				mount_rename_result(a, c'covered', b, c'target', operation, C.EBUSY)
				mount_rename_result(b, c'target', a, c'covered', operation, C.EBUSY)
				mount_rename_identity(a, c'covered', &cover); mount_rename_identity(b, c'target', &original)
			}
			check(C.close(a) == 0 && C.close(b) == 0 && C.close(held) == 0, 489)
		}
	}
}

fn mount_rename_case(kind int) {
	unsafe {
		if kind >= 8 { mount_rename_identity_case(kind); return }
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 457)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [256]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/rp-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0
			&& C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 457)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		if kind == 5 {
			peer := &TruncatePeer(C.alloca(sizeof(TruncatePeer)))
			*peer = TruncatePeer{source_path: source, alias_path: alias, source_fd: -1, alias_fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, truncate_retired_worker, peer) == 0 && C.pthread_join(handle, nil) == 0, 457)
			mount_rename_pair(peer.source_fd, peer.alias_fd, c'.', c'.', 0)
			check(C.close(peer.source_fd) == 0 && C.close(peer.alias_fd) == 0, 457)
			return
		}
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&path[0], 256, c'%s/marker', &source[0]) > 0, 457)
		marker(&path[0])
		mut source_link := [256]char{}
		mut alias_link := [256]char{}
		if kind == 3 {
			check(C.snprintf(&source_link[0], 256, c'%s/source-link', &base[0]) > 0
				&& C.snprintf(&alias_link[0], 256, c'%s/alias-link', &base[0]) > 0
				&& C.symlink(&source[0], &source_link[0]) == 0 && C.symlink(&alias[0], &alias_link[0]) == 0, 457)
		}
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 457)
		if kind == 6 { bind_policy_remount(&source[0], true) } else { bind_policy_remount(&alias[0], true) }
		if kind == 1 { check(C.unshare(int(C.CLONE_NEWNS)) == 0, 457) }
		source_fd := C.open(&source[0], C.O_PATH | C.O_DIRECTORY)
		alias_fd := C.open(&alias[0], C.O_PATH | C.O_DIRECTORY)
		check(source_fd >= 0 && alias_fd >= 0, 457)
		if kind == 7 {
			check(C.unshare(int(C.CLONE_NEWNS)) == 0, 457)
			mount_rename_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 2 {
			check(C.chdir(&alias[0]) == 0 && C.chroot(&source[0]) == 0, 457)
			mount_rename_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'/', c'.', 0)
			bind_policy_remount(c'.', false); bind_policy_remount(c'/', true)
			mount_rename_pair(int(C.AT_FDCWD), int(C.AT_FDCWD), c'.', c'/', 1)
		} else if kind == 3 {
			// Absolute paths ignore an invalid dirfd and follow the final
			// parent through a symlink into the selected bind attachment.
			mount_rename_pair(-999, -999, &source_link[0], &alias_link[0], 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_rename_pair(-999, -999, &alias_link[0], &source_link[0], 1)
		} else if kind == 4 {
			check(C.umount2(&alias[0], int(C.MNT_DETACH)) == 0, 457)
			mount_rename_pair(source_fd, alias_fd, c'.', c'.', 0)
		} else if kind == 6 {
			mount_rename_pair(alias_fd, source_fd, c'.', c'.', 0)
		} else {
			mount_rename_pair(source_fd, alias_fd, c'.', c'.', 0)
			bind_policy_remount(&alias[0], false); bind_policy_remount(&source[0], true)
			mount_rename_pair(alias_fd, source_fd, c'.', c'.', 1)
		}
		check(C.close(source_fd) == 0 && C.close(alias_fd) == 0, 457)
	}
}

fn mount_rename_cases(selected int) {
	unsafe {
		for kind in 0 .. 10 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 458)
			if child == 0 { mount_rename_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT RENAME CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT RENAME: PASS')
		C.fflush(nil)
	}
}
