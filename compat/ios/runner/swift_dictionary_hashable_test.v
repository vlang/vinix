// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
fn C.pipe(&i32) i32
fn C.dup2(i32,i32) i32
fn C.mincore(voidptr,usize,&u8) i32
type DictionaryHashableCall = fn (u64)
type DictionaryHashableSignal = fn (i32,voidptr) voidptr
const dictionary_hashable_symbol = '_$ss53KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTSys5NeverOypXpF'

fn dictionary_hashable_trapped(number i32) { C._exit(100 + number) }
fn dictionary_hashable_returns(_metadata u64) {}
fn dictionary_hashable_output(entry u64, metadata u64, broken bool, expected_status i32) string {
	mut descriptors := [2]i32{}
	assert C.pipe(unsafe { &descriptors[0] }) == 0
	child := C.ios_fork()
	assert child >= 0
	if child == 0 {
		C.close(descriptors[0])
		assert C.dup2(descriptors[1], 2) == 2
		C.close(descriptors[1])
		if broken { C.close(2) }
		signal := unsafe { DictionaryHashableSignal(voidptr(C.signal)) }
		signal(i32(C.SIGTRAP), unsafe { voidptr(dictionary_hashable_trapped) })
		signal(i32(C.SIGSEGV), unsafe { voidptr(dictionary_hashable_trapped) })
		call := unsafe { DictionaryHashableCall(voidptr(entry)) }
		call(metadata)
		C._exit(99) // The control returns here; the diagnostic must trap itself.
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
	assert status == expected_status, 'wrong dictionary diagnostic termination: ' + status.str()
	return bytes.bytestr()
}

fn dictionary_hashable_cases(entry u64, metadata [3]u64) {
	for i, name in ['String', 'Int', 'Bool']! {
		expected := "Fatal error: Duplicate keys of type '" + name + "' were found in a Dictionary.\nThis usually means either that the type violates Hashable's requirements, or\nthat members of such a dictionary were mutated after insertion.\n"
		assert dictionary_hashable_output(entry, metadata[i], false, 105 * 256) == expected
		assert dictionary_hashable_output(entry, metadata[i], true, 105 * 256) == ''
	}
}

fn dictionary_hashable_resolver() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', dictionary_hashable_symbol) or { panic(err) }
}

fn test_swift_dictionary_hashable() {
	$if !arm64 { return }
	assert dictionary_hashable_output(u64(unsafe { voidptr(dictionary_hashable_returns) }), 0, false, 99 * 256) == ''
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, unsafe { &char(dictionary_hashable_symbol.str + 1) }))
		assert entry != 0
		mut metadata := [3]u64{}
		for i, symbol in [c'$sSSN', c'$sSiN', c'$sSbN']! {
			metadata[i] = u64(C.dlsym(lib, symbol)); assert metadata[i] != 0
		}
		dictionary_hashable_cases(entry, metadata)
		println('NATIVE-DICTIONARY-HASHABLE: String/Int/Bool exact diagnostics and actual BRK/SIGTRAP, including closed stderr and a returning control')
	}
	page := usize(C.getpagesize())
	guard := C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert guard != unsafe { voidptr(-1) }
	defer { assert C.munmap(guard, page) == 0 }
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn dictionary_hashable_resolver() }
		resolved := workers.wait()
		for address in resolved { assert address == resolved[0] && address != 0 }
		arena := ios_runtime.swift_fatal_code
		assert arena + 192 == resolved[0]
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF') or { panic(err) } == arena
		assert read32(resolved[0] + 16) == 0xd4200020 && read32(resolved[0] + 20) == 0x17ffffff
		mut metadata := [3]u64{}
		for i, symbol in ['_$sSSN', '_$sSiN', '_$sSbN']! {
			metadata[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) }
		}
		dictionary_hashable_cases(resolved[0], metadata)
		// Unknown, nil, interior and inaccessible metadata are never read.
		for value in [u64(0), u64(1), u64(guard), metadata[0] + 8, ~u64(0)]! {
			assert swift_dictionary_hashable_name(value) == ''
			assert dictionary_hashable_output(resolved[0], value, false, 105 * 256) == 'Vinix Swift runtime: Fatal error: dictionary Hashable diagnostic key type is not implemented\n'
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', dictionary_hashable_symbol + 'Extra') == none
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', dictionary_hashable_symbol) == none
		assert ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0 && ios_runtime.live == 0
		objc_stop()
		$if macos { assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1 }
		$else { mut resident := u8(0); assert C.mincore(unsafe { voidptr(arena) }, page, unsafe { &resident }) == -1 }
	}
	println('IOS-DICTIONARY-HASHABLE: canonical String/Int/Bool exact diagnostics, opaque protected metadata rejection, closed stderr, actual BRK/SIGTRAP, eight cold publishers, shared sealed assertion arena and two drained/unmapped lifetimes')
}
