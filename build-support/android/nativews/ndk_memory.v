// SPDX-License-Identifier: GPL-2.0-or-later
// NDK anonymous shared memory backed by Vinix's real memfd implementation.
@[translated]
module atlframework

#include <sys/stat.h>

struct C.stat {
	st_size i64
}
fn C.memfd_create(&char, u32) i32
fn C.fstat(i32, &C.stat) i32
fn C.__errno_location() &i32

@[export: 'ASharedMemory_create']
pub fn ws_memory_create(name &char, size usize) i32 {
	unsafe {
		if size == 0 || size > usize(0x7fffffffffffffff) {
			*C.__errno_location() = 22
			return -22
		}
		fd := C.memfd_create(if name == nil { c'ASharedMemory' } else { name }, 1 | 2)
		if fd < 0 { return -1 }
		// Keep the region's size fixed, like ashmem/Android's memfd provider.
		if C.ftruncate(fd, i64(size)) != 0 || C.fcntl(fd, 1033, 2 | 4) != 0 {
			saved := *C.__errno_location()
			C.close(fd)
			*C.__errno_location() = saved
			return -1
		}
		return fd
	}
}

@[export: 'ASharedMemory_getSize']
pub fn ws_memory_size(fd i32) usize {
	unsafe {
		mut info := C.stat{}
		seals := C.fcntl(fd, 1034)
		if seals < 0 || seals & 6 != 6 || C.fstat(fd, &info) != 0 || info.st_size < 0 { return 0 }
		return usize(info.st_size)
	}
}
