// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.pipe(&i32) i32
fn C.dup2(i32, i32) i32
fn C.mincore(voidptr, usize, &u8) i32
type FatalProbe = fn (&u64, u64)
type FatalSignal = fn (i32, voidptr) voidptr
const fatal_symbols = [
	'_$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF',
	'_$ss18_fatalErrorMessage__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF',
]!
const fatal_string_symbol = '_$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAHSus6UInt32VtF'

fn fatal_trapped(number i32) { C._exit(100 + number) }
fn fatal_returns(_value u64) {}

fn fatal_output(probe FatalProbe, entry u64, args &u64, expected_status i32) string {
	mut descriptors := [2]i32{}
	assert C.pipe(unsafe { &descriptors[0] }) == 0
	child := C.ios_fork()
	assert child >= 0
	if child == 0 {
		C.close(descriptors[0])
		assert C.dup2(descriptors[1], 2) == 2
		C.close(descriptors[1])
		signal := unsafe { FatalSignal(voidptr(C.signal)) }
		signal(i32(C.SIGTRAP), unsafe { voidptr(fatal_trapped) })
		probe(args, entry)
		C._exit(99) // An assertion entry must never return.
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
	// A real BRK delivered SIGTRAP to our handler, which exits without the
	// host crash reporter or a guest kernel fatal-exception diagnostic.
	assert status == expected_status, 'wrong assertion termination: ' + status.str()
	return bytes.bytestr()
}

fn fatal_cases(probe FatalProbe, entries [2]u64) {
	page := usize(C.getpagesize())
	guard := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(guard) }, page * 2) == 0 }
	// No terminator and no byte readable beyond the supplied count.
	C.memcpy(unsafe { voidptr(guard + u64(page) - 3) }, c'abc', 3)
	assert C.mprotect(unsafe { voidptr(guard) }, page, C.PROT_READ) == 0
	assert C.mprotect(unsafe { voidptr(guard + u64(page)) }, page, C.PROT_NONE) == 0
	record := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert record != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(record) }, page) == 0 }
	for item in 0 .. 13 {
		prefix := if item == 2 { '' } else { 'Fatal error' }
		message := if item == 3 { '' } else if item == 4 { 'a\x00b' } else if item == 10 { '\x00abc' } else { 'fixture message' }
		file := if item == 1 { '' } else if item == 9 { 'f\x00ile' } else { 'fixture.swift' }
		mut args := [u64(prefix.str), u64(prefix.len), 2, u64(message.str), u64(message.len), 2,
			u64(file.str), u64(file.len), 2, if item == 5 { u64(0) } else if item == 6 { u64(0xffffffff) } else { u64(17) }, if item == 7 { u64(1) } else { u64(0) }]!
		mut expected := file + ':' + args[9].str() + ': ' + prefix + if message.len == 0 { '\n' } else { ': ' + message + '\n' }
		if item == 0 {
			args[0] = 0x1f600; args[1] = 0; args[2] = 1
			args[3] = 0xe9; args[4] = 0; args[5] = 1
			args[6] = 0x61; args[7] = 0; args[8] = 3
			expected = 'a:17: 😀: é\n'
		} else if item == 4 { expected = 'fixture.swift:17: Fatal error: a\n' }
		else if item == 8 {
			args[3] = guard + u64(page) - 3; args[4] = 3
			expected = 'fixture.swift:17: Fatal error: abc\n'
		} else if item == 9 { expected = 'f:17: Fatal error: fixture message\n' }
		else if item == 10 { expected = 'fixture.swift:17: Fatal error: \n' }
		else if item == 11 {
			args[3] = 0x10ffff; args[4] = 0; args[5] = 1
			expected = 'fixture.swift:17: Fatal error: \xf4\x8f\xbf\xbf\n'
		} else if item == 12 {
			args[3] = 0; args[4] = 0; args[5] = 3
			expected = 'fixture.swift:17: Fatal error: \n'
		}
		assert C.mprotect(unsafe { voidptr(record) }, page, C.PROT_READ | C.PROT_WRITE) == 0
		C.memcpy(unsafe { voidptr(record) }, unsafe { &args[0] }, 88)
		assert C.mprotect(unsafe { voidptr(record) }, page, C.PROT_READ) == 0
		for entry in entries { assert fatal_output(probe, entry, unsafe { &u64(record) }, 105 * 256) == expected, 'case ' + item.str() }
	}
}

fn fatal_resolver() u64 {
	address := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', fatal_symbols[0]) or { panic(err) }
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', fatal_symbols[1]) or { panic(err) } == address
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', fatal_string_symbol) or { panic(err) } == address + 96
	return address
}

fn fatal_string_cases(probe FatalProbe, entry u64) {
	page := usize(C.getpagesize())
	guard := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	defer { assert C.munmap(unsafe { voidptr(guard) }, page * 2) == 0 }
	C.memcpy(unsafe { voidptr(guard + u64(page) - 16) }, c'123456789abcdefg', 16)
	assert C.mprotect(unsafe { voidptr(guard) }, page, C.PROT_READ) == 0
	assert C.mprotect(unsafe { voidptr(guard + u64(page)) }, page, C.PROT_NONE) == 0
	for item, message in ['', 'é', 'fixture message', '123456789abcdef', '123456789abcdefg',
		'long Unicode message 😀', 'a\x00b', '\x00abc', 'readonly guard!!', 'flags', 'limit'] {
		mut words := swift_string_literal(message.str, message.len, message.is_ascii())
		if item == 8 { words = swift_string_literal(unsafe { &u8(guard + u64(page) - 16) }, 16, true) }
		mut args := [u64(c'Fatal error'), 11, 2, words.first, words.second,
			u64(c'fixture.swift'), 13, 2, if item == 10 { u64(0xffffffff) } else { u64(17) }, if item == 9 { u64(1) } else { u64(0) }, 0]!
		mut expected := 'fixture.swift:' + args[8].str() + ': Fatal error' + if message.len == 0 { '\n' } else { ': ' + message + '\n' }
		if item == 6 { expected = 'fixture.swift:17: Fatal error: a\n' }
		if item == 7 { expected = 'fixture.swift:17: Fatal error: \n' }
		if item == 8 { expected = 'fixture.swift:17: Fatal error: 123456789abcdefg\n' }
		if item == 1 {
			args[0] = 0x1f600; args[1] = 0; args[2] = 1
			args[5] = 0x61; args[6] = 0; args[7] = 3
			expected = 'a:17: 😀: é\n'
		}
		assert fatal_output(probe, entry, unsafe { &args[0] }, 105 * 256) == expected, 'String case ' + item.str()
	}
}

fn test_swift_fatal() {
	$if !arm64 { return }
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page) == 0 }
	// Test adapter: record x0, target x1 -> eight Swift registers and three
	// spilled arguments. A returning target restores the caller and reaches
	// exit(99), so the adapter cannot masquerade as the callee's own BRK.
	for i, op in [u32(0xd100c3ff), 0xf90013fe, 0xaa0003e9, 0xaa0103f0, 0xa9442928,
		0xa9002be8, 0xf9402928, 0xf9000be8, 0xa9400520, 0xa9410d22,
		0xa9421524, 0xa9431d26, 0xd63f0200, 0xf94013fe, 0x9100c3ff, 0xd65f03c0]! { write32(u64(code) + u64(i * 4), op) }
	C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 64) })
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { FatalProbe(code) }
	mut zero := [11]u64{}
	assert fatal_output(probe, u64(unsafe { voidptr(fatal_returns) }), unsafe { &zero[0] }, 99 * 256) == ''
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		mut entries := [2]u64{}
		for i, name in fatal_symbols { entries[i] = u64(C.dlsym(lib, unsafe { name[1..].str })); assert entries[i] != 0 }
		fatal_cases(probe, entries)
		string_entry := u64(C.dlsym(lib, unsafe { fatal_string_symbol[1..].str }))
		assert string_entry != 0
		fatal_string_cases(probe, string_entry)
		println('IOS-SWIFT-FATAL-NATIVE: both StaticString entries and String-message assertion match twenty-four diagnostics and deliver SIGTRAP')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn fatal_resolver() }
		resolved := workers.wait()
		for address in resolved { assert address == resolved[0] && address != 0 }
		fatal_cases(probe, [resolved[0], resolved[0]]!)
		fatal_string_cases(probe, resolved[0] + 96)
		for item in 0 .. 4 {
			mut args := [u64(c'Fatal error'), 11, 2, u64(c'message'), 7, 2, u64(c'file'), 4, 2, 1, 0]!
			if item == 0 { args[0] = 0 }
			if item == 1 { args[3] = 0xd800; args[5] = 1 }
			if item == 2 { args[4] = 0x80000000 }
			if item == 3 { args[9] = 0x100000000 }
			assert fatal_output(probe, resolved[0], unsafe { &args[0] }, 105 * 256) == 'Vinix Swift runtime: Fatal error: invalid assertion arguments\n'
		}
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		for bits in [u64(0), 0x1000000000000000]! {
			mut unsupported := [u64(c'Fatal error'), 11, 2, 0, bits,
				u64(c'fixture.swift'), 13, 2, 1, 0, 0]!
			assert fatal_output(probe, resolved[0] + 96, unsafe { &unsupported[0] }, 105 * 256) == 'Vinix Swift runtime: Fatal error: invalid assertion arguments\n'
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss17_assertionFailure__5flagss5NeverOs12StaticStringV_SSs6UInt32VtF') == none
		arena := ios_runtime.swift_fatal_code
		assert arena == resolved[0]
		objc_stop()
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1 }
		$else { mut resident := u8(0); assert C.mincore(unsafe { voidptr(arena) }, page, unsafe { &resident }) == -1 }
	}
	println('IOS-SWIFT-FATAL: StaticString and String-message assertion entries, scalar/pointer/small/tail UTF-8, NUL/empty diagnostics, guard pages, UInt32 line limits, actual BRK/SIGTRAP, eight publication workers and two drained teardowns')
}
