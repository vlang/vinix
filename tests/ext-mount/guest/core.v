// SPDX-License-Identifier: GPL-2.0-or-later
module guest

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <string.h>
#include <errno.h>

fn C.printf(&char, ...) int
fn C.puts(&char) int
fn C.setbuf(voidptr, voidptr)
fn C.open(&char, int, ...) int
fn C.close(int) int
fn C.dup2(int, int) int
fn C.fflush(voidptr) int
fn C.read(int, voidptr, usize) isize
fn C.pread(int, voidptr, usize, i64) isize
fn C.pwrite(int, voidptr, usize, i64) isize
fn C.write(int, voidptr, usize) isize
fn C.mkdir(&char, u32) int
fn C.mount(&char, &char, &char, usize, voidptr) int
fn C.umount(&char) int
fn C.readlink(&char, voidptr, usize) isize
fn C.memcmp(voidptr, voidptr, usize) int
fn C.mmap(voidptr, usize, int, int, int, i64) voidptr
fn C.munmap(voidptr, usize) int
fn C.__errno_location() &int
fn C.pause() int

fn check(ok bool, line int) {
	if !ok {
		C.printf(c'EXT MOUNT FAIL line=%d errno=%d\n', line, unsafe { *C.__errno_location() })
		C.fflush(unsafe { nil })
		for { C.pause() }
	}
}

fn contents(read_only bool) {
	fd := C.open(c'/mnt/marker', 0)
	check(fd >= 0, 1)
	mut data := [256]u8{}
	check(C.read(fd, unsafe { &data[0] }, 256) == 22, 2)
	check(C.memcmp(unsafe { &data[0] }, c'external Linux volume\n', 22) == 0, 3)
	if read_only {
		C.printf(c'EXT4 READ /marker: %.*s', 22, unsafe { &char(&data[0]) })
		C.fflush(unsafe { nil })
	}
	check(C.close(fd) == 0, 4)
	check(C.readlink(c'/mnt/short-link', unsafe { &char(&data[0]) }, 256) == 6, 5)
	check(C.memcmp(unsafe { &data[0] }, c'marker', 6) == 0, 6)
	fd2 := C.open(c'/mnt/fragmented', 0)
	check(fd2 >= 0, 7)
	for i in 0 .. 9 {
		check(C.pread(fd2, unsafe { &data[0] }, 256, i64(i * 8192)) == 256, 8)
		for j in 0 .. 256 { check(unsafe { data[j] } == u8(i + 1), 9) }
		if i < 8 {
			check(C.pread(fd2, unsafe { &data[0] }, 256, i64(i * 8192 + 4096)) == 256, 10)
			for j in 0 .. 256 { check(unsafe { data[j] } == 0, 11) }
		}
	}
	mapping := C.mmap(unsafe { nil }, 4096, 1, 2, fd2, 0)
	check(mapping != voidptr(u64(-1)), 12)
	check(unsafe { &u8(mapping)[0] } == 1, 13)
	check(C.munmap(mapping, 4096) == 0, 14)
	check(C.close(fd2) == 0, 15)
	writable := C.open(c'/mnt/marker', 1)
	if read_only {
		check(writable == -1 && unsafe { *C.__errno_location() } == 30, 16)
		check(C.mkdir(c'/mnt/denied', 0o755) == -1 && unsafe { *C.__errno_location() } == 30, 17)
	} else {
		check(writable >= 0, 18)
		check(C.write(writable, c'EXT2 write persisted!\n', 22) == 22, 19)
		check(C.close(writable) == 0, 20)
	}
}

@[export: 'main']
pub fn entry(_argc int, _argv &&char) int {
	$if amd64 {
		serial := C.open(c'/dev/com1', 1)
		if serial >= 0 {
			C.dup2(serial, 1)
			C.dup2(serial, 2)
			C.close(serial)
		}
	}
	C.puts(c'EXT MOUNT START')
	C.fflush(unsafe { nil })
	check(C.mkdir(c'/mnt', 0o755) == 0, 21)
	// The runner supplies external data volumes as partitions on AHCI for
	// x86, matching the ThinkPad's /dev/sd0-2 path, and VirtIO on ARM.
	ext2_device := $if amd64 { &char(c'/dev/sd0-0') } $else { &char(c'/dev/vda') }
	ext4_device := $if amd64 { &char(c'/dev/sd1-0') } $else { &char(c'/dev/vdb') }
	check(C.mount(ext2_device, c'/mnt', c'ext2', 0, unsafe { nil }) == 0, 22)
	contents(false)
	check(C.umount(c'/mnt') == 0, 23)
	// A second mount reuses the same device's cache and can read the write.
	check(C.mount(ext2_device, c'/mnt', c'ext2', 0, unsafe { nil }) == 0, 24)
	fd := C.open(c'/mnt/marker', 0)
	mut data := [32]u8{}
	check(fd >= 0 && C.read(fd, unsafe { &data[0] }, 32) == 22, 25)
	check(C.memcmp(unsafe { &data[0] }, c'EXT2 write persisted!\n', 22) == 0, 26)
	check(C.close(fd) == 0 && C.umount(c'/mnt') == 0, 27)
	check(C.mount(ext4_device, c'/mnt', c'ext4', 1, unsafe { nil }) == 0, 28)
	contents(true)
	check(C.mount(ext4_device, c'/mnt', c'ext4', 32, unsafe { nil }) == -1
		&& unsafe { *C.__errno_location() } == 30, 29)
	check(C.umount(c'/mnt') == 0, 30)
	// A requested writable ext4 mount still publishes a read-only root.
	check(C.mount(ext4_device, c'/mnt', c'ext4', 0, unsafe { nil }) == 0, 31)
	check(C.open(c'/mnt/marker', 1) == -1 && unsafe { *C.__errno_location() } == 30, 32)
	check(C.umount(c'/mnt') == 0, 33)
	bad_device := $if amd64 { &char(c'/dev/sd2-0') } $else { &char(c'/dev/vdc') }
	raw := C.open(bad_device, 2)
	check(raw >= 0, 34)
	// Geometry probes successfully, but the damaged root cannot be mounted.
	// Its retained cache must still exclude raw writes at securelevel 1.
	check(C.mount(bad_device, c'/mnt', c'ext2', 0, unsafe { nil }) == -1
		&& unsafe { *C.__errno_location() } == 5, 35)
	level := C.open(c'/proc/sys/kernel/securelevel', 1)
	check(level >= 0 && C.write(level, c'1\n', 2) == 2 && C.close(level) == 0, 36)
	zero := [512]u8{}
	check(C.pwrite(raw, unsafe { &zero[0] }, 512, 1024) == -1
		&& unsafe { *C.__errno_location() } == 1, 37)
	check(C.close(raw) == 0, 38)
	C.puts(c'EXT MOUNT PASS')
	C.fflush(unsafe { nil })
	for { C.pause() }
	return 0
}
