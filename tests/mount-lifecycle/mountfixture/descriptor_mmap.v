// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <sys/mman.h>
fn C.sysconf(i32) isize
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32

fn descriptor_map_result(operation int, prot int, flags int, result int, failure i32, expected int) {
	unsafe {
		if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
		C.printf(c'MOUNT DESCMAP RESULT: operation=%ld prot=%ld flags=%ld result=%ld errno=%d expected=%ld\n',
			i64(operation), i64(prot), i64(flags), i64(result), failure, i64(expected))
		C.fflush(nil)
		check(false, 600)
	}
}

fn descriptor_map_open(fd int, page usize, prot int, flags int, expected int) voidptr {
	unsafe {
		location := C.__errno_location()
		*location = 0
		address := C.mmap(nil, page, i32(prot), i32(flags), i32(fd), 0)
		descriptor_map_result(0, prot, flags, if address == voidptr(C.MAP_FAILED) { -1 } else { 0 }, *location, expected)
		return address
	}
}

fn descriptor_map_protect(address voidptr, page usize, prot int, expected int) {
	unsafe {
		location := C.__errno_location()
		*location = 0
		result := C.mprotect(address, page, i32(prot))
		descriptor_map_result(1, prot, 0, int(result), *location, expected)
	}
}

fn descriptor_map_data(address voidptr) {
	check(unsafe { C.memcmp(address, c'MOUNT-OK', 8) == 0 }, 601)
}

fn descriptor_map_matrix(fd int, fresh int, noexec bool, page usize) {
	unsafe {
		for iteration in 0 .. 64 {
			for sharing in [int(C.MAP_PRIVATE), int(C.MAP_SHARED)]! {
				for location in 0 .. if fresh >= 0 { 2 } else { 1 } {
					selected := if location == 0 { fd } else { fresh }
					denied := if location == 0 { noexec } else { !noexec }
					executable := descriptor_map_open(selected, page, C.PROT_READ | C.PROT_EXEC, sharing,
						if denied { int(C.EPERM) } else { 0 })
					if !denied { descriptor_map_data(executable); check(C.munmap(executable, page) == 0, 601) }
					mapping := descriptor_map_open(selected, page, C.PROT_READ, sharing, 0)
					descriptor_map_data(mapping)
					descriptor_map_protect(mapping, page, C.PROT_READ | C.PROT_EXEC, if denied { int(C.EACCES) } else { 0 })
					descriptor_map_data(mapping)
					descriptor_map_protect(mapping, page, C.PROT_READ, 0)
					descriptor_map_protect(mapping, page, C.PROT_NONE, 0)
					descriptor_map_protect(mapping, page, C.PROT_READ | C.PROT_EXEC, if denied { int(C.EACCES) } else { 0 })
					descriptor_map_protect(mapping, page, C.PROT_READ, 0)
					descriptor_map_data(mapping)
					if sharing == C.MAP_SHARED {
						// A data-read-only description cannot gain shared writes.
						descriptor_map_protect(mapping, page, C.PROT_READ | C.PROT_WRITE, C.EACCES)
						descriptor_map_data(mapping)
					}
					check(C.munmap(mapping, page) == 0, 601)
				}
			}
		}
	}
}

fn descriptor_map_retained(fd int, fresh int, noexec bool, owner bool, page usize) {
	unsafe {
		original := descriptor_map_open(fd, page, C.PROT_READ, C.MAP_PRIVATE, 0)
		copied := if fresh >= 0 { descriptor_map_open(fresh, page, C.PROT_READ, C.MAP_PRIVATE, 0) } else { nil }
		child := C.fork()
		check(child >= 0, 602)
		if child == 0 {
			check(C.close(fd) == 0 && (fresh < 0 || C.close(fresh) == 0), 602)
			if !owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 602) }
			descriptor_map_protect(original, page, C.PROT_READ | C.PROT_EXEC, if noexec { int(C.EACCES) } else { 0 })
			descriptor_map_data(original)
			check(C.munmap(original, page) == 0, 602)
			if fresh >= 0 {
				descriptor_map_protect(copied, page, C.PROT_READ | C.PROT_EXEC, if noexec { 0 } else { int(C.EACCES) })
				descriptor_map_data(copied)
				check(C.munmap(copied, page) == 0, 602)
			}
			C._exit(0)
		}
		wait_child(child)
		// The mapping retains its limits after the final descriptor closes.
		check(C.close(fd) == 0 && (fresh < 0 || C.close(fresh) == 0), 602)
		descriptor_map_protect(original, page, C.PROT_READ | C.PROT_EXEC, if noexec { int(C.EACCES) } else { 0 })
		descriptor_map_data(original)
		check(C.munmap(original, page) == 0, 602)
		if fresh >= 0 {
			descriptor_map_protect(copied, page, C.PROT_READ | C.PROT_EXEC, if noexec { 0 } else { int(C.EACCES) })
			descriptor_map_data(copied)
			check(C.munmap(copied, page) == 0, 602)
		}
	}
}

fn descriptor_map_case(kind int) {
	unsafe {
		noexec := kind % 2 == 1
		unlinked := kind in [2, 3]
		owner := kind >= 4
		page_size := C.sysconf(C._SC_PAGESIZE)
		check(page_size >= 4096, 603)
		page := usize(page_size)
		check(C.unshare(int(C.CLONE_NEWNS)) == 0
			&& C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 603)
		mut root := [256]char{}
		mut target := [256]char{}
		check(C.snprintf(&root[0], 256, c'/tmp/mount-lifecycle/mm-%d', i32(kind)) > 0
			&& C.snprintf(&target[0], 256, c'%s/target', &root[0]) > 0, 603)
		directory(&root[0])
		check(C.mount(c'tmpfs', &root[0], c'tmpfs', usize(C.MS_STRICTATIME), nil) == 0
			&& C.syscall(int(C.SYS_fchmodat), i32(C.AT_FDCWD), &root[0], u32(0o755)) == 0, 603)
		marker(&target[0])
		original := C.open(&target[0], C.O_RDONLY)
		fd := int(C.syscall(int(C.SYS_dup), i32(original)))
		check(original >= 0 && fd >= 0 && C.close(original) == 0, 603)
		uid := if owner { u32(1000) } else { u32(0) }
		check(C.syscall(int(C.SYS_fchown), i32(fd), uid, uid) == 0
			&& C.syscall(int(C.SYS_fchmod), i32(fd), u32(0o600)) == 0, 603)
		if unlinked { check(C.unlink(&target[0]) == 0, 603) }
		mount_statfs_policy(&root[0], if noexec { u64(C.MS_NOEXEC) } else { u64(0) })
		check(C.unshare(int(C.CLONE_NEWNS)) == 0, 604)
		mount_statfs_policy(&root[0], if noexec { u64(0) } else { u64(C.MS_NOEXEC) })
		fresh := if unlinked { -1 } else { C.open(&target[0], C.O_RDONLY) }
		check(unlinked || fresh >= 0, 604)
		report := mount_statfs_read(fd, nil, mount_statfs_expected(if noexec { u64(C.MS_NOEXEC) } else { u64(0) }))
		copied_report := mount_statfs_read(-1, &root[0], mount_statfs_expected(if noexec { u64(0) } else { u64(C.MS_NOEXEC) }))
		mount_statfs_same(report, copied_report)
		if owner { check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 604) }
		mut before := C.stat{}
		check(C.fstat(fd, &before) == 0, 604)
		descriptor_map_matrix(fd, fresh, noexec, page)
		mut after := C.stat{}
		check(C.fstat(fd, &after) == 0 && (!unlinked || after.st_nlink == 0), 605)
		timestamp_identity(&after, &before)
		mut bytes := [8]u8{}
		check(C.read(fd, &bytes[0], 8) == 8 && C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 605)
		descriptor_map_retained(fd, fresh, noexec, owner, page)
	}
}

fn descriptor_map_cases(selected int) {
	unsafe {
		for kind in 0 .. 6 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 606)
			if child == 0 { descriptor_map_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT DESCMAP CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT DESCMAP: PASS')
		C.fflush(nil)
	}
}
