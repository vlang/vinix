// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual PPC musl ABI, including stdio's readv/writev paths.
module main

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/random.h>
#include <dirent.h>

struct C.stat { st_mode u32 st_size i64 st_uid u32 }
struct C.dirent { d_name [256]char }
fn C.printf(&char, ...voidptr) i32
fn C.fflush(voidptr) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, uint) i32
fn C.write(i32, voidptr, uint) i32
fn C.fsync(i32) i32
fn C.fcntl(i32, i32, ...voidptr) i32
fn C.lseek(i32, i64, i32) i64
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.fstat(i32, &C.stat) i32
fn C.lstat(&char, &C.stat) i32
fn C.rename(&char, &char) i32
fn C.unlink(&char) i32
fn C.rmdir(&char) i32
fn C.symlink(&char, &char) i32
fn C.readlink(&char, &char, uint) i32
fn C.getrandom(voidptr, uint, u32) i32
fn C.fopen(&char, &char) voidptr
fn C.fread(voidptr, uint, uint, voidptr) uint
fn C.fwrite(voidptr, uint, uint, voidptr) uint
fn C.fclose(voidptr) i32
fn C.opendir(&char) voidptr
fn C.readdir(voidptr) &C.dirent
fn C.closedir(voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.__errno_location() &i32

fn fail(stage &char) {
	C.printf(c'VINIX-PPC: FAIL storage ABI %s errno %d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	for {}
}

@[export: 'main']
fn entry() i32 {
	unsafe {
		mut counter := u8(0)
		old := C.open(c'/root/storage-round', C.O_RDONLY)
		if old >= 0 {
			if C.read(old, &counter, 1) != 1 || counter != 1 || C.close(old) != 0 { fail(c'reboot contents') }
		}
		counter++
		if C.mkdir(c'/root/abi', 0o700) != 0 { fail(c'mkdir') }
		fd := C.open(c'/root/abi/new', C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
		if fd < 0 { fail(c'create') }
		if C.fcntl(fd, C.F_GETFD) != 1 { fail(c'cloexec') }
		if C.open(c'/root/abi/new', C.O_CREAT | C.O_EXCL | C.O_WRONLY, 0o600) != -1 || *C.__errno_location() != 17 { fail(c'exclusive') }
		if C.chmod(c'/root/abi/new', 0o600) != 0 { fail(c'chmod') }
		mut data := [4096]u8{}
		for i in 0 .. 4096 { data[i] = u8(i * 17 + 3) }
		for _ in 0 .. 16 { if C.write(fd, &data[0], 4096) != 4096 { fail(c'indirect write') } }
		mut st := C.stat{}
		if C.fstat(fd, &st) != 0 || st.st_mode != 0x8180 || st.st_size != 65536 || st.st_uid != 0 { fail(c'statx ABI') }
		if C.lseek(fd, 12 * 4096 - 2, 0) != 12 * 4096 - 2 { fail(c'llseek') }
		mut readback := [8]u8{}
		if C.read(fd, &readback[0], 8) != 8 { fail(c'boundary read') }
		for i in 0 .. 8 { if readback[i] != u8((4094 + i) * 17 + 3) { fail(c'indirect data') } }
		if C.read(fd, voidptr(1), 1) != -1 || *C.__errno_location() != 14 { fail(c'bad pointer') }
		if C.fsync(fd) != 0 || C.rename(c'/root/abi/new', c'/root/abi/saved') != 0 { fail(c'rename sync') }
		if C.symlink(c'/root/abi/saved', c'/root/abi/link') != 0 || C.lstat(c'/root/abi/link', &st) != 0 || st.st_mode & 0xf000 != 0xa000 { fail(c'symlink stat') }
		mut target := [64]u8{}
		if C.readlink(c'/root/abi/link', &char(&target[0]), 64) != 15 { fail(c'readlink') }
		if C.open(c'/root/abi/link', C.O_RDONLY | C.O_NOFOLLOW) != -1 || *C.__errno_location() != 40 { fail(c'nofollow') }
		dir := C.opendir(c'/root/abi')
		if dir == nil { fail(c'opendir') }
		mut found := false
		for {
			e := C.readdir(dir)
			if e == nil { break }
			if C.strcmp(&e.d_name[0], c'saved') == 0 { found = true }
		}
		if !found || C.closedir(dir) != 0 { fail(c'getdents64') }
		if C.rmdir(c'/root/abi') != -1 || *C.__errno_location() != 39 { fail(c'nonempty') }
		if C.unlink(c'/root/abi/saved') != 0 || C.lseek(fd, 0, 0) != 0 || C.read(fd, &readback[0], 8) != 8 || C.close(fd) != 0 { fail(c'unlink-open') }
		if C.unlink(c'/root/abi/link') != 0 || C.rmdir(c'/root/abi') != 0 { fail(c'cleanup') }
		rng := C.fopen(c'/dev/urandom', c'rb')
		if rng == nil || C.fread(&target[0], 1, 64, rng) != 64 || C.fclose(rng) != 0 { fail(c'stdio random readv') }
		if C.getrandom(&data[0], 64, 0) != 64 { fail(c'getrandom') }
		mut different := false
		for i in 0 .. 64 { if target[i] != data[i] { different = true } }
		if !different { fail(c'random repetition') }
		file := C.fopen(c'/root/storage-round', c'wb')
		if file == nil || C.fwrite(&counter, 1, 1, file) != 1 || C.fclose(file) != 0 { fail(c'stdio writev') }
		root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY)
		if root < 0 || C.fsync(root) != 0 || C.close(root) != 0 { fail(c'directory fsync') }
		C.printf(c'VINIX-PPC: PASS storage ABI round %d\n', i32(counter))
		C.fflush(nil)
		for {}
		return 0
	}
}
