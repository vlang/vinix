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
fn C.CFStringAppendCString(voidptr, &char, u32)
fn C.CFGetRetainCount(voidptr) i64

type ProtocolWriteCall = fn (u64, u64, u64, u64, u64, u64, u64, &u64)
type ProtocolDescriptionCall = fn (u64, u64, u64, u64, &u64) SwiftStringWords
type ProtocolRelease = fn (u64)
type ProtocolCString = fn (&u8) SwiftStringWords
type ProtocolSign = fn (u64, u64) u64

struct ProtocolApi {
	native bool
	metadata u64
	text_table u64
	description_table u64
	@[required]
	release ProtocolRelease
}
struct ProtocolProbe {
	write_entry u64
	description_entry u64
	target_entry u64
	sign_entry u64
}
struct ProtocolStream {
	api ProtocolApi
	probe ProtocolProbe
	metadata u64
	table u64
	source u64
	owner u64
	refs u64
	native_heap bool
	reenter bool
mut:
	calls u64
	observed SwiftStringWords
}

fn protocol_refs(api ProtocolApi, owner u64, native_heap bool) u64 {
	if native_heap { return (read64(owner + 8) >> 33) + 1 }
	$if macos { if api.native { return u64(C.CFGetRetainCount(unsafe { voidptr(owner) })) } }
	return u64(obj_header(owner).refs)
}
fn protocol_describe(api ProtocolApi, probe ProtocolProbe, source u64) SwiftStringWords {
	call := unsafe { ProtocolDescriptionCall(voidptr(probe.description_entry)) }
	mut context := u64(0)
	result := call(source, api.metadata, api.description_table, read64(api.description_table + 8), unsafe { &context })
	assert context == source // Swift x20 is callee-saved, including nested calls.
	return result
}
fn protocol_reentry(api ProtocolApi, probe ProtocolProbe, source u64) {
	result := protocol_describe(api, probe, source)
	assert result.first == read64(source) && result.second == read64(source + 8)
	api.release(result.second)
}
fn protocol_target_write(first u64, second u64, metadata u64, table u64, target u64) {
	mut stream := unsafe { &ProtocolStream(target) }
	assert metadata == stream.metadata && table == stream.table
	assert first == read64(stream.source) && second == read64(stream.source + 8)
	if stream.owner != 0 { assert protocol_refs(stream.api, stream.owner, stream.native_heap) == stream.refs }
	stream.calls++
	stream.observed = SwiftStringWords{ first: first, second: second }
	if stream.reenter {
		// Calling another worker while the stream callback is active catches a
		// registry lock held over user code, and exercises nested Swift contexts.
		worker := spawn protocol_reentry(stream.api, stream.probe, stream.source)
		worker.wait()
	}
}
fn protocol_emit_probe(base u64) ProtocolProbe {
	for i, op in [u32(0xa9be7bfd), 0xa90153f3,
		0xaa0703f3, // mov x19,x7 (context output)
		0xaa0303f4, // mov x20,x3 (String self)
		0xaa0603f0, // mov x16,x6 (witness)
		0xaa0403e3, 0xaa0503e4, // Self metadata/table in x3/x4
		0xd63f0200,
		0xf9000274, // str x20,[x19]
		0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! { write32(base + u64(i*4), op) }
	for i, op in [u32(0xa9be7bfd), 0xa90153f3,
		0xaa0403f3, // mov x19,x4 (context output)
		0xaa0003f4, // mov x20,x0 (String self)
		0xaa0303f0, 0xaa0103e0, 0xaa0203e1,
		0xd63f0200, 0xf9000274, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
		write32(base + 64 + u64(i*4), op)
	}
	write32(base + 128, 0xaa1403e4) // mov x4,x20 (target self -> C argument)
	write32(base + 132, 0x58000070)
	write32(base + 136, 0xd61f0200)
	write32(base + 140, 0xd503201f)
	unsafe { *(&u64(base + 144)) = u64(voidptr(protocol_target_write)) }
	// Installed arm64e Swift authenticates the target write witness using its
	// slot address and discriminator 25323. Sign only the native fixture table;
	// Vinix's ARM64 Swift ABI uses ordinary function pointers. No PAC in runtime.
	write32(base + 160, 0xdac10020) // pacia x0,x1
	write32(base + 164, 0xd65f03c0)
	return ProtocolProbe{ write_entry: base, description_entry: base + 64,
		target_entry: base + 128, sign_entry: base + 160 }
}
fn protocol_relative(field u64) u64 {
	offset := unsafe { *(&i32(field)) }
	return if offset == 0 { u64(0) } else { u64(i64(field) + i64(offset)) }
}
fn protocol_layout(api ProtocolApi) {
	for i, table in [api.text_table, api.description_table]! {
		conformance := read64(table)
		assert read64(table + 8) != 0 && unsafe { *(&u32(conformance + 12)) } == 0
		assert protocol_relative(conformance + 4) == read64(api.metadata + 8)
		assert protocol_relative(conformance + 8) == table
		protocol := protocol_relative(conformance)
		assert unsafe { *(&u32(protocol)) } == 0x30043
		assert protocol_relative(protocol + 4) == protocol_relative(read64(api.metadata + 8) + 4)
		name := unsafe { (&u8(protocol_relative(protocol + 8))).vstring() }
		assert name == if i == 0 { 'TextOutputStreamable' } else { 'CustomStringConvertible' }
		assert unsafe { *(&u32(protocol + 12)) } == 0 && unsafe { *(&u32(protocol + 16)) } == 1
		assert unsafe { *(&u32(protocol + 20)) } == 0 && unsafe { *(&u32(protocol + 28)) } == 0
		assert unsafe { *(&u32(protocol + 24)) } & 0xffff == if i == 0 { u32(0x11) } else { u32(0x13) }
	}
}
fn protocol_value(api ProtocolApi, probe ProtocolProbe, words SwiftStringWords, owner u64, native_heap bool) {
	mut source := words
	sp := u64(unsafe { &source })
	if owner != 0 { assert protocol_refs(api, owner, native_heap) == 1 }
	copy := protocol_describe(api, probe, sp)
	assert copy.first == words.first && copy.second == words.second
	assert source.first == words.first && source.second == words.second
	if owner != 0 { assert protocol_refs(api, owner, native_heap) == 2 }
	api.release(copy.second)
	if owner != 0 { assert protocol_refs(api, owner, native_heap) == 1 }
	// Two independent target values/metadata/table addresses ensure forwarding
	// uses the caller's generic arguments rather than String's metadata/table.
	for variant in 0 .. 2 {
		mut metadata := [u64(0x123456789), u64(variant)]!
		mut table := [u64(0), u64(0), u64(0), probe.target_entry, u64(0)]!
		table_address := u64(unsafe { &table[0] })
		$if macos {
			if api.native {
				sign := unsafe { ProtocolSign(voidptr(probe.sign_entry)) }
				table[3] = sign(probe.target_entry, (table_address + 24) | (u64(25323) << 48))
			}
		}
		mut stream := ProtocolStream{ api: api, probe: probe, metadata: u64(unsafe { &metadata[0] }),
			table: table_address, source: sp, owner: owner, refs: 1, native_heap: native_heap, reenter: variant == 1 }
		call := unsafe { ProtocolWriteCall(voidptr(probe.write_entry)) }
		mut context := u64(0)
		for _ in 0 .. 3 {
			call(u64(unsafe { &stream }), stream.metadata, stream.table, sp, api.metadata,
				api.text_table, read64(api.text_table + 8), unsafe { &context })
			assert context == sp
		}
		assert stream.calls == 3 && stream.observed.first == words.first && stream.observed.second == words.second
		assert source.first == words.first && source.second == words.second
		if owner != 0 { assert protocol_refs(api, owner, native_heap) == 1 }
	}
	api.release(words.second)
}
fn protocol_run(api ProtocolApi, probe ProtocolProbe) {
	protocol_layout(api)
	for text in ['', 'Fortnite', '123456789012345', 'long borrowed String literal for forwarding', 'é 🎮', 'a\x00b']! {
		protocol_value(api, probe, swift_string_literal(text.str, i64(text.len), text.is_ascii()), 0, false)
	}
	// Exercise bridge ownership with an ObjC owner. The callbacks only forward
	// String bits; this does not claim foreign String UTF-8 conversion support.
	mut owner := u64(0)
	$if macos {
		if api.native {
			owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0))
			C.CFStringAppendCString(unsafe { voidptr(owner) }, c'owned protocol String', 0x08000100)
		}
	}
	if !api.native { owner = owned_string('owned protocol String') }
	protocol_value(api, probe, SwiftStringWords{ first: 21, second: owner | u64(0x5000000000000000) }, owner, false)
}
fn test_swift_string_protocol_witnesses() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page) == 0 }
	probe := protocol_emit_probe(u64(code))
	C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 168) })
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		api := ProtocolApi{ native: true, metadata: u64(C.dlsym(lib, c'$sSSN')),
			text_table: u64(C.dlsym(lib, c'$sSSs20TextOutputStreamablesWP')),
			description_table: u64(C.dlsym(lib, c'$sSSs23CustomStringConvertiblesWP')),
			release: unsafe { ProtocolRelease(C.dlsym(lib, c'swift_bridgeObjectRelease')) } }
		protocol_run(api, probe)
		ctor := unsafe { ProtocolCString(C.dlsym(lib, c'$sSS7cStringSSSPys4Int8VG_tcfC')) }
		words := ctor(c'a real native owned Swift String for protocol callbacks')
		protocol_value(api, probe, words, words.second, true)
		println('IOS-SWIFT-PROTOCOL-NATIVE: installed descriptors, generic stream forwarding, Swift contexts, borrowed input and owned description, native/ObjC owners and reentrant callbacks')
	}
	for _ in 0 .. 2 {
		objc_start()
		library := '/usr/lib/swift/libswiftCore.dylib'
		api := ProtocolApi{ metadata: runtime_symbol(library, '_$sSSN') or { panic(err) },
			text_table: runtime_symbol(library, '_$sSSs20TextOutputStreamablesWP') or { panic(err) },
			description_table: runtime_symbol(library, '_$sSSs23CustomStringConvertiblesWP') or { panic(err) },
			release: unsafe { ProtocolRelease(voidptr(runtime_symbol(library, '_swift_bridgeObjectRelease') or { panic(err) })) } }
		for i, symbols in [['_$sSSs20TextOutputStreamablesMc', '_$ss20TextOutputStreamableMp'],
			['_$sSSs23CustomStringConvertiblesMc', '_$ss23CustomStringConvertibleMp']] {
			table := if i == 0 { api.text_table } else { api.description_table }
			assert runtime_symbol(library, symbols[0]) or { panic(err) } == read64(table)
			assert runtime_symbol(library, symbols[1]) or { panic(err) } == protocol_relative(read64(table))
		}
		protocol_run(api, probe)
		if _ := runtime_symbol(library, '_swift_conformsToProtocol') { assert false }
		assert ios_runtime.objects.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		objc_stop()
		assert ios_runtime.swift_metadata_arena == 0 && ios_runtime.swift_arc_code == 0
	}
	println('IOS-SWIFT-PROTOCOL: immutable String protocol/conformance descriptors and witnesses, generic stream callback dispatch with borrowed input, owned description, preserved Swift contexts, reentrant workers and two empty teardowns')
}
