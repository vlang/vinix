// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type InterpolationCtor = fn (i64, i64) SwiftStringWords
type InterpolationRelease = fn (u64)
type InterpolationRetain = fn (u64) u64
type InterpolationCall = fn (u64, u64, u64, u64, u64, u64, &u64)
type InterpolationSign = fn (u64, u64) u64
type InterpolationCString = fn (&u8) SwiftStringWords

struct InterpolationApi {
	native   bool
	metadata u64
	table    u64
	literal  u64
	generic  u64
	ctor     InterpolationCtor @[required]
	release  InterpolationRelease @[required]
	retain   InterpolationRetain @[required]
}

struct InterpolationSource {
	api      InterpolationApi
	probe    u64
	metadata u64
	table    u64
	words    SwiftStringWords
	reenter  bool
mut:
	calls u64
}

struct InterpolationTarget {
	api      InterpolationApi
	metadata u64
	table    u64
mut:
	observed SwiftStringWords
	calls    u64
}

fn interpolation_target_write(first u64, second u64, metadata u64, table u64, self u64) {
	mut target := unsafe { &InterpolationTarget(self) }
	assert metadata == target.metadata && table == target.table
	target.api.retain(second)
	target.observed = SwiftStringWords{ first: first, second: second }
	target.calls++
}

fn interpolation_invoke(probe u64, entry u64, first u64, second u64, third u64, fourth u64, destination u64) {
	call := unsafe { InterpolationCall(voidptr(probe)) }
	mut observed := u64(0)
	call(first, second, third, fourth, destination, entry, unsafe { &observed })
	assert observed == destination
}

fn interpolation_source_write(target u64, target_metadata u64, target_table u64, source_metadata u64, source_table u64, self u64) {
	mut source := unsafe { &InterpolationSource(self) }
	assert target_metadata == source.api.metadata && target_table == source.api.table
	assert source_metadata == source.metadata && source_table == source.table
	source.calls++
	if source.reenter {
		worker := spawn interpolation_other_worker(source.api, source.probe)
		worker.wait() // The generic dispatch must not hold the registry lock.
	}
	interpolation_invoke(source.probe, read64(target_table + 24), source.words.first,
		source.words.second, target_metadata, target_table, target)
}

fn interpolation_other_worker(api InterpolationApi, probe u64) {
	mut value := api.ctor(0, 1)
	input := swift_string_literal(c'nested', 6, true)
	interpolation_invoke(probe, api.literal, input.first, input.second, 0, 0, u64(unsafe { &value }))
	interpolation_expect(value, 'nested')
	api.release(value.second)
}

fn interpolation_probe(base u64) {
	for i, op in [u32(0xa9be7bfd), 0xa90153f3, 0xaa0403f4, 0xaa0503f0, 0xaa0603f3, 0xd63f0200,
		0xf9000274, 0xa94153f3, 0xa8c27bfd, 0xd65f03c0]! {
		write32(base + u64(i * 4), op)
	}
	// The generic source write witness's borrowed self arrives in x20.
	write32(base + 64, 0xaa1403e5)
	write32(base + 68, 0x58000070)
	write32(base + 72, 0xd61f0200)
	unsafe { *(&u64(base + 80)) = u64(voidptr(interpolation_source_write)) }
	// Native arm64e's source table slot uses discriminator 64871. Only the
	// installed-library fixture is signed; runtime witnesses use plain BLR.
	write32(base + 96, 0xdac143e0)
	write32(base + 100, 0xdac10020)
	write32(base + 104, 0xd65f03c0)
	write32(base + 128, 0xaa1403e4)
	write32(base + 132, 0x58000070)
	write32(base + 136, 0xd61f0200)
	unsafe { *(&u64(base + 144)) = u64(voidptr(interpolation_target_write)) }
}

fn interpolation_expect(words SwiftStringWords, expected string) {
	mut scratch := [u64(0), u64(0)]!
	bytes := swift_string_bytes(words, u64(unsafe { &scratch[0] })) or { panic(err) }
	assert bytes.count == u64(expected.len)
	for i in 0 .. expected.len {
		assert unsafe { *(&u8(bytes.address + u64(i))) } == expected[i]
	}
	if words.second >> 63 == 0 {
		assert unsafe { *(&u8(bytes.address + bytes.count)) } == 0
	}
	if expected.is_ascii() {
		assert if words.second & (u64(1) << 61) != 0 {
			words.second & (u64(1) << 62) != 0
		} else {
			words.first & (u64(1) << 63) != 0
		}
	}
}

fn interpolation_relative(field u64) u64 {
	offset := unsafe { *(&i32(field)) }
	return if offset == 0 { u64(0) } else { u64(i64(field) + i64(offset)) }
}

fn interpolation_layout(api InterpolationApi) {
	assert read64(api.metadata) == 0x200 && read64(api.metadata + 16) == 0
	vwt := read64(api.metadata - 8)
	assert read64(vwt + 64) == 16 && read64(vwt + 72) == 16 && read64(vwt + 80) == 0x7fffffff02010007
	desc := read64(api.metadata + 8)
	assert unsafe { (&u8(interpolation_relative(desc + 8))).vstring() } == 'DefaultStringInterpolation'
	assert unsafe { *(&u32(desc + 20)) } == 1 && unsafe { *(&u32(desc + 24)) } == 2
	conf := read64(api.table)
	assert interpolation_relative(conf + 4) == desc && interpolation_relative(conf + 8) == api.table
	proto := interpolation_relative(conf)
	assert unsafe { *(&u32(proto)) } == 0x30043 && unsafe { *(&u32(proto + 16)) } == 4
	assert unsafe { (&u8(interpolation_relative(proto + 8))).vstring() } == 'TextOutputStream'
	for i in 0 .. 4 {
		assert unsafe { *(&u32(proto + 24 + u64(i * 8))) } & 0xffff == 0x11
	}
	assert interpolation_relative(proto + 28) != 0 && interpolation_relative(proto + 36) != 0
	assert interpolation_relative(proto + 44) == 0 && interpolation_relative(proto + 52) != 0
}

fn interpolation_run(api InterpolationApi, probe u64) {
	interpolation_layout(api)
	for hint in [-16, 0, 15, 16, 64]! {
		mut value := api.ctor(hint, 0)
		interpolation_expect(value, '')
		if hint <= 15 {
			assert value.second == 0xe000000000000000
		} else {
			assert value.second >> 63 == 0
		}
		mut expected := ''
		for text in ['a', '12345678901234', 'é 🎮', '\x00b', ' long borrowed literal string']! {
			words := swift_string_literal(text.str, i64(text.len), text.is_ascii())
			interpolation_invoke(probe, api.literal, words.first, words.second, 0, 0, u64(unsafe { &value }))
			expected += text
			interpolation_expect(value, expected)
		}
		// A retained alias must survive mutation; self-append must finish reading
		// the old bytes before retiring its owner. Both small and large paths run.
		previous := value
		api.retain(previous.second)
		interpolation_invoke(probe, api.literal, value.first, value.second, 0, 0, u64(unsafe { &value }))
		interpolation_expect(value, expected + expected)
		interpolation_expect(previous, expected)
		assert previous.second != value.second
		api.release(previous.second)
		// A unique owner with reserve room grows in place, including overlap.
		before := value.second
		text := 'z'
		input := swift_string_literal(text.str, 1, true)
		interpolation_invoke(probe, read64(api.table + 24), input.first, input.second,
			api.metadata, api.table, u64(unsafe { &value }))
		interpolation_expect(value, expected + expected + 'z')
		if !api.native && ios_runtime.swift_strings[before] >= u64((expected + expected + 'z').len) {
			assert value.second == before
		}
		api.release(value.second)
	}
	// All four requirements, including the generic protocol ASCII default.
	mut value := api.ctor(128, 2)
	for slot in [1, 2]! {
		interpolation_invoke(probe, read64(api.table + u64(slot * 8)), api.metadata, api.table, 0, 0, u64(unsafe { &value }))
	}
	ascii := 'ASCII\x00tail'
	interpolation_invoke(probe, read64(api.table + 32), u64(ascii.str), u64(ascii.len), api.metadata, api.table, u64(unsafe { &value }))
	interpolation_expect(value, ascii)
	proto := interpolation_relative(read64(api.table))
	interpolation_invoke(probe, interpolation_relative(proto + 52), u64(ascii.str), u64(ascii.len), api.metadata, api.table, u64(unsafe { &value }))
	interpolation_expect(value, ascii + ascii)
	api.release(value.second)
	// A generic stream can retain the default's String beyond the buffer call.
	// Supply an independent target type/table, then overwrite the source bytes.
	mut target_metadata := [u64(0xabc123), u64(0)]!
	mut target_table := [u64(0), u64(0), u64(0), probe + 128, u64(0)]!
	target_table_address := u64(unsafe { &target_table[0] })
	$if macos {
		if api.native {
			sign := unsafe { InterpolationSign(voidptr(probe + 96)) }
			target_table[3] = sign(probe + 128, (target_table_address + 24) | (u64(25323) << 48))
		}
	}
	mut target := InterpolationTarget{ api: api, metadata: u64(unsafe { &target_metadata[0] }), table: target_table_address }
	retained_text := 'long ASCII buffer copied into an independently retained String'
	mut buffer := retained_text.bytes()
	interpolation_invoke(probe, interpolation_relative(proto + 52), u64(buffer.data), u64(buffer.len),
		target.metadata, target.table, u64(unsafe { &target }))
	assert target.calls == 1
	for i in 0 .. buffer.len { buffer[i] = `X` }
	interpolation_expect(target.observed, retained_text)
	assert (read64(target.observed.second + 8) >> 33) + 1 == 1
	api.release(target.observed.second)
	unsafe { buffer.free() }
	// Arbitrary source values and independently supplied metadata/tables prove
	// generic append calls the source witness with its actual Swift context.
	for variant in 0 .. 2 {
		mut meta := [u64(0x123456789), u64(variant)]!
		mut table := [u64(0), probe + 64]!
		table_address := u64(unsafe { &table[0] })
		$if macos {
			if api.native {
				sign := unsafe { InterpolationSign(voidptr(probe + 96)) }
				table[1] = sign(probe + 64, (table_address + 8) | (u64(64871) << 48))
			}
		}
		text := if variant == 0 { 'source one' } else { 'second arbitrary source 🎮' }
		mut source := InterpolationSource{
			api:      api
			probe:    probe
			metadata: u64(unsafe { &meta[0] })
			table:    table_address
			words:    swift_string_literal(text.str, i64(text.len), text.is_ascii())
			reenter:  variant == 1
		}
		mut output := api.ctor(64, 1)
		for _ in 0 .. 3 {
			interpolation_invoke(probe, api.generic, u64(unsafe { &source }), source.metadata,
				0x987654321, source.table, u64(unsafe { &output }))
		}
		assert source.calls == 3
		interpolation_expect(output, text + text + text)
		api.release(output.second)
	}
	// Use the actual String TextOutputStreamable witness as the generic source.
	// The input remains owned by its caller and can be mutated independently.
	mut string_metadata := u64(0)
	mut string_witness := u64(0)
	$if macos {
		if api.native {
			lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			string_metadata = u64(C.dlsym(lib, c'$sSSN'))
			string_witness = read64(u64(C.dlsym(lib, c'$sSSs20TextOutputStreamablesWP')) + 8)
		}
	}
	if !api.native {
		string_metadata = swift_string_metadata()
		string_witness = read64((swift_string_protocol_symbol('_$sSSs20TextOutputStreamablesWP') or { panic('missing String stream table') }) + 8)
	}
	mut string_table := [u64(0), string_witness]!
	string_table_address := u64(unsafe { &string_table[0] })
	$if macos {
		if api.native {
			sign := unsafe { InterpolationSign(voidptr(probe + 96)) }
			string_table[1] = sign(string_witness, (string_table_address + 8) | (u64(64871) << 48))
		}
	}
	mut input := api.ctor(64, 0)
	owned_text := 'heap String borrowed by generic interpolation'
	words := swift_string_literal(owned_text.str, i64(owned_text.len), true)
	interpolation_invoke(probe, api.literal, words.first, words.second, 0, 0, u64(unsafe { &input }))
	mut output := api.ctor(128, 1)
	interpolation_invoke(probe, api.generic, u64(unsafe { &input }), string_metadata, 0x987654321,
		string_table_address, u64(unsafe { &output }))
	assert (read64(input.second + 8) >> 33) + 1 == 1
	interpolation_expect(input, owned_text)
	interpolation_expect(output, owned_text)
	// Unique self-append reuses its reserve and safely handles overlapping bytes.
	old_owner := output.second
	interpolation_invoke(probe, api.literal, output.first, output.second, 0, 0, u64(unsafe { &output }))
	assert output.second == old_owner
	interpolation_expect(output, owned_text + owned_text)
	interpolation_expect(input, owned_text)
	api.release(input.second)
	api.release(output.second)
}

fn interpolation_resolve() u64 { return swift_interpolation_metadata() }

fn test_swift_interpolation_storage_and_dispatch() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != unsafe { voidptr(-1) }
	defer { assert C.munmap(code, page) == 0 }
	probe := u64(code)
	interpolation_probe(probe)
	C.__builtin___clear_cache(code, unsafe { voidptr(probe + 152) })
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		api := InterpolationApi{
			native:   true
			metadata: u64(C.dlsym(lib, c'$ss26DefaultStringInterpolationVN'))
			table:    u64(C.dlsym(lib, c'$ss26DefaultStringInterpolationVs16TextOutputStreamsWP'))
			literal:  u64(C.dlsym(lib, c'$ss26DefaultStringInterpolationV13appendLiteralyySSF'))
			generic:  u64(C.dlsym(lib, c'$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzs20TextOutputStreamableRzlF'))
			ctor:     unsafe { InterpolationCtor(C.dlsym(lib, c'$ss26DefaultStringInterpolationV15literalCapacity18interpolationCountABSi_SitcfC')) }
			release:  unsafe { InterpolationRelease(C.dlsym(lib, c'swift_bridgeObjectRelease')) }
			retain:   unsafe { InterpolationRetain(C.dlsym(lib, c'swift_bridgeObjectRetain')) }
		}
		interpolation_run(api, probe)
		println('IOS-SWIFT-INTERPOLATION-NATIVE: installed storage, borrowed literal, retained aliases, self-append, four stream requirements, generic protocol ASCII default and arbitrary source witness dispatch')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn interpolation_resolve() }
		metadata := workers[0].wait()
		for i in 1 .. workers.len {
			assert workers[i].wait() == metadata
		}
		library := '/usr/lib/swift/libswiftCore.dylib'
		api := InterpolationApi{
			metadata: metadata
			table:    runtime_symbol(library, '_$ss26DefaultStringInterpolationVs16TextOutputStreamsWP') or { panic(err) }
			literal:  runtime_symbol(library, '_$ss26DefaultStringInterpolationV13appendLiteralyySSF') or { panic(err) }
			generic:  runtime_symbol(library, '_$ss26DefaultStringInterpolationV06appendC0yyxs06CustomB11ConvertibleRzs20TextOutputStreamableRzlF') or { panic(err) }
			ctor:     swift_interpolation_init
			release:  swift_bridge_release
			retain:   swift_bridge_retain
		}
		interpolation_run(api, probe)
		assert runtime_symbol(library, '_$sSS6appendyySSF') or { panic(err) } == api.literal
		assert runtime_symbol(library, '_$ss26DefaultStringInterpolationVMn') or { panic(err) } == read64(metadata + 8)
		assert runtime_symbol(library, '_$ss16TextOutputStreamMp') or { panic(err) } == interpolation_relative(read64(api.table))
		assert swift_interpolation_capacity(12, 2) or { panic(err) } == 16
		assert swift_interpolation_capacity(0, -1) or { panic(err) } == 0
		for counts in [[i64(0), i64(9223372036854775807)]!, [i64(9223372036854775807), i64(1)]!,
			[i64(-9223372036854775807) - 1, i64(-1)]!]! {
			if _ := swift_interpolation_capacity(counts[0], counts[1]) {
				assert false
			}
		}
		// Copies via the shared non-POD VWT acquire the new String owner.
		mut value := api.ctor(32, 0)
		mut alias := SwiftStringWords{}
		swift_string_copy(u64(unsafe { &alias }), u64(unsafe { &value }), metadata)
		assert swift_buffer_refs(value.second, 0) or { panic(err) } == 2
		input := swift_string_literal(c'copy on write', 13, true)
		interpolation_invoke(probe, api.literal, input.first, input.second, 0, 0, u64(unsafe { &value }))
		interpolation_expect(value, 'copy on write')
		interpolation_expect(alias, '')
		swift_string_destroy(u64(unsafe { &alias }), metadata)
		swift_string_destroy(u64(unsafe { &value }), metadata)
		assert ios_runtime.swift_strings.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.objects.len == 0
		arena := ios_runtime.swift_interpolation_arena
		objc_stop()
		assert ios_runtime.swift_interpolation_arena == 0 && ios_runtime.swift_metadata_arena == 0
		assert C.mprotect(unsafe { voidptr(arena) }, page, C.PROT_READ) == -1
	}
	println('IOS-SWIFT-INTERPOLATION: frozen metadata, checked reserve hints, UTF-8/NUL boundaries, growth and ARC, COW and self-append, real generic witnesses, reentrant contexts, concurrent sealed publication and two empty teardowns')
}
