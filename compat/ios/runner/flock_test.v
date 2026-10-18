// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

#include <dlfcn.h>
fn C.dlsym(voidptr, &char) voidptr
fn C.mkstemp(&u8) i32

type FlockTestCall = fn (i32, i32) i32
type FlockTestRaw = fn (u64, u64, u64) i32

struct FlockTestFile {
	first i32
	other i32
	path string
}

fn flock_test_error(call FlockTestCall, fd i32, flags i32, expected i32) {
	darwin_set_errno(77)
	assert call(fd, flags) == -1
	assert unsafe { *C.ios_errno_address() } == expected, 'fd=${fd} flags=0x${u32(flags).hex()} expected=${expected}'
}

fn flock_test_success(call FlockTestCall, fd i32, flags i32) {
	darwin_set_errno(77)
	assert call(fd, flags) == 0
	assert unsafe { *C.ios_errno_address() } == 77
}

fn flock_test_mode(call FlockTestCall, first i32, other i32, flags i32) {
	flock_test_success(call, first, flags)
	if flags & 8 != 0 {
		flock_test_success(call, other, 6)
	} else if flags & 2 != 0 {
		flock_test_error(call, other, 5, 35)
		flock_test_error(call, other, 6, 35)
	} else {
		flock_test_success(call, other, 5)
		flock_test_success(call, other, 12)
		flock_test_error(call, other, 6, 35)
	}
	flock_test_success(call, first, 12)
	flock_test_success(call, other, 12)
}

fn flock_test_matrix(call FlockTestCall, first i32, other i32) {
	for extra in [u32(0), 0x10, 0x100, 0x40000000, 0xfffffff0]! {
		for low in 0 .. 16 {
			flags := i32(extra | u32(low))
			flock_test_error(call, -1, flags, 9)
			if flags & 11 == 0 { flock_test_error(call, first, flags, 9) }
			else { flock_test_mode(call, first, other, flags) }
		}
	}
	// Invalid operations must leave an existing lock held.
	flock_test_success(call, first, 2)
	flock_test_error(call, first, 0, 9)
	flock_test_error(call, other, 6, 35)
	flock_test_success(call, first, 12)
}

fn flock_test_blocked(call FlockTestCall, fd i32, signals &u64) {
	darwin_set_errno(177)
	C.ios_store_pointer(signals, 1)
	assert call(fd, 2) == 0
	assert unsafe { *C.ios_errno_address() } == 177
	C.ios_store_pointer(unsafe { signals + 1 }, 1)
}

fn flock_test_wait(call FlockTestCall, first i32, other i32) {
	flock_test_success(call, first, 2)
	mut signals := [u64(0), 0]!
	worker := spawn flock_test_blocked(call, other, unsafe { &signals[0] })
	for _ in 0 .. 1000 {
		if C.ios_load_pointer(unsafe { &signals[0] }) == 1 { break }
		time.sleep(time.millisecond)
	}
	assert C.ios_load_pointer(unsafe { &signals[0] }) == 1
	time.sleep(20 * time.millisecond)
	assert C.ios_load_pointer(unsafe { &signals[1] }) == 0
	flock_test_success(call, first, 12)
	worker.wait()
	assert C.ios_load_pointer(unsafe { &signals[1] }) == 1
	flock_test_success(call, other, 12)
}

fn flock_test_lifetime(call FlockTestCall, path string) {
	original := i32(C.open(path.str, C.O_RDWR))
	alias := C.fcntl(original, C.F_DUPFD, usize(0))
	other := i32(C.open(path.str, C.O_RDWR))
	assert original >= 0 && alias >= 0 && other >= 0
	flock_test_success(call, original, 2)
	assert C.close(original) == 0
	flock_test_error(call, other, 6, 35)
	flock_test_success(call, alias, 12)
	flock_test_success(call, alias, 2)
	child := C.ios_fork()
	assert child >= 0
	if child == 0 {
		if call(alias, 12) != 0 { C._exit(1) }
		C._exit(0)
	}
	mut status := i32(-1)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
	flock_test_success(call, other, 6)
	flock_test_success(call, other, 12)
	flock_test_success(call, alias, 2)
	closed_child := C.ios_fork()
	assert closed_child >= 0
	if closed_child == 0 { C.close(alias); C._exit(0) }
	assert C.ios_waitpid(closed_child, unsafe { &status }, 0) == closed_child && status == 0
	flock_test_error(call, other, 6, 35)
	assert C.close(alias) == 0
	flock_test_success(call, other, 6)
	assert C.close(other) == 0
}

fn flock_test_conversion(call FlockTestCall, first i32, other i32) {
	flock_test_success(call, first, 1)
	flock_test_success(call, other, 1)
	flock_test_error(call, first, 6, 35)
	flock_test_success(call, other, 12)
	result := call(other, 6)
	retained := result == -1
	if retained { assert unsafe { *C.ios_errno_address() } == 35 } else { assert result == 0 }
	$if macos { assert retained }
	flock_test_success(call, first, 12)
	flock_test_success(call, other, 12)
	println('IOS-FLOCK-CONVERSION: failed upgrade retained shared lock=' + retained.str() + '; Vinix uses native Linux conversion semantics')
}

fn flock_test_descriptors(call FlockTestCall, path string) {
	mut pairs := [4]i32{}
	assert C.pipe(unsafe { &pairs[0] }) == 0 && C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pairs[2] }) == 0
	for fd in pairs { for flags in [i32(0), 5, 6, 12]! { flock_test_error(call, fd, flags, 45) }; assert C.close(fd) == 0 }
	for access in [i32(C.O_RDONLY), C.O_WRONLY]! {
		fd := i32(C.open(path.str, access))
		assert fd >= 0
		flock_test_success(call, fd, 6)
		flock_test_success(call, fd, 12)
		assert C.close(fd) == 0
	}
	fd := i32(C.open(path.str, C.O_RDONLY))
	assert fd >= 0 && C.close(fd) == 0
	flock_test_error(call, fd, 12, 9)
	directory := path + '.dir'
	assert C.ios_mkdir(directory.str, 0o700) == 0
	first_dir := i32(C.open(directory.str, C.O_RDONLY | C.O_DIRECTORY))
	other_dir := i32(C.open(directory.str, C.O_RDONLY | C.O_DIRECTORY))
	assert first_dir >= 0 && other_dir >= 0
	for flags in [i32(5), 6, 12]! { flock_test_mode(call, first_dir, other_dir, flags) }
	assert C.close(first_dir) == 0 && C.close(other_dir) == 0 && C.rmdir(directory.str) == 0
	device := i32(C.open(c'/dev/null', C.O_RDWR))
	assert device >= 0
	$if linux { for flags in [i32(0), 5, 6, 12]! { flock_test_error(call, device, flags, 45) } }
	$if macos { flock_test_error(call, device, 0, 9); flock_test_success(call, device, 6); flock_test_success(call, device, 12) }
	assert C.close(device) == 0
	unsafe { directory.free() }
}

fn flock_test_registers(call FlockTestCall, fd i32) {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, word in [u32(0xa9bf7bfd), 0xaa0003f0, 0xaa0103e0, 0xaa0203e1, 0xd63f0200, 0xa8c17bfd, 0xd65f03c0]! { write32(code + u64(i * 4), word) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 28))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { FlockTestRaw(voidptr(code)) }
	darwin_set_errno(77)
	assert probe(u64(voidptr(call)), (u64(0x87654321) << 32) | u64(u32(fd)), (u64(0x12345678) << 32) | 12) == 0
	assert unsafe { *C.ios_errno_address() } == 77
	assert probe(u64(voidptr(call)), 0x87654321ffffffff, (u64(0x12345678) << 32) | 12) == -1
	assert unsafe { *C.ios_errno_address() } == 9 && C.munmap(voidptr(code), page) == 0
}

fn flock_test_file() FlockTestFile {
	mut template := ('/tmp/ios-flock-XXXXXX' + '\x00').bytes()
	defer { unsafe { template.free() } }
	first := C.mkstemp(template.data)
	assert first >= 0
	path := unsafe { tos_clone(template.data) }
	other := i32(C.open(path.str, C.O_RDWR))
	open_error := unsafe { *C.ios_errno_address() }
	assert other >= 0, 'path=${path} first=${first} errno=${open_error}'
	return FlockTestFile{first, other, path}
}

fn flock_test_close(file FlockTestFile) {
	assert C.close(file.other) == 0 && C.close(file.first) == 0 && C.unlink(file.path.str) == 0
	unsafe { file.path.free() }
}

fn flock_test_run(call FlockTestCall, detailed bool, file FlockTestFile) {
	first := file.first
	other := file.other
	path := file.path
	assert C.write(first, c'unchanged contents', 18) == 18 && C.lseek(first, 5, 0) == 5
	flags := C.fcntl(first, C.F_GETFL, usize(0))
	mut environment := [32]u64{}
	assert C.fegetenv(unsafe { voidptr(&environment[0]) }) == 0
	defer { C.fesetenv(unsafe { voidptr(&environment[0]) }) }
	for rounding in [i32(C.FE_TONEAREST), C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
		assert C.fesetround(rounding) == 0
		C.feclearexcept(C.FE_ALL_EXCEPT)
		C.feraiseexcept(C.FE_DIVBYZERO | C.FE_INEXACT)
		sticky := C.fetestexcept(C.FE_ALL_EXCEPT)
		flock_test_matrix(call, first, other)
		assert C.fegetround() == rounding && C.fetestexcept(C.FE_ALL_EXCEPT) == sticky
	}
	if detailed {
		flock_test_descriptors(call, path)
		flock_test_wait(call, first, other)
		flock_test_lifetime(call, path)
		flock_test_conversion(call, first, other)
		flock_test_registers(call, first)
	}
	mut final_flags := C.fcntl(first, C.F_GETFL, usize(0))
	// Darwin reports an internal 0x4000 bit after flock, even after unlock.
	// Access and ordinary descriptor status bits must remain unchanged.
	$if macos { final_flags &= ~i32(0x4000) }
	assert final_flags == flags && C.lseek(first, 0, 1) == 5
	mut contents := [18]u8{}
	assert C.pread(first, unsafe { &contents[0] }, 18, 0) == 18
	assert C.memcmp(unsafe { &contents[0] }, c'unchanged contents', 18) == 0
}

fn test_flock() {
	$if macos {
		native := unsafe { FlockTestCall(C.dlsym(voidptr(-2), c'flock')) }
		file := flock_test_file()
		flock_test_run(native, true, file)
		flock_test_close(file)
	}
	address := runtime_symbol('/usr/lib/libSystem.B.dylib', '_flock') or { panic(err) }
	call := unsafe { FlockTestCall(voidptr(address)) }
	file := flock_test_file()
	flock_test_run(call, true, file)
	flock_test_close(file)
	// Create and retire names sequentially; all eight workers exercise their
	// already-open files concurrently, including real kernel lock conflicts.
	mut files := [8]FlockTestFile{}
	for id in 0 .. 8 { files[id] = flock_test_file() }
	mut workers := []thread{cap: 8}
	for id in 0 .. 8 { workers << spawn flock_test_run(call, false, files[id]) }
	workers.wait()
	unsafe { workers.free() }
	for item in files { flock_test_close(item) }
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
		mut rejected := false
		runtime_symbol(library, '_flock') or { rejected = true }
		assert rejected
	}
	println('IOS-FLOCK: native oracle, 80 flag combinations, shared/exclusive contention, blocking wakeup, read/write access, pipe/socket/closed errors, dup/fork/last-close ownership, raw ARM64 dirty-upper arguments, unchanged data/offset/flags/errno/fenv and eight concurrent callers passed; Linux conversion and POSIX-lock-domain differences remain')
}
