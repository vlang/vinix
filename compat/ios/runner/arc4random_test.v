// SPDX-License-Identifier: GPL-2.0-or-later
module main

type ArcWord = fn () u32
type ArcBuffer = fn (voidptr, usize)
type ArcUniform = fn (u32) u32

fn arc_word() ArcWord {
	return unsafe { ArcWord(runtime_symbol('/usr/lib/libSystem.B.dylib', '_arc4random') or { panic(err) }) }
}

fn arc_buffer() ArcBuffer {
	return unsafe { ArcBuffer(runtime_symbol('/usr/lib/libSystem.B.dylib', '_arc4random_buf') or { panic(err) }) }
}

fn arc_uniform() ArcUniform {
	return unsafe { ArcUniform(runtime_symbol('/usr/lib/libSystem.B.dylib', '_arc4random_uniform') or { panic(err) }) }
}

fn arc_check_state(expected i32, flags int, rounding i32) {
	assert unsafe { *C.ios_errno_address() } == expected
	assert C.fetestexcept(C.FE_ALL_EXCEPT) == flags
	assert C.fegetround() == rounding
}

fn arc_calls(seed int) {
	word := arc_word()
	buffer := arc_buffer()
	uniform := arc_uniform()
	previous_rounding := C.fegetround()
	defer {
		assert C.fesetround(previous_rounding) == 0
		assert C.feclearexcept(C.FE_ALL_EXCEPT) == 0
	}
	for rounding in [i32(C.FE_TONEAREST), C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
		assert C.fesetround(rounding) == 0
		assert C.feclearexcept(C.FE_ALL_EXCEPT) == 0
		assert C.feraiseexcept(C.FE_DIVBYZERO) == 0
		flags := C.fetestexcept(C.FE_ALL_EXCEPT)
		errno := i32(41 + seed)
		darwin_set_errno(errno)
		first := word()
		mut changed := false
		for _ in 0 .. 32 {
			if word() != first { changed = true }
			arc_check_state(errno, flags, rounding)
		}
		assert changed
		for bound in [u32(0), 1, 2, 3, 7, 255, 256, 257, 65535, 0x80000000, 0x80000001, 0xffffffff]! {
			for _ in 0 .. 64 {
				value := uniform(bound)
				assert if bound < 2 { value == 0 } else { value < bound }
				arc_check_state(errno, flags, rounding)
			}
		}
		mut bytes := [513]u8{}
		buffer(unsafe { &bytes[1] }, 511)
		assert bytes[0] == 0 && bytes[512] == 0
		arc_check_state(errno, flags, rounding)
	}
}

fn test_arc4random_typed_calls_and_threads() {
	arc_calls(0)
	mut workers := []thread{cap: 8}
	for i in 0 .. 8 { workers << spawn arc_calls(i + 1) }
	workers.wait()
	unsafe { workers.free() }
}

fn test_arc4random_guarded_buffers() {
	buffer := arc_buffer()
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page * 4), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(region) }, usize(page * 4)) == 0 }
	assert C.mprotect(unsafe { voidptr(region + page) }, usize(page * 2), C.PROT_READ | C.PROT_WRITE) == 0
	for count in [u64(0), 1, 3, 4, 7, 255, 256, 257, 4095, 4096, 4097, page * 2 - 32]! {
		// Test both ends: a guard catches even a one-byte over/underwrite.
		for end_guard in [false, true]! {
			address := if end_guard { region + page * 3 - count } else { region + page }
			canary := if end_guard { address - 32 } else { address + count }
			C.memset(unsafe { voidptr(canary) }, 0x5a, 32)
			darwin_set_errno(42)
			buffer(unsafe { voidptr(address) }, usize(count))
			assert unsafe { *C.ios_errno_address() } == 42
			for i in 0 .. 32 {
				assert unsafe { *(&u8(canary + u64(i))) } == 0x5a
			}
		}
	}
	for address in [u64(0), region, region + page * 3, ~u64(0)]! {
		darwin_set_errno(42)
		buffer(unsafe { voidptr(address) }, 0)
		assert unsafe { *C.ios_errno_address() } == 42
	}
	assert cc_random_generate(unsafe { nil }, 1) == -4300
	assert cc_random_generate(unsafe { &u8(~u64(0) - 3) }, 8) == -4300
	// Larger than SecRandomCopyBytes' separate 16 MiB limit. Only boundary
	// canaries are deterministic; random bytes are never compared to a pattern.
	size := usize(16 * 1024 * 1024 + 1)
	allocation := C.malloc(size + 2)
	assert allocation != unsafe { nil }
	defer { C.free(allocation) }
	unsafe {
		*(&u8(allocation)) = 0x5a
		*(&u8(u64(allocation) + u64(size) + 1)) = 0xa5
	}
	darwin_set_errno(42)
	buffer(unsafe { voidptr(u64(allocation) + 1) }, size)
	assert unsafe { *C.ios_errno_address() } == 42
	assert unsafe { *(&u8(allocation)) } == 0x5a
	assert unsafe { *(&u8(u64(allocation) + u64(size) + 1)) } == 0xa5
}

fn test_arc4random_fork() {
	mut pipe := [2]i32{}
	assert C.pipe(unsafe { &pipe[0] }) == 0
	defer {
		C.close(pipe[0])
		C.close(pipe[1])
	}
	// Warm the public APIs before fork. Child and parent must obtain fresh OS
	// entropy independently, with no inherited userspace generator lock/state.
	buffer := arc_buffer()
	mut before := [32]u8{}
	buffer(unsafe { &before[0] }, 32)
	pid := C.ios_fork()
	assert pid >= 0
	if pid == 0 {
		mut child := [32]u8{}
		buffer(unsafe { &child[0] }, 32)
		if C.write(pipe[1], unsafe { &child[0] }, 32) != 32 { C._exit(1) }
		C._exit(0)
	}
	mut parent := [32]u8{}
	mut child := [32]u8{}
	buffer(unsafe { &parent[0] }, 32)
	assert C.read(pipe[0], unsafe { &child[0] }, 32) == 32
	mut status := i32(-1)
	assert C.ios_waitpid(pid, unsafe { &status }, 0) == pid && status == 0
	assert C.memcmp(unsafe { &parent[0] }, unsafe { &child[0] }, 32) != 0
	assert C.memcmp(unsafe { &before[0] }, unsafe { &child[0] }, 32) != 0
}

fn test_arc4random_library_scope() {
	for symbol in ['_arc4random', '_arc4random_buf', '_arc4random_uniform']! {
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', symbol)! != 0
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
			'/System/Library/Frameworks/Foundation.framework/Foundation']! {
			mut rejected := false
			libsystem_symbol(library, symbol) or { rejected = true }
			assert rejected
		}
	}
	println('IOS-ARC4RANDOM: typed word/buffer/uniform ABI, guarded zero/chunk/page/large buffers, errno/flags/four rounding modes, eight concurrent callers and fork passed')
}
