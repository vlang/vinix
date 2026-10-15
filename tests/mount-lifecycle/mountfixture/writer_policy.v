// SPDX-License-Identifier: GPL-2.0-or-later
module mountfixture

#include <sys/mman.h>
#include <sys/resource.h>

fn mount_writer_remount(path &char, readonly bool, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	flags := usize(C.MS_REMOUNT | C.MS_BIND) | if readonly { usize(C.MS_RDONLY) } else { usize(0) }
	result := C.mount(c'none', path, unsafe { nil }, flags, unsafe { nil })
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT WRITER RESULT: readonly=%d result=%d errno=%d expected=%d\n', i32(if readonly { 1 } else { 0 }), i32(result), failure, i32(expected)) }
	C.fflush(unsafe { nil })
	check(false, 490)
}

fn mount_writer_truncate(fd int, length i64, expected int) {
	location := C.__errno_location()
	unsafe { *location = 0 }
	result := C.syscall(int(C.SYS_ftruncate), i32(fd), length)
	failure := unsafe { *location }
	if (expected == 0 && result == 0) || (expected != 0 && result == -1 && failure == expected) { return }
	unsafe { C.printf(c'MOUNT WRITER TRUNCATE: size=%ld result=%ld errno=%d expected=%d\n', length, i64(result), failure, i32(expected)) }
	C.fflush(unsafe { nil })
	check(false, 491)
}

fn mount_writer_sizes(fd int, reader int) {
	unsafe {
		mut original := C.stat{}
		check(C.fstat(fd, &original) == 0 && C.syscall(int(C.SYS_lseek), i32(fd), i64(3), i32(C.SEEK_SET)) == 3, 492)
		for _ in 0 .. 16 {
			for length in [i64(0), 32, 8]! {
				mount_writer_truncate(fd, length, 0)
				mut after := C.stat{}
				check(C.fstat(fd, &after) == 0 && after.st_size == length && after.st_dev == original.st_dev
					&& after.st_ino == original.st_ino && after.st_mode == original.st_mode && after.st_uid == original.st_uid
					&& after.st_gid == original.st_gid && after.st_nlink == original.st_nlink
					&& C.syscall(int(C.SYS_lseek), i32(fd), i64(0), i32(C.SEEK_CUR)) == 3, 492)
				if length == 32 {
					mut zeros := [32]u8{}
					check(C.syscall(int(C.SYS_pread64), i32(reader), &zeros[0], usize(32), i64(0)) == 32, 492)
					for value in zeros { check(value == 0, 492) }
				}
			}
			mut bytes := [8]u8{}
			check(C.syscall(int(C.SYS_pwrite64), i32(fd), c'MOUNT-OK', usize(8), i64(0)) == 8
				&& C.syscall(int(C.SYS_pread64), i32(reader), &bytes[0], usize(8), i64(0)) == 8
				&& C.memcmp(&bytes[0], c'MOUNT-OK', 8) == 0, 492)
		}
		mount_writer_truncate(fd, -1, C.EINVAL)
	}
}

struct MountWriterPeer { path [256]char mut: fd int }

fn mount_writer_retired(argument voidptr) voidptr {
	unsafe {
		mut peer := &MountWriterPeer(argument)
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'tmpfs', &peer.path[0], c'tmpfs', 0, nil) == 0, 493)
		mut path := [512]char{}
		check(C.snprintf(&path[0], 512, c'%s/marker', &peer.path[0]) > 0, 493)
		marker(&path[0])
		peer.fd = C.open(&path[0], C.O_RDWR)
		check(peer.fd >= 0, 493)
		return nil
	}
}

fn mount_writer_case(kind int) {
	unsafe {
		check(C.unshare(int(C.CLONE_NEWNS)) == 0 && C.mount(c'none', c'/', nil, usize(C.MS_PRIVATE | C.MS_REC), nil) == 0, 494)
		mut base := [256]char{}
		mut source := [256]char{}
		mut alias := [256]char{}
		mut path := [512]char{}
		check(C.snprintf(&base[0], 256, c'/tmp/mount-lifecycle/wr-%d', i32(kind)) > 0
			&& C.snprintf(&source[0], 256, c'%s/source', &base[0]) > 0 && C.snprintf(&alias[0], 256, c'%s/alias', &base[0]) > 0, 494)
		directory(&base[0]); directory(&source[0]); directory(&alias[0])
		check(C.mount(c'tmpfs', &source[0], c'tmpfs', 0, nil) == 0 && C.snprintf(&path[0], 512, c'%s/marker', &source[0]) > 0, 494)
		marker(&path[0])
		check(C.mount(&source[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 494)
		reader := C.open(&path[0], C.O_RDONLY)
		check(reader >= 0, 494)
		if kind <= 1 {
			mut alternate := [512]char{}
			check(C.snprintf(&alternate[0], 512, c'%s/marker', &alias[0]) > 0, 495)
			active := if kind == 0 { &char(&source[0]) } else { &char(&alias[0]) }
			other := if kind == 0 { &char(&alias[0]) } else { &char(&source[0]) }
			name := if kind == 0 { &char(&path[0]) } else { &char(&alternate[0]) }
			for flags in [int(C.O_WRONLY), int(C.O_RDWR)]! {
				fd := C.open(name, flags)
				check(fd >= 0, 495)
				mount_writer_remount(active, true, C.EBUSY)
				mount_writer_remount(other, true, 0)
				mount_writer_sizes(fd, reader)
				check(C.close(fd) == 0, 495)
				mount_writer_remount(active, true, 0)
				mount_writer_remount(active, false, 0); mount_writer_remount(other, false, 0)
			}
		} else if kind == 2 {
			fd := C.open(&path[0], C.O_RDWR)
			check(fd >= 0 && C.unshare(int(C.CLONE_NEWNS)) == 0, 496)
			// A copy has no writers of its own. The inherited description
			// still names the original writable mount and may truncate it.
			mount_writer_remount(&source[0], true, 0)
			mount_writer_sizes(fd, reader)
			check(C.open(&path[0], C.O_RDWR) == -1 && *C.__errno_location() == C.EROFS && C.close(fd) == 0, 496)
		} else if kind == 3 {
			for _ in 0 .. 16 {
				fd := C.open(&path[0], C.O_RDWR)
				copy := C.syscall(int(C.SYS_dup), i32(fd))
				check(fd >= 0 && copy >= 0 && C.close(fd) == 0, 497)
				mount_writer_remount(&source[0], true, C.EBUSY)
				mount_writer_sizes(int(copy), reader)
				check(C.close(int(copy)) == 0, 497)
				mount_writer_remount(&source[0], true, 0); mount_writer_remount(&source[0], false, 0)
			}
		} else if kind == 4 {
			fd := C.open(&path[0], C.O_RDWR)
			mut ready := [2]i32{}
			mut proceed := [2]i32{}
			check(fd >= 0 && C.pipe(&ready[0]) == 0 && C.pipe(&proceed[0]) == 0, 498)
			child := C.fork()
			check(child >= 0, 498)
			mut signal_byte := u8(0)
			if child == 0 {
				check(C.close(ready[0]) == 0 && C.close(proceed[1]) == 0 && C.write(ready[1], c'R', 1) == 1
					&& C.read(proceed[0], &signal_byte, 1) == 1, 498)
				check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 498)
				mount_writer_remount(&source[0], true, C.EPERM)
				truncate_result(&path[0], 0, C.EACCES)
				mount_writer_sizes(fd, reader)
				C._exit(0)
			}
			check(C.close(ready[1]) == 0 && C.close(proceed[0]) == 0 && C.close(fd) == 0 && C.read(ready[0], &signal_byte, 1) == 1, 498)
			mount_writer_remount(&source[0], true, C.EBUSY)
			check(C.write(proceed[1], c'G', 1) == 1, 498)
			wait_child(child)
			check(C.close(ready[0]) == 0 && C.close(proceed[1]) == 0, 498)
			mount_writer_remount(&source[0], true, 0)
		} else if kind == 5 {
			for sharing in [int(C.MAP_PRIVATE), int(C.MAP_SHARED)]! {
				fd := C.open(&path[0], C.O_RDWR)
				check(fd >= 0, 499)
				mount_writer_truncate(fd, 4096, 0)
				address := C.syscall(int(C.SYS_mmap), voidptr(0), usize(4096), i32(C.PROT_READ | C.PROT_WRITE), i32(sharing), i32(fd), i64(0))
				check(address != -1 && C.close(fd) == 0 && *&u8(voidptr(address)) == `M`, 499)
				mount_writer_remount(&source[0], true, C.EBUSY)
				check(C.syscall(int(C.SYS_munmap), voidptr(address), usize(4096)) == 0, 499)
				mount_writer_remount(&source[0], true, 0); mount_writer_remount(&source[0], false, 0)
			}
		} else if kind == 6 {
			mut saved := [2]u64{}
			check(C.syscall(int(C.SYS_prlimit64), i32(0), i32(C.RLIMIT_NOFILE), voidptr(0), &saved[0]) == 0, 500)
			mut limit := [u64(0), saved[1]]!
			for _ in 0 .. 16 {
				check(C.syscall(int(C.SYS_prlimit64), i32(0), i32(C.RLIMIT_NOFILE), &limit[0], voidptr(0)) == 0
					&& C.open(&path[0], C.O_WRONLY) == -1 && *C.__errno_location() == C.EMFILE
					&& C.syscall(int(C.SYS_prlimit64), i32(0), i32(C.RLIMIT_NOFILE), &saved[0], voidptr(0)) == 0, 500)
				mount_writer_remount(&source[0], true, 0); mount_writer_remount(&source[0], false, 0)
			}
		} else if kind == 7 {
			check(C.umount2(&alias[0], 0) == 0 && C.syscall(int(C.SYS_unlinkat), i32(C.AT_FDCWD), &alias[0], i32(C.AT_REMOVEDIR)) == 0, 501)
			marker(&alias[0])
			check(C.mount(&path[0], &alias[0], nil, usize(C.MS_BIND), nil) == 0, 501)
			fd := C.open(&alias[0], C.O_RDWR)
			check(fd >= 0, 501)
			mount_writer_remount(&alias[0], true, C.EBUSY); mount_writer_remount(&source[0], true, 0)
			mount_writer_sizes(fd, reader)
			check(C.close(fd) == 0, 501)
			mount_writer_remount(&alias[0], true, 0)
		} else if kind == 8 {
			fd := C.open(&path[0], C.O_RDONLY | C.O_TRUNC)
			check(fd >= 0, 502)
			mount_writer_remount(&source[0], true, 0)
			mount_writer_truncate(fd, 0, C.EINVAL); mount_writer_truncate(fd, -1, C.EINVAL)
			path_fd := C.open(&path[0], C.O_PATH | C.O_WRONLY)
			check(path_fd >= 0, 502)
			mount_writer_truncate(path_fd, 0, C.EBADF); mount_writer_truncate(path_fd, -1, C.EINVAL)
			mount_writer_remount(&source[0], true, 0)
			check(C.close(fd) == 0 && C.close(path_fd) == 0, 502)
		} else {
			mut retired := [256]char{}
			check(C.snprintf(&retired[0], 256, c'%s/retired', &base[0]) > 0, 503)
			directory(&retired[0])
			peer := &MountWriterPeer(C.alloca(sizeof(MountWriterPeer)))
			*peer = MountWriterPeer{path: retired, fd: -1}
			mut handle := C.pthread_t{}
			check(C.pthread_create(&handle, nil, mount_writer_retired, peer) == 0 && C.pthread_join(handle, nil) == 0, 503)
			mount_writer_remount(&source[0], true, 0)
			mount_writer_sizes(peer.fd, peer.fd)
			check(C.close(peer.fd) == 0, 503)
		}
		check(C.close(reader) == 0, 504)
	}
}

fn mount_writer_cases(selected int) {
	unsafe {
		for kind in 0 .. 10 {
			if selected >= 0 && selected != kind { continue }
			child := C.fork()
			check(child >= 0, 505)
			if child == 0 { mount_writer_case(kind); C._exit(0) }
			wait_child(child)
			C.printf(c'MOUNT WRITER CASE: %d PASS\n', i32(kind))
			C.fflush(nil)
		}
		C.puts(c'MOUNT WRITERS: PASS')
		C.fflush(nil)
	}
}
