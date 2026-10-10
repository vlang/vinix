// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)

type HashCall = fn (u64, u64, u64, u64, u64, u64, &u64) i64
type HashSign = fn (u64, u64) u64

struct HashApi {
	native bool
	entries [5]u64
}
struct HashProbe {
	call u64
	raw u64
	getter u64
	into u64
	sign u64
}
struct HashScenario {
	api HashApi
	probe HashProbe
	source u64
	bytes u64
	length usize
	owner u64
	result i64
	reenter bool
mut:
	metadata u64
	table u64
	seed i64
	hasher u64
	raw_calls u64
	getter_calls u64
	into_calls u64
}

fn hash_refs(api HashApi, owner u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) } }
	return obj_header(owner).refs
}
fn hash_scenario(metadata u64, table u64, receiver u64) &HashScenario {
	mut scenario := unsafe { &HashScenario(read64(metadata + 8)) }
	assert metadata == scenario.metadata && table == scenario.table && receiver == scenario.source
	assert C.memcmp(unsafe { voidptr(receiver) }, unsafe { voidptr(scenario.bytes) }, scenario.length) == 0
	if scenario.owner != 0 { assert hash_refs(scenario.api, scenario.owner) == 1 }
	return scenario
}
fn hash_raw_callback(seed i64, metadata u64, table u64, receiver u64) i64 {
	mut scenario := hash_scenario(metadata, table, receiver)
	assert seed == scenario.seed
	scenario.raw_calls++
	if scenario.reenter {
		worker := spawn hash_worker(scenario.api, scenario.probe, scenario.result, 1)
		worker.wait()
	}
	return scenario.result
}
fn hash_getter_callback(metadata u64, table u64, receiver u64) i64 {
	mut scenario := hash_scenario(metadata, table, receiver)
	scenario.getter_calls++
	return -17 // Deliberately distinct from _rawHashValue, detecting the wrong slot.
}
fn hash_into_callback(hasher u64, metadata u64, table u64, receiver u64) {
	mut scenario := hash_scenario(metadata, table, receiver)
	assert hasher == scenario.hasher
	scenario.into_calls++
	unsafe { *(&u64(hasher)) ^= 0x9f123456789abcde }
}
fn hash_emit_bridge(code u64, body u64, instruction u32) {
	write32(code, instruction)
	write32(code + 4, 0x58000070)
	write32(code + 8, 0xd61f0200)
	write32(code + 12, 0xd503201f)
	unsafe { *(&u64(code + 16)) = body }
}
fn hash_probe_emit(code u64) HashProbe {
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd,
		0xaa0603f3, // mov x19,x6 (context output)
		0xaa0403f4, // mov x20,x4 (initial context)
		0xaa0503f0, // mov x16,x5 (entry)
		0xd63f0200, 0xf9000274, // blr x16; str x20,[x19]
		0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	hash_emit_bridge(code + 64, u64(unsafe { voidptr(hash_raw_callback) }), 0xaa1403e3) // x3 = self
	hash_emit_bridge(code + 96, u64(unsafe { voidptr(hash_getter_callback) }), 0xaa1403e2) // x2 = self
	hash_emit_bridge(code + 128, u64(unsafe { voidptr(hash_into_callback) }), 0xaa1403e3)
	write32(code + 160, 0xdac10020) // pacia x0,x1: native arm64e fixture only.
	write32(code + 164, 0xd65f03c0)
	return HashProbe{ call: code, raw: code + 64, getter: code + 96, into: code + 128, sign: code + 160 }
}
fn hash_call(api HashApi, probe HashProbe, slot int, a u64, b u64, c u64, d u64, context u64) i64 {
	call := unsafe { HashCall(voidptr(probe.call)) }
	mut returned_context := u64(0)
	result := call(a, b, c, d, context, api.entries[slot], unsafe { &returned_context })
	assert returned_context == context
	return result
}
fn hash_value(api HashApi, probe HashProbe, source u64, expected u64, length usize, owner u64, result i64, reenter bool, iterations int) {
	mut scenario := HashScenario{ api: api, probe: probe, source: source, bytes: expected,
		length: length, owner: owner, result: result, reenter: reenter }
	mut metadata := [u64(0x200), u64(unsafe { &scenario })]!
	mut table := [u64(0), u64(0), probe.getter, probe.into, probe.raw]!
	mut raw_representable := [u64(0xdead), u64(0xbeef), u64(0xabcd), u64(0x9876), u64(0)]!
	mut raw_value := [u64(0), u64(1), u64(2), u64(3), u64(4)]!
	scenario.metadata = u64(unsafe { &metadata[0] })
	scenario.table = u64(unsafe { &table[0] })
	$if macos {
		if api.native {
			sign := unsafe { HashSign(voidptr(probe.sign)) }
			for slot, discriminator in { 2: u64(619), 3: 15753, 4: 50202 } {
				table[slot] = sign(table[slot], (scenario.table + u64(slot * 8)) | (discriminator << 48))
			}
		}
	}
	for _ in 0 .. iterations {
		scenario.seed = 0
		assert hash_call(api, probe, 0, scenario.metadata, scenario.table,
			u64(unsafe { &raw_representable[0] }), u64(unsafe { &raw_value[0] }), source) == result
		// A free function temporarily uses its borrowed value as Swift context
		// and restores the caller's distinct context rather than leaving Self there.
		assert hash_call(api, probe, 1, source, scenario.metadata, scenario.table, 0, u64(unsafe { &raw_value[1] })) == result
		assert hash_call(api, probe, 2, scenario.metadata, scenario.table, 0, 0, source) == -17
		for seed in [i64(0), 1, -1, i64(-9223372036854775807) - 1, i64(0x7fffffffffffffff)]! {
			scenario.seed = seed
			assert hash_call(api, probe, 4, u64(seed), scenario.metadata, scenario.table, 0, source) == result
		}
		mut hasher := [u64(0xdeadbeef), u64(0x12345678), u64(0xcafebabe)]!
		scenario.hasher = u64(unsafe { &hasher[1] })
		hash_call(api, probe, 3, scenario.hasher, scenario.metadata, scenario.table, 0, source)
		assert hasher[0] == 0xdeadbeef && hasher[2] == 0xcafebabe
		assert hasher[1] == (u64(0x12345678) ^ u64(0x9f123456789abcde))
	}
	assert scenario.raw_calls == u64(iterations * 7)
	assert scenario.getter_calls == u64(iterations) && scenario.into_calls == u64(iterations)
	assert C.memcmp(unsafe { voidptr(source) }, unsafe { voidptr(expected) }, length) == 0
	if owner != 0 { assert hash_refs(api, owner) == 1 }
}
fn hash_worker(api HashApi, probe HashProbe, result i64, iterations int) {
	if !api.native {
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSYsSHRzSH8RawValueSYRpzrlE04hashB0Sivg') or { panic(err) } == api.entries[0]
	}
	bytes := C.malloc(1); expected := C.malloc(1)
	assert bytes != unsafe { nil } && expected != unsafe { nil }
	defer { C.free(bytes); C.free(expected) }
	unsafe { *(&u8(bytes)) = 0x73; *(&u8(expected)) = 0x73 }
	hash_value(api, probe, u64(bytes), u64(expected), 1, 0, result, false, iterations)
}
fn hash_run(api HashApi, probe HashProbe) {
	for result in [i64(0), 42, -1, i64(-9223372036854775807) - 1, i64(0x7fffffffffffffff)]! {
		hash_worker(api, probe, result, 1)
	}
	mut bytes := [u64(0xabcdef1234567890), u64(0x9876543210fedcba)]!
	mut expected := bytes
	hash_value(api, probe, u64(unsafe { &bytes[0] }), u64(unsafe { &expected[0] }), 16, 0, -1, true, 1)
	mut owner := u64(0)
	$if macos { if api.native { owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0)) } }
	if !api.native { owner = owned_string('borrowed opaque Hashable owner') }
	mut reference := owner; mut expected_reference := owner
	hash_value(api, probe, u64(unsafe { &reference }), u64(unsafe { &expected_reference }), 8, owner, 42, false, 1)
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(owner) }) } }
	if !api.native { objc_release(owner) }
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn hash_worker(api, probe, i64(i) - 4, 200) }
	workers.wait()
}
fn hash_resolve_worker() {
	symbols := ['_$sSYsSHRzSH8RawValueSYRpzrlE04hashB0Sivg', '_$ss10_hashValue3forSix_tSHRzlF',
		'_$sSH9hashValueSivgTj', '_$sSH4hash4intoys6HasherVz_tFTj', '_$sSH13_rawHashValue4seedS2i_tFTj']!
	offsets := [u64(0), 32, 96, 128, 160]!
	mut base := u64(0)
	for iteration in 0 .. 50 {
		for i, name in symbols {
			entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
			if iteration == 0 && i == 0 { base = entry }
			assert entry == base + offsets[i]
			assert unsafe { *(&u32(base)) } == 0xf9401030 // Fully emitted before publication.
		}
	}
}
fn test_swift_hash_forwarding() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page) == 0 }
	probe := hash_probe_emit(u64(code))
	C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 168) })
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	symbols := ['_$sSYsSHRzSH8RawValueSYRpzrlE04hashB0Sivg', '_$ss10_hashValue3forSix_tSHRzlF',
		'_$sSH9hashValueSivgTj', '_$sSH4hash4intoys6HasherVz_tFTj', '_$sSH13_rawHashValue4seedS2i_tFTj']!
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		mut entries := [5]u64{}
		for i, name in symbols { entries[i] = u64(C.dlsym(lib, name[1..].str)); assert entries[i] != 0 }
		hash_run(HashApi{ native: true, entries: entries }, probe)
		println('IOS-SWIFT-HASH-NATIVE: generic hashValue and Hashable dispatch, measured witness slots/argument order, signed seeds/results, borrowed opaque receivers, preserved contexts, guarded inout state and reentrant/concurrent callbacks')
	}
	for _ in 0 .. 2 {
		objc_start()
		assert ios_runtime.swift_hash_code == 0
		mut resolvers := []thread{}
		for _ in 0 .. 8 { resolvers << spawn hash_resolve_worker() }
		resolvers.wait()
		mut entries := [5]u64{}
		for i, name in symbols {
			entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } == entries[i]
		}
		assert ios_runtime.swift_hash_code == entries[0] && ios_runtime.swift_metadata_arena == 0
		hash_run(HashApi{ entries: entries }, probe)
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSHsE13_rawHashValue4seedS2i_tF') or { panic(err) } != 0
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss6HasherVMa') { assert false }
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_hash_code == 0 && ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_arc_code == 0
	}
	println('IOS-SWIFT-HASH: generic hashing forwards to caller witnesses, Hashable requirement dispatch, signed 64-bit seed/result boundaries, exact one-byte/16-byte/reference receivers, borrowed ownership, preserved Swift contexts, guarded inout state, concurrent publication, reentrant/eight concurrent workers and two empty teardowns')
}
