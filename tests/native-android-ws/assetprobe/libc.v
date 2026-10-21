// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module assetprobe

fn C.open(&char, i32, ...i32) i32
fn C.close(i32) i32
fn C.unlink(&char) i32
fn C.write(i32, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64
fn C.__pread_chk(i32, voidptr, usize, i64, usize) isize
fn C.__pread64_chk(i32, voidptr, usize, i64, usize) isize
fn C.android_get_device_api_level() i32
fn C.__system_property_get(&char, &char) i32
fn C.mallopt(i32, i32) i32
fn C.ASharedMemory_create(&char, usize) i32
fn C.ASharedMemory_getSize(i32) usize
fn C.dup(i32) i32
fn C.ftruncate(i32, i64) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32

fn shared_memory_check() bool {
	unsafe {
		if C.ASharedMemory_create(nil, 0) >= 0
			|| C.ASharedMemory_create(nil, usize(0xffffffffffffffff)) >= 0
			|| C.ASharedMemory_getSize(-1) != 0 { return false }
		fd := C.ASharedMemory_create(c'vinix-bootstrap-shared', 16384)
		if fd < 0 { return false }
		alias := C.dup(fd)
		if alias < 0 { C.close(fd); return false }
		defer { C.close(alias) }
		if C.ASharedMemory_getSize(fd) != 16384 || C.ftruncate(fd, 32768) == 0 {
			C.close(fd)
			return false
		}
		first := &u8(C.mmap(nil, 16384, 3, 1, fd, 0))
		C.close(fd)
		if voidptr(first) == voidptr(usize(0xffffffffffffffff)) { return false }
		defer { C.munmap(first, 16384) }
		second := &u8(C.mmap(nil, 16384, 3, 1, alias, 0))
		if voidptr(second) == voidptr(usize(0xffffffffffffffff)) { return false }
		defer { C.munmap(second, 16384) }
		if first[0] != 0 || first[16383] != 0 { return false }
		first[0] = 42
		second[16383] = 91
		return second[0] == 42 && first[16383] == 91 && C.ASharedMemory_getSize(alias) == 16384
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeLibc']
pub fn libc_check(e voidptr, class voidptr) u8 {
	unsafe {
		fd := C.open(c'/tmp/vinix-bootstrap-pread', 2 | 64 | 512, 384)
		if fd < 0 { return 0 }
		C.unlink(c'/tmp/vinix-bootstrap-pread')
		defer { C.close(fd) }
		if C.write(fd, c'abcdef', 6) != 6 { return 0 }
		mut bytes := [8]u8{}
		if C.__pread_chk(fd, &bytes[0], 4, 2, 8) != 4
			|| bytes[0] != `c` || bytes[3] != `f` || C.lseek(fd, 0, 1) != 6
			|| C.__pread64_chk(fd, &bytes[0], 8, 4, 8) != 2
			|| C.__pread_chk(fd, &bytes[0], 0, 0, 0) != 0
			|| C.__pread_chk(-1, &bytes[0], 1, 0, 8) != -1 { return 0 }
		mut property := [92]char{}
		if C.__system_property_get(c'ro.build.version.sdk', &property[0]) <= 0 { return 0 }
		mut level := i32(0)
		for i := 0; i < 91 && property[i] >= `0` && property[i] <= `9`; i++ {
			level = level * 10 + i32(property[i] - `0`)
		}
		return u8(level > 0 && C.android_get_device_api_level() == level && C.mallopt(-9999, 0) == 0 && shared_memory_check())
	}
}
