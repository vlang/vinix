// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type State2Lookup = fn (u64, u64, u64, u64, u64) u64
type State2Probe = fn (u64, u64, u64, u64, u64, u64, &u64, u64)
type State2Array = fn (u64, u64) SwiftAssociatedMetadata
__global state2_guard = u64(0)

fn state2_case(lookup State2Lookup, probe State2Probe, request u64, name u64, length u64, context u64, args u64, expected u64) {
	mut words := [u64(0x1234), 0, 0, 0, 0, 0, 0x5678]!
	probe(request, name, length, context, args, u64(unsafe { voidptr(lookup) }), unsafe { &words[1] },state2_guard)
	assert words[0] == 0x1234 && words[6] == 0x5678 && words[1] == expected
	assert words[3] == state2_guard && words[4] == 0x5121 && words[5] == 0x5222
}

fn state2_basics(lookup State2Lookup, probe State2Probe, integer u64, text u64, void_metadata u64, array_access State2Array, context u64) {
	mut args := [text]!
	for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
		for _ in 0 .. 32 {
			for name, metadata in {'Si': integer, 'SS': text, 'S': text, 'yt': void_metadata,
				'SaySSG': array_access(0, text).metadata, 'SaySaySiGG': array_access(0, array_access(0, integer).metadata).metadata,
				'Si\x00unused': integer, '': u64(0), 'Say': u64(0)} {
				state2_case(lookup, probe, request, u64(name.str), u64(name.len), 0, 0, metadata)
			}
			state2_case(lookup, probe, request, u64('x'.str), 1, context, u64(unsafe { &args[0] }), text)
			state2_case(lookup, probe, request, u64('SayxG'.str), 5, context, u64(unsafe { &args[0] }), array_access(0, text).metadata)
		}
	}
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	name := base + u64(page) - 2
	unsafe { *(&u8(name)) = `S`; *(&u8(name + 1)) = `i` }
	assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_NONE) == 0
	for request in [u64(0), 0xff, 0x1ff]! {
		state2_case(lookup, probe, request, name, 2, base + u64(page), base + u64(page), integer)
		state2_case(lookup, probe, request, base + u64(page), 0, 0, 0, 0)
	}
	assert C.munmap(voidptr(base), page * 2) == 0
}

fn state2_symbolic(name u64, tag u8, target u64) {
	unsafe { *(&u8(name)) = tag }
	delta := u32(i32(i64(target) - i64(name + 1)))
	for i in u64(0) .. 4 { unsafe { *(&u8(name + 1 + i)) = u8(delta >> (i * 8)) } }
}

fn state2_fixture(base u64, metadata u64) u64 {
	page := u64(C.getpagesize()); descriptor := base + page + 64; parent := base + page + 128
	trace := base + page * 2 + 32
	// Borrowed accessor records the effective request and returns Complete.
	for i, word in [u32(0x58000109), 0xf9000120, 0x58000080, 0xd2800001, 0xd65f03c0]! { write32(base + u64(i * 4), word) }
	unsafe { *(&u64(base + 24)) = metadata; *(&u64(base + 32)) = trace }
	write32(descriptor, 0x51); write32(descriptor + 24, 2)
	swift_protocol_relative(descriptor + 4, parent); swift_protocol_relative(descriptor + 8, base + page + 192)
	swift_protocol_relative(descriptor + 12, base); swift_protocol_relative(parent + 8, base + page + 224)
	C.memcpy(voidptr(base + page + 192), c'Fixture', 8); C.memcpy(voidptr(base + page + 224), c'VinixState2', 11)
	C.__builtin___clear_cache(voidptr(base), voidptr(base + 40)); assert C.mprotect(voidptr(base), usize(page), C.PROT_READ | C.PROT_EXEC) == 0
	return descriptor
}

fn state2_nominals(lookup State2Lookup, probe State2Probe, integer u64, native bool) {
	page := usize(C.getpagesize()); base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	descriptor := state2_fixture(base, integer); name := base + u64(page) + 256; slot := name + 64; trace := base + u64(page) * 2 + 32
	for flags in if native { [u32(0x51)] } else { [u32(0x50), 0x51, 0x52] } {
		write32(descriptor, flags)
		for tag in [u8(1), 2]! {
			unsafe { *(&u64(slot)) = descriptor }; state2_symbolic(name, tag, if tag == 1 { descriptor } else { slot })
			assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_READ) == 0
			for request in [u64(0), 0x3f, 0xff, 0x100, 0x13f, 0x1ff]! {
				for iteration in 0 .. 32 {
					unsafe { *(&u64(trace)) = ~u64(0) }
					state2_case(lookup, probe, request, name, 5, 0, 0, integer)
					assert read64(trace) == 0xff
					if native && tag == 1 && iteration == 0 { println('NATIVE-MANGLED-STATE2-REQUEST: input=' + request.hex() + ' accessor=' + read64(trace).hex()) }
				}
			}
			assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
		}
	}
	assert C.munmap(voidptr(base), page * 3) == 0
}

fn state2_native(probe State2Probe) {
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); assert lib != unsafe { nil }
		entry := C.dlsym(lib,c'swift_getTypeByMangledNameInContextInMetadataState2'); assert entry != unsafe { nil }
		lookup := unsafe { State2Lookup(entry) }
		array_access := unsafe { State2Array(C.dlsym(lib, c'$sSaMa')) }; integer := u64(C.dlsym(lib, c'$sSiN'))
		state2_basics(lookup, probe, integer, u64(C.dlsym(lib, c'$sSSN')), u64(C.dlsym(lib, c'$sytN')) + 8, array_access, u64(C.dlsym(lib, c'$sSaMn')))
		state2_nominals(lookup, probe, integer, true)
		println('NATIVE-MANGLED-STATE2: five-argument pointer result, six Complete/LayoutComplete/Abstract request forms, forced blocking accessor traces, canonical builtins/nested Arrays/generic substitution, direct/indirect nominal accessors, embedded zero bytes, protected span ends and unused inputs, read-only descriptors/names, guarded result and x20/x21')
	}
}

__global state2_access_calls = u64(0)
__global state2_access_request = u64(0)
fn state2_worker() u64 {
	metadata := swift_array_access(0, swift_string_metadata()).metadata
	for _ in 0 .. 256 { assert swift_mangled_state2_lookup(0x1ff, u64(c'SaySSG'), 6, 0, 0) == metadata }
	return metadata
}
fn state2_reentry(request u64) SwiftAssociatedMetadata {
	state2_access_request = request; state2_access_calls++
	worker := spawn state2_worker(); assert worker.wait() == swift_array_access(0, swift_string_metadata()).metadata
	return SwiftAssociatedMetadata{metadata: swift_integer_metadata()}
}
fn state2_incomplete(request u64) SwiftAssociatedMetadata { state2_access_request = request; return SwiftAssociatedMetadata{metadata: swift_integer_metadata(), state: 0xff} }
fn state2_reject(request u64, name u64, length u64, context u64, args u64) {
	if _ := swift_mangled_state2_lookup_checked(request, name, length, context, args) { assert false, 'unsupported metadata-state lookup accepted' }
}
fn state2_suite(probe State2Probe) {
	lookup := unsafe { State2Lookup(voidptr(runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getTypeByMangledNameInContextInMetadataState2') or { panic(err) })) }
	integer := swift_integer_metadata(); text := swift_string_metadata(); descriptor := swift_array_arena() + u64(C.getpagesize()) + 160
	state2_basics(lookup, probe, integer, text, swift_void_full_metadata() + 8, swift_array_access, descriptor); state2_nominals(lookup, probe, integer, false)
	for request in [u64(1), 0x42, 0x200, ~u64(0)]! { state2_reject(request, 1, 1, 1, 1) }
	for name in ['Sb', 'SSSg', 'SaySSGG', 'SSx']! { state2_reject(0xff, u64(name.str), u64(name.len), 0, 0) }
	// Value is now recognized generic syntax; a missing context has no type.
	assert lookup(0xff, u64(c'q_'), 2, 0, 0) == 0
	state2_reject(0, 0, 1, 0, 0); state2_reject(0, 1, 1048577, 0, 0); state2_reject(0, ~u64(0) - 1, 2, 0, 0)
	page := usize(C.getpagesize()); base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	nominal := state2_fixture(base, integer); name := base + u64(page) + 256; state2_symbolic(name, 1, nominal)
	assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
	write32(base, 0x58000050); write32(base + 4, 0xd61f0200); unsafe { *(&u64(base + 8)) = u64(voidptr(state2_reentry)) }
	C.__builtin___clear_cache(voidptr(base), voidptr(base + 16)); assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_EXEC) == 0
	state2_access_calls = 0; assert lookup(0x1ff, name, 5, 0, 0) == integer && state2_access_calls == 1 && state2_access_request == 0xff
	unsafe { *(&u8(name + 5)) = `?` }; state2_reject(0xff, name, 6, 0, 0); state2_reject(0x200, name, 5, 0, 0); assert state2_access_calls == 1
	assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
	unsafe { *(&u64(base + 8)) = u64(voidptr(state2_incomplete)) }; C.__builtin___clear_cache(voidptr(base), voidptr(base + 16)); assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_EXEC) == 0
	state2_reject(0xff, name, 5, 0, 0); assert state2_access_request == 0xff
	write32(nominal, 0xd1); state2_reject(0xff, name, 5, 0, 0); write32(nominal, 0x51); write32(nominal + 12, 0); state2_reject(0xff, name, 5, 0, 0)
	assert C.munmap(voidptr(base), page * 3) == 0
	mut workers := []thread u64{}; for _ in 0 .. 8 { workers << spawn state2_worker() }; results := workers.wait(); for metadata in results { assert metadata == swift_array_access(0, text).metadata }
	unsafe { workers.free(); results.free() }
	ios_runtime.swift_concurrency_retired = true; state2_reject(0, 1, 1, 1, 1); ios_runtime.swift_concurrency_retired = false
	if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_getTypeByMangledNameInContextInMetadataState2') { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_getTypeByMangledNameInContextInMetadataState2') { assert false }
	assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
}
fn test_swift_mangled_state2_lookup() {
	page := usize(C.getpagesize()); code := u64(C.mmap(unsafe { nil }, page*2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != u64(-1)
	for i, word in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0603f3,0xaa0503f0,0xaa0703f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0703e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! { write32(code + u64(i * 4), word) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 68)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	state2_guard = code + u64(page); assert C.mprotect(voidptr(state2_guard),page,C.PROT_NONE) == 0
	probe := unsafe { State2Probe(voidptr(code)) }; state2_native(probe)
	state2_reject(0,state2_guard,0,state2_guard,state2_guard)
	for _ in 0 .. 2 {
		objc_start(); state2_suite(probe); objc_stop()
		state2_reject(0,state2_guard,0,state2_guard,state2_guard)
		assert ios_runtime.swift_array_metadata.len == 0 && ios_runtime.swift_array_arena == 0 && ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_integer_arena == 0 && ios_runtime.swift_void_arena == 0 && ios_runtime.swift_objc_metadata.len == 0
	}
	assert C.munmap(voidptr(code), page*2) == 0
	println('IOS-MANGLED-STATE2: exact Core-only five-argument ABI, shared complete metadata/parser/caches, blocking request propagation, canonical builtins/Arrays/generic and nominal cases, bounded syntax/state/lifetime rejection before callbacks, incomplete-response rejection, unlocked accessor reentry, eight readers and two drained lifetimes')
}
