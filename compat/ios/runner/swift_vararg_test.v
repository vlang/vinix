// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.mincore(voidptr, usize, &u8) i32
type VarargProbe = fn (u64, u64, u64, u64, u64, &u64) u64
type VarargGetter = fn (u64) u64
type VarargSign = fn (u64, u64) u64
type VarargRetain = fn (u64) u64
type VarargRelease = fn (u64)
type VarargArray = fn (u64, u64) SwiftAssociatedMetadata
type VarargCopy = fn (u64, u64, u64) u64
type VarargDestroy = fn (u64, u64)

const vararg_symbols = ['_$ss7CVarArgMp', '_$ss7CVarArgTL',
	'_$ss7CVarArgP05_cVarB8EncodingSaySiGvgTq', '_$ss7CVarArgP05_cVarB8EncodingSaySiGvgTj',
	'_$sSis7CVarArgsWP', '_$sSis7CVarArgsMc', '_$sSi16_cVarArgEncodingSaySiGvg', '_$sSiN']!
const vararg_unsupported = ['_swift_getExistentialTypeMetadata', '_swift_conformsToProtocol',
	'_$ss9getVaListys03CVaC7PointerVSays7CVarArg_pGF']!
struct VarargApi {
	native bool
	entries [8]u64
	@[required]
	probe VarargProbe
	@[required]
	retain VarargRetain
	@[required]
	release VarargRelease
	@[required]
	array VarargArray
}
struct VarargTarget {
	native bool
	self u64
	mask u64
	@[required]
	getter VarargGetter
mut:
	table u64
}

fn vararg_relative(field u64) u64 { return u64(i64(field) + i64(unsafe { *(&i32(field)) })) }
fn vararg_resolve() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_$ss7CVarArgMp') or { panic(err) }
}
fn vararg_target(metadata u64, table u64, source u64) u64 {
	target := unsafe { &VarargTarget(metadata) }
	assert table == target.table && source == target.self
	if !target.native {
		worker := spawn vararg_resolve()
		assert worker.wait() != 0
	}
	return target.getter(read64(source) ^ target.mask)
}
fn vararg_layout(api VarargApi) {
	protocol := api.entries[0]; conformance := api.entries[5]; table := api.entries[4]
	assert unsafe { *(&u32(protocol)) } == 0x30043
	assert unsafe { (&u8(vararg_relative(protocol + 8))).vstring() } == 'CVarArg'
	parent := vararg_relative(protocol + 4)
	assert unsafe { (&u8(vararg_relative(parent + 8))).vstring() } == 'Swift'
	assert unsafe { *(&u32(protocol + 12)) } == 0 && unsafe { *(&u32(protocol + 16)) } == 1
	assert unsafe { *(&u32(protocol + 20)) } == 0
	assert unsafe { *(&u32(protocol + 24)) } == 0x95c40013 && unsafe { *(&u32(protocol + 28)) } == 0
	assert api.entries[1] == protocol + 16 && api.entries[2] == protocol + 24
	assert read64(table) & swift_address_mask == conformance && read64(table + 8) != 0
	assert vararg_relative(conformance) == protocol
	assert vararg_relative(conformance + 4) == read64(api.entries[7] + 8) & swift_address_mask
	assert vararg_relative(conformance + 8) == table && unsafe { *(&u32(conformance + 12)) } == 0
}
fn vararg_value(api VarargApi, bits u64) {
	mut source := [u64(0x123456789abcdef0), bits, 0xfedcba9876543210]!
	self := u64(unsafe { &source[1] })
	for mode in 0 .. 3 {
		entry := if mode == 0 { api.entries[6] } else if mode == 1 { read64(api.entries[4] + 8) } else { api.entries[3] }
		mut context := u64(0)
		owner := api.probe(if mode == 0 { bits } else { api.entries[7] },
			if mode == 0 { u64(0) } else { api.entries[4] }, 0, self, entry, unsafe { &context })
		assert context == self && source == [u64(0x123456789abcdef0), bits, 0xfedcba9876543210]!
		assert read64(owner + 16) == 1 && read64(owner + 24) & 1 == 0
		assert read64(owner + 24) >> 1 >= 1 && read64(owner + 32) == bits && read64(owner + 8) == 3
		assert api.retain(owner) == owner
		api.release(owner); assert read64(owner + 8) == 3
		// Ordinary Array witnesses retain an alias; either alias may die first.
		metadata := api.array(0, api.entries[7]).metadata
		witness := read64(metadata - 8) & swift_address_mask
		copy_value := unsafe { VarargCopy(voidptr(read64(witness + 16))) }
		destroy := unsafe { VarargDestroy(voidptr(read64(witness + 8))) }
		mut value := owner; mut alias := u64(0)
		assert copy_value(u64(unsafe { &alias }), u64(unsafe { &value }), metadata) == u64(unsafe { &alias })
		assert alias == owner && read64(owner + 8) == 0x200000003
		destroy(u64(unsafe { &value }), metadata)
		assert read64(owner + 8) == 3 && read64(owner + 32) == bits
		destroy(u64(unsafe { &alias }), metadata)
	}
}
fn vararg_custom(api VarargApi, code u64) {
	mut source := u64(0xdeadbeef12345678)
	mut target := VarargTarget{ native: api.native, self: u64(unsafe { &source }), mask: 0xa5a5a5a5a5a5a5a5,
		getter: unsafe { VarargGetter(voidptr(api.entries[6])) } }
	mut table := [u64(0), code + 64]!
	target.table = u64(unsafe { &table[0] })
	$if macos {
		if api.native {
			sign := unsafe { VarargSign(voidptr(code + 96)) }
			table[1] = sign(table[1], (target.table + 8) | (u64(0x95c4) << 48))
		}
	}
	mut context := u64(0)
	owner := api.probe(u64(unsafe { &target }), target.table, 0, target.self, api.entries[3], unsafe { &context })
	assert context == target.self && source == 0xdeadbeef12345678
	assert read64(owner + 16) == 1 && read64(owner + 32) == source ^ target.mask
	api.release(owner)
}
fn vararg_worker(api VarargApi, index int) {
	for i in 0 .. 64 { vararg_value(api, (u64(1) << u32(i)) ^ (u64(index) << 56)) }
}
fn vararg_run(api VarargApi, code u64) {
	vararg_layout(api)
	for bits in [u64(0), 1, 0x7fffffffffffffff, 0x8000000000000000, 0xffffffffffffffff]! { vararg_value(api, bits) }
	vararg_custom(api, code)
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn vararg_worker(api, i) }
	workers.wait()
}
fn test_swift_vararg() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, instruction in [u32(0xa9be7bfd), 0xa90153f3, 0x910003fd, 0xaa0503f3, 0xaa0303f4,
		0xaa0403f0, 0xd63f0200, 0xf9000274, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(code + u64(i * 4), instruction) }
	write32(code + 64, 0xaa1403e2) // mov x2,x20
	write32(code + 68, 0x58000070) // ldr x16,literal +80
	write32(code + 72, 0xd61f0200); write32(code + 76, 0xd503201f)
	unsafe { *(&u64(code + 80)) = u64(voidptr(vararg_target)) }
	write32(code + 96, 0xdac10020); write32(code + 100, 0xd65f03c0) // Native fixture's PACIA x0,x1; ret.
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 104) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	defer { assert C.munmap(unsafe { voidptr(code) }, page) == 0 }
	probe := unsafe { VarargProbe(voidptr(code)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		for symbol in vararg_unsupported { assert C.dlsym(lib, symbol[1..].str) != unsafe { nil }, symbol }
		mut entries := [8]u64{}
		for i, symbol in vararg_symbols { entries[i] = u64(C.dlsym(lib, symbol[1..].str)); assert entries[i] != 0, symbol }
		vararg_run(VarargApi{ native: true, entries: entries, probe: probe,
			retain: unsafe { VarargRetain(C.dlsym(lib, c'swift_bridgeObjectRetain')) }, release: unsafe { VarargRelease(C.dlsym(lib, c'swift_bridgeObjectRelease')) },
			array: unsafe { VarargArray(C.dlsym(lib, c'$sSaMa')) } }, code)
		println('IOS-SWIFT-VARARG-NATIVE: installed descriptors and aliases, direct/indirect/generic Int encodings, owned Array witnesses, signed arbitrary callback dispatch, preserved context and eight workers')
	}
	for _ in 0 .. 2 {
		objc_start(); library := '/usr/lib/swift/libswiftCore.dylib'
		mut resolvers := []thread u64{}
		for _ in 0 .. 8 { resolvers << spawn vararg_resolve() }
		resolved := resolvers.wait(); for address in resolved { assert address == resolved[0] && address != 0 }
		mut entries := [8]u64{}
		for i, symbol in vararg_symbols { entries[i] = runtime_symbol(library, symbol) or { panic(err) } }
		vararg_run(VarargApi{ entries: entries, probe: probe, retain: swift_bridge_retain, release: swift_bridge_release, array: swift_array_access }, code)
		assert ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.swift_strings.len == 0 && ios_runtime.objects.len == 0
		for symbol in vararg_unsupported {
			assert runtime_symbol(library, symbol) == none
		}
		arena := ios_runtime.swift_integer_arena
		objc_stop()
		assert ios_runtime.swift_integer_arena == 0 && ios_runtime.swift_array_arena == 0 && ios_runtime.live == 0
		for offset in 0 .. 2 {
			address := arena + u64(offset) * u64(page)
			$if macos { assert C.mprotect(unsafe { voidptr(address) }, page, C.PROT_READ) == -1 }
			$else { mut residency := u8(0); assert C.mincore(unsafe { voidptr(address) }, page, &residency) == -1 }
		}
	}
	println('IOS-SWIFT-VARARG: real sealed CVarArg/Int conformance records, exact owned word encoding, actual witness dispatch, borrowed Self and preserved contexts, Array aliases, reentrant resolver, eight workers and two drained/unmapped teardowns')
}
