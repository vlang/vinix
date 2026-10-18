// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

type BtCall = fn (voidptr, i32) i32
type BtProbe = fn (u64, voidptr, i32) i32

fn bt_put64(address u64, value u64) {
	unsafe { *(&u64(address)) = value }
}

fn bt_code() u64 {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	// Three actual AAPCS64 frames, independent of ELF/DWARF metadata. Root
	// preserves x19-x21 and records its FP/LR; the leaf calls the imported API.
	for i, instruction in [u32(0xa9bc7bfd), 0x910003fd, 0xa90153f3, 0xf90013f5, 0xaa0003f3, 0xaa0103f4,
		0x2a0203f5, 0x94000019, 0xf94013f5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), instruction)
	}
	for i, instruction in [u32(0xa9bf7bfd), 0x910003fd, 0x9400000e, 0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), instruction)
	}
	for i, instruction in [u32(0xa9bf7bfd), 0x910003fd, 0xaa1403e0, 0x2a1503e1, 0xd63f0260, 0xa8c17bfd,
		0xd65f03c0]! {
		write32(code + 192 + u64(i * 4), instruction)
	}
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 220) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	return code
}

fn bt_check_prefix(code u64, output &u64, count i32) {
	for i, expected in [code + 212, code + 140, code + 32]! {
		if i >= int(count) { break }
		assert unsafe { output[i] } == expected
	}
}

fn bt_guarded_capture(entry u64, code u64) {
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page * 4), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(region) }, usize(page * 4)) == 0 }
	assert C.mprotect(unsafe { voidptr(region + page) }, usize(page * 2), C.PROT_READ | C.PROT_WRITE) == 0
	previous_rounding := C.fegetround()
	defer {
		assert C.fesetround(previous_rounding) == 0
		C.feclearexcept(C.FE_ALL_EXCEPT)
	}
	for rounding in [i32(C.FE_TONEAREST), C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
		assert C.fesetround(rounding) == 0
		assert C.feclearexcept(C.FE_ALL_EXCEPT) == 0
		assert C.feraiseexcept(C.FE_DIVBYZERO) == 0
		flags := C.fetestexcept(C.FE_ALL_EXCEPT)
		for capacity in [i32(0), 1, 2, 3, 4, 8, 64]! {
			address := region + page * 3 - u64(capacity) * 8
			C.memset(unsafe { voidptr(address - 32) }, 0x5a, usize(capacity) * 8 + 32)
			darwin_set_errno(42)
			count := unsafe { BtProbe(voidptr(code))(entry, voidptr(address), capacity) }
			assert count >= 0 && count <= capacity
			assert if capacity < 3 { count == capacity } else { count >= 3 }
			assert unsafe { *C.ios_errno_address() } == 42
			assert C.fetestexcept(C.FE_ALL_EXCEPT) == flags && C.fegetround() == rounding
			bt_check_prefix(code, unsafe { &u64(address) }, count)
			for i in 1 .. 33 {
				assert unsafe { *(&u8(address - u64(i))) } == 0x5a
			}
			for i in int(count) .. int(capacity) {
				assert read64(address + u64(i * 8)) in [u64(0), 0x5a5a5a5a5a5a5a5a]!
			}
		}
	}
}

fn bt_worker(entry u64, code u64, index int) {
	for _ in 0 .. 64 {
		mut output := [64]u64{}
		darwin_set_errno(40 + index)
		count := unsafe { BtProbe(voidptr(code))(entry, &output[0], 64) }
		assert count >= 3 && count <= 64
		bt_check_prefix(code, unsafe { &output[0] }, count)
		assert unsafe { *C.ios_errno_address() } == i32(40 + index)
	}
}

fn test_backtrace_real_frames_and_native_reference() {
	entry := runtime_symbol('/usr/lib/libSystem.B.dylib', '_backtrace')!
	code := bt_code()
	defer { assert C.munmap(unsafe { voidptr(code) }, usize(C.getpagesize())) == 0 }
	bt_guarded_capture(entry, code)
	$if macos {
		handle := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
		assert handle != unsafe { nil }
		native := u64(C.dlsym(handle, c'backtrace'))
		assert native != 0
		bt_guarded_capture(native, code)
		assert C.dlclose(handle) == 0
	}
	mut workers := []thread{cap: 8}
	for i in 0 .. 8 { workers << spawn bt_worker(entry, code, i) }
	workers.wait()
	unsafe { workers.free() }
	pid := C.ios_fork()
	assert pid >= 0
	if pid == 0 {
		mut output := [16]u64{}
		count := unsafe { BtProbe(voidptr(code))(entry, &output[0], 16) }
		C._exit(if count >= 3 && output[0] == code + 212 && output[1] == code + 140 && output[2] == code + 32 {
			0
		} else {
			1
		})
	}
	mut status := i32(-1)
	assert C.ios_waitpid(pid, unsafe { &status }, 0) == pid && status == 0
	println('IOS-BACKTRACE: typed pointer-array/int32 ABI, real V-emitted ARM64 frames with exact native caller PCs, guarded capacities, four rounding modes and sticky flags, preserved errno, 512 concurrent captures and fork passed')
}

fn test_backtrace_bounded_record_walker() {
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page * 4), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(region) }, usize(page * 4)) == 0 }
	low := region + page
	high := region + page * 3
	assert C.mprotect(unsafe { voidptr(low) }, usize(page * 2), C.PROT_READ | C.PROT_WRITE) == 0
	last := high - 16
	mut output := [8]u64{}
	bt_put64(low, last)
	bt_put64(low + 8, 0x2220)
	bt_put64(last, 0)
	bt_put64(last + 8, 0x3330)
	assert backtrace_walk(unsafe { &output[0] }, 8, low, 0x1110, low, high) == 3
	assert output[0] == 0x1110 && output[1] == 0x2220 && output[2] == 0x3330
	bt_put64(low + 8, 0)
	assert backtrace_walk(unsafe { &output[0] }, 8, low, 0x1110, low, high) == 3 && output[1] == 0
	bt_put64(low + 8, 0x2220)
	bt_put64(last + 8, 0)
	assert backtrace_walk(unsafe { &output[0] }, 8, low, 0x1110, low, high) == 2
	bt_put64(last + 8, 0x3330)
	for next in [low, low - 16, high, high + 16, ~u64(0), low + 1]! {
		bt_put64(low, next)
		assert backtrace_walk(unsafe { &output[0] }, 8, low, 0x1110, low, high) == 2
	}
	bt_put64(low, last | u64(0xab00000000000000))
	assert backtrace_walk(unsafe { &output[0] }, 8, low, 0x1110, low, high) == 3
	for start in [u64(0), low - 16, low + 1, high - 8, high, ~u64(0)]! {
		assert backtrace_walk(unsafe { &output[0] }, 8, start, 0x1110, low, high) == 1
	}
	for capacity in [i32(-1), -2147483647 - 1, 0]! {
		assert backtrace_walk(unsafe { &u64(region) }, capacity, ~u64(0), 0, 0, ~u64(0)) == 0
	}
	assert backtrace_walk(unsafe { nil }, 8, low, 0, low, high) == 0
	assert backtrace_walk(unsafe { &u64(~u64(0) - 7) }, 2, low, 0, low, high) == 0
	assert backtrace_walk(unsafe { &output[0] }, 8, 0, 0, 0, 0) == 0
	call := unsafe { BtCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_backtrace')!)) }
	for capacity in [i32(-1), -2147483647 - 1, 0]! {
		darwin_set_errno(42)
		assert call(unsafe { voidptr(region) }, capacity) == 0
		assert unsafe { *C.ios_errno_address() } == 42
	}
}

fn test_backtrace_library_scope() {
	address := backtrace_symbol('_backtrace') or { panic('missing backtrace symbol') }
	assert address != 0
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib']! {
		mut rejected := false
		libsystem_symbol(library, '_backtrace') or { rejected = true }
		assert rejected
	}
}
