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
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)

type RawCall = fn (u64, u64, u64, u64, u64, u64, u64, &u64)
type RawLookup = fn (u64, u64, u64, u64, u64) SwiftAssociatedMetadata
type RawSign = fn (u64, u64) u64
type RawStrip = fn (u64) u64

struct RawApi {
	native          bool
	entry           u64
	protocol        u64
	lookup          u64
	string_metadata u64
	requirements    [4]u64
}

struct RawProbe {
	call      u64
	getter    u64
	into      u64
	sign_code u64
	sign_data u64
	strip     u64
}

struct RawScenario {
	api          RawApi
	probe        RawProbe
	source       u64
	payload      u64
	length       usize
	owner        u64
	reenter      bool
	string_value bool
mut:
	metadata      u64
	raw_metadata  u64
	raw_table     u64
	hash_table    u64
	hasher        u64
	temporary     u64
	phase         int
	getter_calls  int
	into_calls    int
	destroy_calls int
}

fn raw_refs(s &RawScenario) i64 {
	if s.owner == 0 { return 0 }
	$if macos {
		if s.api.native { return C.CFGetRetainCount(unsafe { voidptr(s.owner) }) }
	}
	return obj_header(s.owner).refs
}

fn raw_retain(s &RawScenario) {
	if s.owner == 0 { return }
	$if macos {
		if s.api.native {
			C.CFRetain(unsafe { voidptr(s.owner) })
			return
		}
	}
	objc_retain(s.owner)
}

fn raw_release(s &RawScenario) {
	if s.owner == 0 { return }
	$if macos {
		if s.api.native {
			C.CFRelease(unsafe { voidptr(s.owner) })
			return
		}
	}
	objc_release(s.owner)
}

fn raw_getter(metadata u64, table u64, output u64, receiver u64) {
	mut s := unsafe { &RawScenario(read64(table + 32)) }
	assert metadata == s.metadata && table == s.raw_table && receiver == s.source
	assert unsafe { *(&u8(receiver)) } == 0x79
	assert s.phase == 0 && output != receiver && output % 16 == 0
	if s.owner != 0 {
		assert raw_refs(s) == 1
	}
	s.phase = 1
	s.getter_calls++
	s.temporary = output
	raw_retain(s)
	C.memcpy(unsafe { voidptr(output) }, unsafe { voidptr(s.payload) }, s.length)
	if s.reenter {
		worker := spawn raw_lookup_worker(s.api, s.raw_table, s.metadata, s.raw_metadata, 20)
		worker.wait()
	}
}

fn raw_into(hasher u64, metadata u64, table u64, receiver u64) {
	mut s := unsafe { &RawScenario(read64(table + 40)) }
	assert metadata == s.raw_metadata && table == s.hash_table && receiver == s.temporary
	assert hasher == s.hasher && s.phase == 1
	assert C.memcmp(unsafe { voidptr(receiver) }, unsafe { voidptr(s.payload) }, s.length) == 0
	if s.owner != 0 {
		assert raw_refs(s) == 2
	}
	s.phase = 2
	s.into_calls++
	// Use a complete, guarded Hasher, and compare its state with hashing the
	// original payload. The witness may read exactly RawValue.size bytes.
	mut state := unsafe { &SwiftHasher(hasher) }
	swift_hasher_bytes(mut state, receiver, receiver + u64(s.length))
	if s.reenter {
		worker := spawn raw_lookup_worker(s.api, s.raw_table, s.metadata, s.raw_metadata, 20)
		worker.wait()
	}
}

fn raw_destroy(value u64, metadata u64) {
	mut s := unsafe { &RawScenario(read64(metadata + 8)) }
	assert metadata == s.raw_metadata && value == s.temporary && s.phase == 2
	assert C.memcmp(unsafe { voidptr(value) }, unsafe { voidptr(s.payload) }, s.length) == 0
	if s.owner != 0 {
		assert raw_refs(s) == 2
	}
	s.phase = 3
	s.destroy_calls++
	raw_release(s)
	if s.reenter {
		worker := spawn raw_lookup_worker(s.api, s.raw_table, s.metadata, s.raw_metadata, 20)
		worker.wait()
	}
}

fn raw_bridge(code u64, body u64, getter bool) {
	write32(code, if getter { u32(0xaa0803e2) } else { u32(0xd503201f) }) // x2 = indirect result x8
	write32(code + 4, 0xaa1403e3) // x3 = self x20
	write32(code + 8, 0x58000090)
	write32(code + 12, 0xd61f0200)
	unsafe { *(&u64(code + 24)) = body }
}

fn raw_probe_emit(code u64) RawProbe {
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd, 0xaa0703f3, 0xaa0503f4, 0xaa0603f0,
		0xd63f0200, 0xf9000274, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	raw_bridge(code + 64, u64(unsafe { voidptr(raw_getter) }), true)
	raw_bridge(code + 96, u64(unsafe { voidptr(raw_into) }), false)
	write32(code + 128, 0xdac10020)
	write32(code + 132, 0xd65f03c0) // pacia
	write32(code + 144, 0xdac10820)
	write32(code + 148, 0xd65f03c0) // pacda
	write32(code + 160, 0xdac147e0)
	write32(code + 164, 0xd65f03c0) // xpacd
	return RawProbe{
		call:      code
		getter:    code + 64
		into:      code + 96
		sign_code: code + 128
		sign_data: code + 144
		strip:     code + 160
	}
}

fn raw_lookup_worker(api RawApi, table u64, metadata u64, expected u64, iterations int) {
	lookup := unsafe { RawLookup(voidptr(api.lookup)) }
	for _ in 0 .. iterations {
		if !api.native {
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getAssociatedTypeWitness') or { panic(err) } == api.lookup
		}
		for request in [u64(0), 0xff, 0x100, 0x1ff]! {
			response := lookup(request, table, metadata, api.protocol + 16, api.protocol + 24)
			assert response.metadata == expected && response.state == 0
		}
	}
}

fn raw_value(api RawApi, probe RawProbe, length usize, reference bool, string_value bool, reenter bool, iterations int) {
	payload := C.malloc(if length == 0 { usize(1) } else { length })
	source := C.malloc(1)
	assert payload != unsafe { nil } && source != unsafe { nil }
	defer {
		C.free(payload)
		C.free(source)
	}
	unsafe { *(&u8(source)) = 0x79 }
	for i in 0 .. int(length) {
		unsafe { *(&u8(u64(payload) + u64(i))) = u8(i * 37 + 19) }
	}
	mut owner := u64(0)
	if reference {
		$if macos {
			if api.native { owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0)) }
		}
		if !api.native { owner = owned_string('RawValue owner') }
		unsafe { *(&u64(payload)) = owner }
		if string_value {
			unsafe { *(&SwiftStringWords(payload)) = SwiftStringWords{ first: 0x12345678, second: owner | (u64(1) << 62) } }
		}
	}
	mut s := RawScenario{
		api:          api
		probe:        probe
		source:       u64(source)
		payload:      u64(payload)
		length:       length
		owner:        owner
		reenter:      reenter
		string_value: string_value
	}
	mut self_metadata := [u64(0x200), u64(unsafe { &s })]!
	mut raw_metadata := [u64(0), u64(0x200), u64(unsafe { &s })]!
	mut vwt := [u64(0), u64(unsafe { voidptr(raw_destroy) }), 0, 0, 0, 0, 0, 0, u64(length),
		u64(length), u64(0x10000)]!
	mut raw_table := [u64(0), u64(0), u64(0), probe.getter, u64(unsafe { &s })]!
	mut hash_table := [u64(0), u64(0), u64(0), probe.into, u64(0), u64(unsafe { &s })]!
	mut self_hashable := [u64(0x11), 0x22, 0x33, 0x44, 0x55]!
	s.metadata = u64(unsafe { &self_metadata[0] })
	s.raw_metadata = if string_value {
		api.string_metadata
	} else {
		u64(unsafe { &raw_metadata[1] })
	}
	s.raw_table = u64(unsafe { &raw_table[0] })
	s.hash_table = u64(unsafe { &hash_table[0] })
	raw_metadata[0] = u64(unsafe { &vwt[0] })
	raw_table[1] = s.raw_metadata
	$if macos {
		if api.native {
			sign_code := unsafe { RawSign(voidptr(probe.sign_code)) }
			sign_data := unsafe { RawSign(voidptr(probe.sign_data)) }
			raw_table[1] = sign_data(raw_table[1], (s.raw_table + 8) | (u64(0x617) << 48))
			raw_table[3] = sign_code(raw_table[3], (s.raw_table + 24) | (u64(15752) << 48))
			hash_table[3] = sign_code(hash_table[3], (s.hash_table + 24) | (u64(15753) << 48))
			vwt[1] = sign_code(vwt[1], u64(unsafe { &vwt[1] }) | (u64(1272) << 48))
			raw_metadata[0] = sign_data(raw_metadata[0], u64(unsafe { &raw_metadata[0] }) | (u64(11839) << 48))
		}
	}
	raw_lookup_worker(api, s.raw_table, s.metadata, s.raw_metadata, 2)
	call := unsafe { RawCall(voidptr(probe.call)) }
	for _ in 0 .. iterations {
		mut guarded := RawHasherGuard{ state: swift_hasher_raw_seed(0x0706050403020100, 0x0f0e0d0c0b0a0908) }
		mut expected := guarded.state
		swift_hasher_bytes(mut expected, s.payload, s.payload + u64(length))
		s.hasher = u64(unsafe { &guarded.state })
		s.phase = 0
		mut returned := u64(0)
		call(s.hasher, s.metadata, u64(unsafe { &self_hashable[0] }), s.raw_table, s.hash_table,
			s.source, api.entry, unsafe { &returned })
		assert returned == s.source && unsafe { *(&u8(s.source)) } == 0x79
		assert guarded.before == 0x123456789abcdef0 && guarded.after == 0xfedcba9876543210
		assert C.memcmp(&guarded.state, &expected, 72) == 0
		assert s.phase == if string_value { 2 } else { 3 }
		if owner != 0 {
			assert raw_refs(&s) == 1
		}
	}
	assert s.getter_calls == iterations && s.into_calls == iterations
	assert s.destroy_calls == if string_value { 0 } else { iterations }
	raw_release(&s)
}

struct RawHasherGuard {
mut:
	before u64 = 0x123456789abcdef0
	state  SwiftHasher
	after  u64 = 0xfedcba9876543210
}

fn raw_tagged(api RawApi, probe RawProbe, prefix bool) {
	// A real conformance record is needed by the native mangled-name slow
	// path. Its protocol reference uses a relative indirectable pointer.
	mut record := [12]u64{}
	address := u64(unsafe { &record[0] })
	write32(address, 17)
	write32(address + 4, 28)
	record[2] = api.protocol
	write32(address + 32, 0x51)
	mut metadata := [u64(0x200), address + 32]!
	mut name := [u8(0xff), `S`, `S`, 0, 0, 0, 0, 0]!
	if !prefix {
		name[0] = `S`
		name[1] = `S`
		name[2] = 0
	}
	mut table := [address, u64(unsafe { &name[0] }) | 1, u64(0), u64(0)]!
	tp := u64(unsafe { &table[0] })
	$if macos {
		if api.native {
			sign := unsafe { RawSign(voidptr(probe.sign_data)) }
			table[1] = sign(table[1], (tp + 8) | (u64(0x617) << 48))
		}
	}
	mut workers := []thread{}
	for _ in 0 .. 8 {
		workers << spawn raw_lookup_worker(api, tp, u64(unsafe { &metadata[0] }), api.string_metadata, 50)
	}
	workers.wait()
	mut stored := table[1]
	$if macos {
		if api.native {
			strip := unsafe { RawStrip(voidptr(probe.strip)) }
			stored = strip(stored)
		}
	}
	assert stored == api.string_metadata
}

fn raw_other_slots(api RawApi, probe RawProbe) {
	mut requirements := [16]u64{}
	mut table := [16]u64{}
	base := u64(unsafe { &requirements[0] })
	tp := u64(unsafe { &table[0] })
	lookup := unsafe { RawLookup(voidptr(api.lookup)) }
	for index in [1, 3, 7, 15]! {
		write32(base + u64(index * 8), 0x12340007)
		table[index] = api.string_metadata
		$if macos {
			if api.native {
				sign := unsafe { RawSign(voidptr(probe.sign_data)) }
				table[index] = sign(table[index], (tp + u64(index * 8)) | (u64(0x1234) << 48))
			}
		}
		prior := table[index]
		for request in [u64(0), 0xff, 0x100, 0x1ff]! {
			response := lookup(request, tp, api.string_metadata, base, base + u64(index * 8))
			assert response.metadata == api.string_metadata && response.state == 0
			assert table[index] == prior
		}
	}
}

fn raw_run(api RawApi, probe RawProbe) {
	for i, offset in [u64(16), 24, 32, 40]! {
		assert api.requirements[i] == api.protocol + offset
	}
	raw_other_slots(api, probe)
	assert unsafe { *(&u32(api.protocol)) } == 0x30043
	assert unsafe { *(&u32(api.protocol + 12)) } == 0 && unsafe { *(&u32(api.protocol + 16)) } == 3
	assert unsafe { *(&u32(api.protocol + 24)) } == 0x06170007
	assert unsafe { *(&u32(api.protocol + 32)) } == 0x3b260002
	assert unsafe { *(&u32(api.protocol + 40)) } == 0x3d880013
	for prefix in [false, true]! { raw_tagged(api, probe, prefix) }
	for length in [usize(0), 1, 3, 8, 16, 17, 33, 257, 8193]! {
		raw_value(api, probe, length, false, false, length == 17, 2)
	}
	raw_value(api, probe, 8, true, false, true, 2)
	raw_value(api, probe, 16, true, true, true, 2)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn raw_value(api, probe, 33, false, false, false, 100) }
	workers.wait()
}

fn test_swift_raw_representable() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page) == 0 }
	probe := raw_probe_emit(u64(code))
	C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 168) })
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	symbol := '_$sSYsSHRzSH8RawValueSYRpzrlE4hash4intoys6HasherVz_tF'
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		mut requirements := [4]u64{}
		for i, name in raw_requirement_symbols {
			requirements[i] = u64(C.dlsym(lib, name[1..].str))
		}
		api := RawApi{
			native:          true
			entry:           u64(C.dlsym(lib, symbol[1..].str))
			protocol:        u64(C.dlsym(lib, c'$sSYMp'))
			lookup:          u64(C.dlsym(lib, c'swift_getAssociatedTypeWitness'))
			string_metadata: u64(C.dlsym(lib, c'$sSSN'))
			requirements:    requirements
		}
		assert api.entry != 0 && api.protocol != 0 && api.lookup != 0 && api.string_metadata != 0
		raw_run(api, probe)
		println('IOS-SWIFT-RAW-NATIVE: RawRepresentable hash-into argument/context/result ABI, associated metadata data slots, tagged String cache with both contexts, native descriptor flags, owned temporary getter/hash/destroy ordering, exact payload sizes and native String destruction, reentrant/concurrent callbacks')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut requirements := [4]u64{}
		for i, name in raw_requirement_symbols {
			requirements[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) }
		}
		api := RawApi{
			entry:           runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol) or { panic(err) }
			protocol:        runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$sSYMp') or { panic(err) }
			lookup:          runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_getAssociatedTypeWitness') or { panic(err) }
			string_metadata: swift_string_metadata()
			requirements:    requirements
		}
		raw_run(api, probe)
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_hash_code == 0 && ios_runtime.swift_metadata_arena == 0
	}
	println('IOS-SWIFT-RAW: RawRepresentable hash-into default, complete associated metadata and tagged String atomic cache, genuine protocol descriptor, borrowed Self/owned RawValue, exact zero/one/odd/large payloads, 16-byte stack alignment, getter x8 result, distinct metadata/tables/contexts, guarded Hasher, String/reference retain/destroy balance, reentry/eight workers and two empty teardowns')
}

const raw_requirement_symbols = ['_$sSYTL', '_$s8RawValueSYTl', '_$sSY8rawValuexSg03RawB0Qz_tcfCTq',
	'_$sSY8rawValue03RawB0QzvgTq']!
