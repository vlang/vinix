// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.pipe(&i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
type InitializerFile = fn (u64, i32, u64, i32, u64, i32, u32, u32, u32)
type InitializerPlain = fn (u64, i32, u64, i32, u32)
type InitializerProbe = fn (&u64, u64, u64, &u64)
const initializer_symbols = [
	'__swift_stdlib_reportUnimplementedInitializerInFile',
	'__swift_stdlib_reportUnimplementedInitializer',
]!

fn initializer_returns() {}

fn initializer_output(probe InitializerProbe, entry u64, args &u64, direct bool,
	in_file bool, broken_stderr bool) string {
	mut descriptors := [2]i32{}
	assert C.pipe(unsafe { &descriptors[0] }) == 0
	child := C.ios_fork()
	assert child >= 0
	if child == 0 {
		C.close(descriptors[0])
		if broken_stderr { C.close(2) }
		else { assert C.dup2(descriptors[1], 2) == 2 }
		C.close(descriptors[1])
		if direct {
			unsafe {
				if in_file {
					report := InitializerFile(voidptr(entry))
					report(args[0], i32(args[1]), args[2], i32(args[3]), args[4],
						i32(args[5]), u32(args[6]), u32(args[7]), u32(args[8]))
				} else {
					report := InitializerPlain(voidptr(entry))
					report(args[0], i32(args[1]), args[2], i32(args[3]), u32(args[8]))
				}
			}
		} else {
			mut observed := u64(0)
			probe(args, entry, 0xdeadbeef12345678, unsafe { &observed })
			assert observed == 0xdeadbeef12345678
		}
		C._exit(0) // These C reporting shims return; their Swift caller traps.
	}
	C.close(descriptors[1])
	mut bytes := []u8{}
	for {
		mut buffer := [256]u8{}
		count := C.read(descriptors[0], unsafe { &buffer[0] }, 256)
		if count == 0 { break }
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		assert count > 0
		bytes << buffer[..int(count)]
	}
	C.close(descriptors[0])
	mut status := i32(0)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child
	assert status == 0, 'initializer reporter failed to return: ' + status.str()
	return bytes.bytestr()
}

fn initializer_cases(probes [2]InitializerProbe, entries [2]u64) {
	page := usize(C.getpagesize())
	guard := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(guard) }, page * 2) == 0 }
	end := guard + u64(page)
	C.memcpy(unsafe { voidptr(end - 3) }, c'abc', 3)
	assert C.mprotect(unsafe { voidptr(guard) }, page, C.PROT_READ) == 0
	assert C.mprotect(unsafe { voidptr(end) }, page, C.PROT_NONE) == 0
	record := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert record != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(record) }, page * 2) == 0 }
	assert C.mprotect(unsafe { voidptr(record + u64(page)) }, page, C.PROT_NONE) == 0
	arguments := record + u64(page) - 72
	for item in 0 .. 20 {
		class_name := 'Demo🎮Class-unused'
		init_name := 'init(value:)tail'
		file := 'Sources/Game.swift-unused'
		mut words := [u64(class_name.str), 13, u64(init_name.str), 12,
			u64(file.str), 18, 42, 99, 0]!
		mut expected_class := 'Demo🎮Class'
		mut expected_init := 'init(value:)'
		mut expected_file := 'Sources/Game.swift'
		if item == 1 { words[6] = 0; words[7] = 0 }
		if item == 2 { words[6] = 0xffffffff; words[7] = 0xffffffff }
		if item == 3 { words[8] = 1 }
		if item == 4 { words[8] = 0x80000000 }
		if item == 5 { words[8] = 0xffffffff }
		if item == 6 || item == 7 { words[1] = 0; expected_class = '' }
		if item == 6 || item == 8 { words[3] = 0; expected_init = '' }
		if item == 6 || item == 9 { words[5] = 0; expected_file = '' }
		if item == 10 {
			words[0] = u64(c'Demo\0ignored'); words[1] = 12; expected_class = 'Demo'
		}
		if item == 11 {
			words[2] = u64(c'init()\0ignored'); words[3] = 14; expected_init = 'init()'
		}
		if item == 12 {
			words[4] = u64(c'Game.swift\0ignored'); words[5] = 18; expected_file = 'Game.swift'
		}
		if item == 13 {
			words[0] = u64(c'\0class'); words[1] = 6; expected_class = ''
			words[2] = u64(c'\0init'); words[3] = 5; expected_init = ''
			words[4] = u64(c'\0file'); words[5] = 5; expected_file = ''
		}
		if item == 14 || item == 17 {
			words[0] = end - 3; words[1] = 3; expected_class = 'abc'
		}
		if item == 15 || item == 17 {
			words[2] = end - 3; words[3] = 3; expected_init = 'abc'
		}
		if item == 16 || item == 17 {
			words[4] = end - 3; words[5] = 3; expected_file = 'abc'
		}
		if item == 18 {
			words[0] = end; words[1] = 0; expected_class = ''
			words[2] = end; words[3] = 0; expected_init = ''
			words[4] = end; words[5] = 0; expected_file = ''
		}
		if item == 19 {
			words[1] = 1; expected_class = 'D'
			words[3] = 1; expected_init = 'i'
			words[5] = 1; expected_file = 'S'
		}
		body := "Fatal error: Use of unimplemented initializer '" + expected_init
			+ "' for class '" + expected_class + "'\n"
		file_output := expected_file + ':' + words[6].str() + ': ' + body
		// Raw calls poison the unspecified high halves of all narrow C args.
		// The ninth UInt32 flags is passed at caller sp+0 by the file probe.
		for index in [1, 3, 5, 6, 7, 8]! { words[index] |= 0xa5a5a5a500000000 }
		assert C.mprotect(unsafe { voidptr(record) }, page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memcpy(unsafe { voidptr(arguments) }, unsafe { &words[0] }, 72)
		assert C.mprotect(unsafe { voidptr(record) }, page, C.PROT_READ) == 0
		for which, entry in entries {
			for direct in [false, true]! {
				observed := initializer_output(probes[which], entry, unsafe { &u64(arguments) },
					direct, which == 0, false)
				expected := if which == 0 { file_output } else { body }
				assert observed == expected, 'initializer case ' + item.str() +
					' entry ' + which.str() + ' direct ' + direct.str()
			}
		}
	}
	mut words := [u64(c'Class'), 5, u64(c'init()'), 6, u64(c'file.swift'), 10, 42, 99, 0]!
	for which, entry in entries {
		assert initializer_output(probes[which], entry, unsafe { &words[0] },
			false, which == 0, true) == ''
	}
}

fn initializer_resolve() [2]u64 {
	mut entries := [2]u64{}
	for i, symbol in initializer_symbols {
		entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) }
	}
	return entries
}

fn initializer_worker(probes [2]InitializerProbe, entries [2]u64, worker int) {
	mut words := [u64(c'Class'), 5, u64(c'init()'), 6, u64(c'file.swift'), 10, 42, 99, 0]!
	for i in 0 .. 128 {
		for which, entry in entries {
			context := u64(0xdeadbeef00000000) ^ u64(worker << 12 | i)
			mut seen := u64(0)
			probes[which](unsafe { &words[0] }, entry, context, unsafe { &seen })
			assert seen == context
		}
	}
}

fn initializer_workers(probes [2]InitializerProbe, entries [2]u64) {
	saved := C.dup(2); assert saved >= 0
	null_file := C.open(c'/dev/null', C.O_WRONLY, 0); assert null_file >= 0
	assert C.dup2(i32(null_file), 2) == 2
	C.close(null_file)
	mut workers := []thread{}
	for worker in 0 .. 8 { workers << spawn initializer_worker(probes, entries, worker) }
	workers.wait()
	assert C.dup2(saved, 2) == 2
	C.close(saved)
}

fn test_swift_initializer_reporters() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(code) }, page) == 0 }
	// V-emitted C ABI adapters load eight registers plus the spilled flags,
	// preserve the caller's x19/x20/frame and record the borrowed Swift x20.
	for offset in [u64(0), 96]! {
		for i, op in [u32(0xd10103ff), 0xa9037bfd, 0xa90253f3, 0x910003fd,
			0xaa0003e9, 0xaa0103f0, 0xaa0203f4, 0xaa0303f3, 0xf9402128,
			0xf90003e8, 0xa9400520, 0xa9410d22, 0xa9421524, 0xa9431d26,
			0xd63f0200, 0xf9000274, 0xa94253f3, 0xa9437bfd, 0x910103ff,
			0xd65f03c0]! { write32(code + offset + u64(i * 4), op) }
	}
	write32(code + 96 + 48, 0xf9402124) // Plain flags in x4 instead of file.
	write32(code + 96 + 52, 0xd503201f)
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 176) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probes := [unsafe { InitializerProbe(voidptr(code)) },
		unsafe { InitializerProbe(voidptr(code + 96)) }]!
	mut zero := [9]u64{}
	for probe in probes {
		assert initializer_output(probe, u64(unsafe { voidptr(initializer_returns) }),
			unsafe { &zero[0] }, false, false, false) == ''
	}
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		mut native := [2]u64{}
		for i, name in initializer_symbols {
			native[i] = u64(C.dlsym(lib, unsafe { name[1..].str })); assert native[i] != 0
		}
		initializer_cases(probes, native)
		initializer_workers(probes, native)
		println('IOS-SWIFT-INITIALIZER-NATIVE: both reporters return after twenty exact diagnostics, bounded/NUL/empty/protected spans, narrow C args, UInt32 limits/flags, broken stderr, preserved Swift context and eight workers')
	}
	early := initializer_resolve()
	initializer_cases(probes, early)
	for _ in 0 .. 2 {
		objc_start()
		mut resolvers := []thread [2]u64{}
		for _ in 0 .. 8 { resolvers << spawn initializer_resolve() }
		resolved := resolvers.wait()
		for entries in resolved { assert entries == early && entries[0] != 0 && entries[1] != 0 }
		initializer_cases(probes, early)
		initializer_workers(probes, early)
		for item in 0 .. 6 {
			mut args := [u64(c'Class'), 5, u64(c'init()'), 6, u64(c'file.swift'), 10, 42, 99, 0]!
			if item == 0 { args[0] = 0 }
			if item == 1 { args[2] = 0 }
			if item == 2 { args[4] = 0 }
			if item == 3 { args[0] = 1; args[1] = 0xffffffff }
			if item == 4 { args[2] = 1; args[3] = 0x80000000 }
			if item == 5 { args[4] = 1; args[5] = 0xffffffff }
			for which, entry in early {
				if which == 1 && item in [2, 5] { continue }
				assert initializer_output(probes[which], entry, unsafe { &args[0] },
					false, which == 0, false) == 'Vinix Swift runtime: Fatal error: invalid initializer arguments\n'
			}
		}
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.swift_arrays.len == 0
		assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_array_arena == 0 && ios_runtime.swift_integer_arena == 0 && ios_runtime.swift_void_arena == 0
		assert ios_runtime.swift_arc_code == 0 && ios_runtime.swift_hash_code == 0 && ios_runtime.swift_fatal_code == 0
		objc_stop()
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
		assert initializer_resolve() == early
		assert initializer_output(probes[0], early[0], unsafe { &zero[0] },
			false, true, false) == 'Vinix Swift runtime: Fatal error: invalid initializer arguments\n'
	}
	println('IOS-SWIFT-INITIALIZER: both ordinary C ABI reporting entries return, exact bounded diagnostics, read-only/protected/zero-length/NUL spans, UInt32 limits/flags and ninth stack arg, preserved context, invalid inputs, broken stderr, eight workers and two drained cycles without runtime arenas')
}
