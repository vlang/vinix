// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native EXT2 read-ahead policy, data and retention workload.
@[translated; has_globals]
module cachefixture

#include <cache-native-abi.h>

@[typedef]
struct C.FILE {}

struct C.statfs {
	f_type isize
}

@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global buffer [16384]u8

fn C.printf(&char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.fclose(&C.FILE) i32
fn C.setbuf(&C.FILE, voidptr)
fn C.strcmp(&char, &char) i32
fn C.statfs(&char, &C.statfs) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64
fn C.posix_fadvise(i32, i64, i64, i32) i32
fn C.fsync(i32) i32
fn C.puts(&char) i32
fn C.pause() i32

fn check(ok bool, line i32) {
	if !ok {
		unsafe { C.printf(c'READAHEAD FAIL line=%d errno=%d FAIL END\n', line, C.errno) }
		for { C.pause() }
	}
}

fn metric(name &char) isize {
	unsafe {
		file := C.fopen(c'/proc/meminfo', c'r')
		check(file != nil, 15)
		mut line := [256]char{}
		mut key := [64]char{}
		mut value := isize(0)
		mut found := isize(-1)
		for C.fgets(&line[0], i32(sizeof(line)), file) != nil {
			if C.sscanf(&line[0], c'%63s %ld', &key[0], &value) == 2 && C.strcmp(&key[0], name) == 0 {
				found = value
			}
		}
		C.fclose(file)
		check(found >= 0, 19)
		return found
	}
}

fn bytes(fd i32, offset i64, count usize, positional i32) {
	unsafe {
		check(count <= sizeof(buffer), 24)
		n := if positional != 0 { C.pread(fd, &buffer[0], count, offset) } else { C.read(fd, &buffer[0], count) }
		check(n == isize(count), 26)
		for i := usize(0); i < count; i++ { check(buffer[i] == u8((offset + i64(i)) % 251), 27) }
	}
}

fn cold(fd i32, advice i32) {
	check(C.posix_fadvise(fd, 0, 0, C.POSIX_FADV_DONTNEED) == 0, 32)
	check(C.posix_fadvise(fd, 0, 0, advice) == 0, 33)
	check(C.lseek(fd, 0, C.SEEK_SET) == 0, 34)
}

fn window(fd i32, advice i32, positional i32) isize {
	cold(fd, advice)
	before := metric(c'Cached:')
	bytes(fd, 0, 1024, positional)
	first := metric(c'Cached:')
	bytes(fd, 1024, 1024, positional)
	second := metric(c'Cached:')
	check(first - before < 32, 45)
	unsafe { C.printf(c'READAHEAD advice=%d positional=%d first_kb=%ld second_kb=%ld\n', advice, positional, first - before, second - first) }
	if positional != 0 { check(C.lseek(fd, 0, C.SEEK_CUR) == 0, 47) }
	return second - first
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		$if amd64 {
			serial := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
			if serial >= 0 { C.dup2(serial, 1); C.dup2(serial, 2); C.close(serial) }
		}
		C.puts(c'READAHEAD START')
		mut filesystem := C.statfs{}
		check(C.statfs(c'/root', &filesystem) == 0 && filesystem.f_type == 0xef53, 60)
		fd := C.open(c'/root/readahead-data', C.O_CREAT | C.O_TRUNC | C.O_RDWR, i32(0o600))
		check(fd >= 0, 61)
		file_bytes := i64(384 * 1024 + 137)
		for offset := i64(0); offset < file_bytes; {
			amount := if file_bytes - offset < i64(sizeof(buffer)) { usize(file_bytes - offset) } else { sizeof(buffer) }
			for i := usize(0); i < amount; i++ { buffer[i] = u8((offset + i64(i)) % 251) }
			check(C.write(fd, &buffer[0], amount) == isize(amount), 65)
			offset += i64(amount)
		}
		check(C.fsync(fd) == 0, 67)
		check(window(fd, C.POSIX_FADV_RANDOM, 0) < 32, 68)
		normal := window(fd, C.POSIX_FADV_NORMAL, 0)
		check(normal >= 64, 69)
		sequential := window(fd, C.POSIX_FADV_SEQUENTIAL, 0)
		check(sequential >= normal + 64, 70)
		check(window(fd, C.POSIX_FADV_NORMAL, 1) >= 64, 71)
		cold(fd, C.POSIX_FADV_RANDOM)
		mut before := metric(c'Cached:')
		check(C.posix_fadvise(fd, 0, 128 * 1024, C.POSIX_FADV_WILLNEED) == 0, 74)
		check(metric(c'Cached:') >= before + 64, 75)
		C.puts(c'READAHEAD PASS: sequential windows, random suppression and explicit hints')
		cold(fd, C.POSIX_FADV_RANDOM)
		alias := C.dup(fd)
		check(alias >= 0, 79)
		check(C.posix_fadvise(alias, 0, 0, C.POSIX_FADV_NORMAL) == 0, 80)
		bytes(fd, 0, 1024, 0)
		before = metric(c'Cached:')
		bytes(alias, 1024, 1024, 0)
		check(metric(c'Cached:') >= before + 64, 82)
		check(C.lseek(fd, 0, C.SEEK_CUR) == 2048, 83)
		check(C.close(alias) == 0, 84)
		before = metric(c'Cached:')
		check(C.lseek(fd, 320 * 1024, C.SEEK_SET) == 320 * 1024, 86)
		bytes(fd, 320 * 1024, 1024, 0)
		check(metric(c'Cached:') - before < 32, 87)
		check(C.posix_fadvise(fd, 0, 0, C.POSIX_FADV_RANDOM) == 0, 88)
		for offset := i64(0); offset < file_bytes; {
			amount := if file_bytes - offset < i64(sizeof(buffer)) { usize(file_bytes - offset) } else { sizeof(buffer) }
			bytes(fd, offset, amount, 1)
			offset += i64(amount)
		}
		check(C.pread(fd, &buffer[0], sizeof(buffer), file_bytes) == 0, 93)
		C.puts(c'READAHEAD PASS: shared descriptions, offset resets and exact tail bytes')
		// The original first cohort warms metadata; the second retains its
		// unchanged 16 KiB tolerance after 200 clustered-fill/discard cycles.
		for round := i32(0); round < 2; round++ {
			cold(fd, C.POSIX_FADV_NORMAL)
			slab := metric(c'Slab:')
			for _ in 0 .. 200 {
				cold(fd, C.POSIX_FADV_NORMAL)
				bytes(fd, 0, 1024, 0)
				bytes(fd, 1024, 1024, 0)
			}
			cold(fd, C.POSIX_FADV_NORMAL)
			after := metric(c'Slab:')
			C.printf(c'READAHEAD retained round=%d slab_before_kb=%ld slab_after_kb=%ld\n', round, slab, after)
			if round == 1 { check(after <= slab + 16, 108) }
		}
		check(C.close(fd) == 0, 110)
		C.puts(c'READAHEAD DONE pass ino=0')
		for { C.pause() }
	}
}
