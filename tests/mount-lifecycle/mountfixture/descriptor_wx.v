// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

fn C.strstr(&char, &char) &char

struct WxCapHeader {
	version u32 = 0x20080522
	pid i32
}

struct WxCapData {
mut:
	effective u32
	permitted u32
	inheritable u32
}

fn descriptor_wx_mapping(allowed bool) {
	unsafe {
		size := C.sysconf(C._SC_PAGESIZE)
		check(size >= 4096, 630)
		page := usize(size)
		flags := i32(C.MAP_PRIVATE | C.MAP_ANONYMOUS)
		prot := i32(C.PROT_READ | C.PROT_WRITE | C.PROT_EXEC)
		address := C.mmap(nil, page, prot, flags, -1, 0)
		if allowed {
			check(address != voidptr(C.MAP_FAILED), 630)
			*&u64(address) = u64(0x1122334455667788)
			check(*&u64(address) == u64(0x1122334455667788) && C.munmap(address, page) == 0, 630)
		} else {
			check(address == voidptr(C.MAP_FAILED) && *C.__errno_location() == C.EOPNOTSUPP, 630)
		}
		writable := C.mmap(nil, page, i32(C.PROT_READ | C.PROT_WRITE), flags, -1, 0)
		check(writable != voidptr(C.MAP_FAILED), 630)
		*&u64(writable) = u64(0x8877665544332211)
		result := C.mprotect(writable, page, prot)
		check(if allowed { result == 0 } else { result == -1 && *C.__errno_location() == C.EOPNOTSUPP }, 630)
		check(*&u64(writable) == u64(0x8877665544332211) && C.munmap(writable, page) == 0, 630)
	}
}

fn descriptor_wx_entry(argc i32, argv &&char) {
	unsafe {
		if argc < 4 || C.strcmp(argv[argc - 3], c'--mount-wx-child') != 0 { return }
		allowed := C.strcmp(argv[argc - 2], c'allowed') == 0
		owner := C.strcmp(argv[argc - 1], c'owner') == 0
		uid := if owner { u32(1000) } else { u32(0) }
		check((allowed || C.strcmp(argv[argc - 2], c'default') == 0)
			&& (owner || C.strcmp(argv[argc - 1], c'root') == 0)
			&& C.getuid() == uid && C.geteuid() == uid && C.getgid() == uid && C.getegid() == uid, 631)
		descriptor_wx_mapping(allowed)
		child := C.fork()
		check(child >= 0, 631)
		if child == 0 { descriptor_wx_mapping(allowed); C._exit(0) }
		wait_child(child)
		// Proves exec reached the image and checked its actual mapping policy.
		C._exit(38)
	}
}

fn descriptor_wx_policy(path &char, approved bool) {
	unsafe {
		flags := usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV | C.MS_STRICTATIME)
		check(C.mount(c'none', path, nil, flags, if approved { c'wxallowed' } else { &char(nil) }) == 0, 632)
		// Check the live namespace's advertised policy, not an input flag bit.
		fd := C.open(c'/proc/self/mounts', C.O_RDONLY)
		mut bytes := [65536]char{}
		count := C.read(fd, &bytes[0], 65535)
		check(fd >= 0 && count > 0 && count < 65535 && C.close(fd) == 0, 632)
		mut needle := [512]char{}
		check(C.snprintf(&needle[0], 512, c' %s ', path) > 0, 632)
		mut start := 0
		mut found := 0
		for end in 0 .. int(count) + 1 {
			if end == count || bytes[end] == char(`\n`) {
				bytes[end] = 0
				if C.strstr(&bytes[start], &needle[0]) != nil {
					check((C.strstr(&bytes[start], c'wxallowed') != nil) == approved, 632)
					found++
				}
				start = end + 1
			}
		}
		check(found == 1, 632)
	}
}

fn descriptor_wx_attempt(form int, fd int, path &char, approved bool, identity int, request bool) {
	unsafe {
		child := C.fork()
		check(child >= 0, 633)
		if child == 0 {
			if identity == 1 {
				check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 633)
			} else if identity == 2 {
				header := WxCapHeader{}
				mut data := [2]WxCapData{}
				check(C.syscall(int(C.SYS_capget), &header, &data[0]) == 0, 633)
				data[0].effective &= ~(u32(1) << 21)
				data[0].permitted &= ~(u32(1) << 21)
				check(C.syscall(int(C.SYS_capset), &header, &data[0]) == 0, 633)
			}
			// If a denied request unexpectedly starts, prove the grant too.
			allowed := request
			arguments := [&char(c'mount-wx'), &char(c'--mount-wx-child'),
				if allowed { &char(c'allowed') } else { &char(c'default') },
				if identity == 1 { &char(c'owner') } else { &char(c'root') }, &char(nil)]!
			environment := [if request { &char(c'VINIX_ALLOW_WX=1') } else { &char(nil) }, &char(nil)]!
			location := C.__errno_location()
			*location = 0
			result := if form == 2 {
				C.syscall(int(C.SYS_execve), path, &arguments[0], &environment[0])
			} else {
				C.syscall(int(C.SYS_execveat), i32(fd), path, &arguments[0], &environment[0],
					i32(if form == 0 { C.AT_EMPTY_PATH } else { 0 }))
			}
			failure := *location
			if request && !approved && identity != 0 && result == -1 && failure == C.EPERM { C._exit(0) }
			C.printf(c'MOUNT DESCWX RESULT: form=%d result=%ld errno=%d expected=%d\n',
				i32(form), i64(result), failure, i32(if request && !approved && identity != 0 { C.EPERM } else { 0 }))
			C.fflush(nil)
			C._exit(1)
		}
		mut status := i32(0)
		check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0, 633)
		actual := C.WEXITSTATUS(status)
		expected := if request && !approved && identity != 0 { 0 } else { 38 }
		if actual != expected {
			C.printf(c'MOUNT DESCWX STATUS: form=%d status=%d expected=%d\n', i32(form), i32(actual), i32(expected))
			C.fflush(nil)
			check(false, 633)
		}
	}
}

fn descriptor_wx_case(kind int) {
	unsafe {
		approved := kind % 2 == 0
		unlinked := kind in [2, 3]
		script := kind >= 6
		identity := if kind in [4, 5] { 2 } else { 1 }
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 634)
		mut root := [256]char{}
		mut target := [256]char{}
		mut helper := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/dw-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0
			&& C.snprintf(&helper[0], 256, c'/tmp/mount-lifecycle/dw-%d-helper', i32(kind)) > 0, 634)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 634)
		if script {
			descriptor_exec_copy(&helper[0])
			check(C.mount(&helper[0], &helper[0], nil, usize(C.MS_BIND), nil) == 0, 634)
			descriptor_wx_policy(&helper[0], true)
			mut text := [512]char{}
			length := C.snprintf(&text[0], 512, c'#!%s\n', &helper[0])
			output := C.open(&target[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o755))
			check(length > 0 && length < 512 && output >= 0
				&& C.write(output, &text[0], usize(length)) == length && C.close(output) == 0, 634)
		} else { descriptor_exec_copy(&target[0]) }
		original := C.open(&target[0], C.O_RDONLY)
		original_path := C.open(&target[0], C.O_PATH)
		fd := int(C.syscall(int(C.SYS_dup), i32(original)))
		pathfd := int(C.syscall(int(C.SYS_dup), i32(original_path)))
		check(original >= 0 && original_path >= 0 && fd >= 0 && pathfd >= 0
			&& C.close(original) == 0 && C.close(original_path) == 0, 634)
		uid := if identity == 1 { u32(1000) } else { u32(0) }
		check(C.syscall(int(C.SYS_fchown), i32(fd), uid, uid) == 0
			&& C.syscall(int(C.SYS_fchmod), i32(fd), u32(0o755)) == 0, 634)
		if unlinked { check(C.unlink(&target[0]) == 0, 634) }
		descriptor_wx_policy(&root[0], approved)
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 635)
		descriptor_wx_policy(&root[0], !approved)
		dirfd := C.open(&root[0], C.O_PATH | C.O_DIRECTORY)
		fresh := if unlinked { -1 } else { C.open(&target[0], C.O_RDONLY) }
		fresh_path := if unlinked { -1 } else { C.open(&target[0], C.O_PATH) }
		check(dirfd >= 0 && (unlinked || (fresh >= 0 && fresh_path >= 0)), 635)
		// Initial-namespace root with CAP_SYS_ADMIN still has explicit authority.
		descriptor_wx_attempt(0, fd, c'', approved, 0, true)
		if fresh >= 0 { descriptor_wx_attempt(0, fresh, c'', !approved, 0, true) }
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0 && (!unlinked || before.st_nlink == 0), 635)
		for iteration in 0 .. 2 {
			for request in [true, false]! {
				descriptor_wx_attempt(0, fd, c'', approved, identity, request)
				descriptor_wx_attempt(0, pathfd, c'', approved, identity, request)
				if fresh >= 0 {
					descriptor_wx_attempt(0, fresh, c'', !approved, identity, request)
					descriptor_wx_attempt(0, fresh_path, c'', !approved, identity, request)
					descriptor_wx_attempt(1, -1234, &target[0], !approved, identity, request)
					descriptor_wx_attempt(3, dirfd, c'target', !approved, identity, request)
					descriptor_wx_attempt(2, -1, &target[0], !approved, identity, request)
				}
			}
		}
		mut after := C.stat{}
		check(C.fstat(fd, &after) == 0 && after.st_nlink == before.st_nlink, 636)
		timestamp_identity(&after, &before)
		check(timestamp_equal(after.st_mtim, before.st_mtim) && timestamp_equal(after.st_ctim, before.st_ctim), 636)
		mut bytes := [2]u8{}
		check(C.read(fd, &bytes[0], 2) == 2 && bytes[0] == if script { u8(`#`) } else { u8(127) }
			&& bytes[1] == if script { u8(`!`) } else { u8(`E`) }, 636)
		check(C.close(fd) == 0 && C.close(pathfd) == 0 && C.close(dirfd) == 0
			&& (fresh < 0 || (C.close(fresh) == 0 && C.close(fresh_path) == 0)), 636)
	}
}

fn descriptor_wx_cases(selected int) {
	unsafe {
		for kind in 0 .. 8 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 637)
			if child == 0 { descriptor_wx_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT DESCWX CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT DESCWX: PASS')
		C.fflush(nil)
	}
}
