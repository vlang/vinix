// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

const ii_vm = u64(0x100000000)
const ii_bytes = u64(2 * 1024 * 1024)

fn ii_module(base u64, page u64, sections []macho.Section, routines []u64) LoadedModule {
	return LoadedModule{
		base: base
		layout: macho.Layout{base: ii_vm, size: page + ii_bytes + page}
		image: macho.Image{
			routines: routines
			segments: [
				macho.Segment{name: '__TEXT', address: ii_vm, size: page, filesize: 32, prot: 5},
				macho.Segment{name: '__DATA', address: ii_vm + page, size: ii_bytes + page,
					fileoff: page, filesize: ii_bytes, prot: 3, sections: sections},
			]
		}
	}
}

fn ii_reject(loaded &LoadedModule, message string) {
	functions := image_initializers(loaded) or {
		assert err.msg() == message
		return
	}
	unsafe { functions.free() }
	assert false, 'malformed initializer table accepted'
}

fn ii_offset_reject(header u64, offset u32, message string) {
	_ := image_initializer_offset_address(header, offset) or {
		assert err.msg() == message
		return
	}
	assert false, 'invalid initializer offset address accepted'
}

fn test_image_initializer_tables() {
	page := u64(C.getpagesize())
	span := ii_bytes + page * 4
	mapping := u64(C.mmap(unsafe { nil }, usize(span), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert mapping != ~u64(0)
	defer { assert C.munmap(voidptr(mapping), usize(span)) == 0 }
	base := mapping + page
	table := base + page
	assert C.mprotect(voidptr(base), usize(page + ii_bytes), C.PROT_READ | C.PROT_WRITE) == 0
	image_runtime = &ImageRuntime{}
	defer {
		unsafe { image_runtime.destructors.free(); free(image_runtime) }
		image_runtime = unsafe { nil }
	}
	for i in 0 .. 262144 { write32(table + u64(i) * 4, u32(i % 4) * 4) }
	assert C.mprotect(voidptr(table), usize(ii_bytes), C.PROT_READ) == 0
	// Include the old boundary, Fortnite's exact count and the new boundary.
	for count in [0, 65536, 65537, 176816, 262144] {
		loaded := ii_module(base, page, [macho.Section{address: ii_vm + page,
			size: u64(count) * 4, flags: 0x80000016}], []u64{})
		functions := image_initializers(&loaded) or { panic(err) }
		assert functions.len == count
		for i, address in functions { assert address == base + u64(i % 4) * 4 }
		unsafe { functions.free() }
	}
	assert C.mprotect(voidptr(table), usize(ii_bytes), C.PROT_READ | C.PROT_WRITE) == 0
	for i in 0 .. 262144 { unsafe { *(&u64(table + u64(i) * 8)) = base + u64(i % 4) * 4 } }
	assert C.mprotect(voidptr(table), usize(ii_bytes), C.PROT_READ) == 0
	loaded_pointers := ii_module(base, page, [macho.Section{address: ii_vm + page,
		size: ii_bytes, flags: 9}], []u64{})
	pointers := image_initializers(&loaded_pointers) or { panic(err) }
	assert pointers.len == 262144
	for i, address in pointers { assert address == base + u64(i % 4) * 4 }
	unsafe { pointers.free() }

	invalid_section := 'iOS: invalid initializer section'
	for section in [
		macho.Section{address: ii_vm + page, size: 262145 * 4, flags: 0x16},
		macho.Section{address: ii_vm + page, size: 262145 * 8, flags: 9},
		macho.Section{address: ii_vm + page, size: 3, flags: 0x16},
		macho.Section{address: ii_vm + page, size: 7, flags: 10},
		macho.Section{address: ii_vm + page + 1, size: 4, flags: 0x16},
		macho.Section{address: ii_vm + page - 4, size: 4, flags: 0x16},
		macho.Section{address: ii_vm + page + ii_bytes, size: 4, flags: 0x16},
		macho.Section{address: ii_vm + page + ii_bytes - 4, size: 8, flags: 9},
		macho.Section{address: ii_vm + page + ii_bytes + 4, flags: 0x16},
	] {
		loaded := ii_module(base, page, [section], []u64{})
		ii_reject(&loaded, invalid_section)
	}
	// Aggregate bounds include separate sections, terminators and LC_ROUTINES_64.
	for extra in [u32(9), 10, 0x16] {
		loaded := ii_module(base, page, [
			macho.Section{address: ii_vm + page, size: 262144 * 4, flags: 0x16},
			macho.Section{address: ii_vm + page, size: if extra == 0x16 { u64(4) } else { u64(8) }, flags: extra},
		], []u64{})
		ii_reject(&loaded, invalid_section)
	}
	loaded_routine_limit := ii_module(base, page, [macho.Section{address: ii_vm + page,
		size: 262144 * 4, flags: 0x16}], [ii_vm])
	ii_reject(&loaded_routine_limit, invalid_section)
	too_many_routines := []u64{len: 262145, init: ii_vm}
	loaded_routines := ii_module(base, page, []macho.Section{}, too_many_routines)
	ii_reject(&loaded_routines, invalid_section)
	unsafe { too_many_routines.free() }

	assert C.mprotect(voidptr(table), usize(ii_bytes), C.PROT_READ | C.PROT_WRITE) == 0
	for kind in [u32(9), 10, 0x16] {
		for offset in [u64(1), 32, page, page + ii_bytes, ~u64(0) - base] {
			if kind == 0x16 { write32(table, u32(offset)) }
			else { unsafe { *(&u64(table)) = base + offset } }
			loaded := ii_module(base, page, [macho.Section{address: ii_vm + page,
				size: if kind == 0x16 { u64(4) } else { u64(8) }, flags: kind}], []u64{})
			ii_reject(&loaded, 'iOS: initializer/terminator is not executable')
		}
	}
	for offset in [u64(1), 32, page, page + ii_bytes] {
		loaded := ii_module(base, page, []macho.Section{}, [ii_vm + offset])
		ii_reject(&loaded, 'iOS: initializer is not executable')
	}
	// A zero offset is valid only when there is a mapped header. Do not
	// substitute the reservation base for an absent or unreadable header.
	write32(table, 4)
	for text in [
		macho.Segment{name: '__TEXT', address: ii_vm, size: page, fileoff: page * 3, filesize: 32, prot: 5},
		macho.Segment{name: '__TEXT', address: ii_vm, size: page, filesize: 31, prot: 5},
		macho.Segment{name: '__TEXT', address: ii_vm, size: page, filesize: 32, prot: 4},
	] {
		loaded := LoadedModule{
			base: base
			layout: macho.Layout{base: ii_vm, size: page + ii_bytes + page}
			image: macho.Image{segments: [text,
				macho.Segment{name: '__DATA', address: ii_vm + page, size: ii_bytes + page,
					fileoff: page, filesize: ii_bytes, prot: 3,
					sections: [macho.Section{address: ii_vm + page, size: 4, flags: 0x16}]},
			]}
		}
		ii_reject(&loaded, 'iOS: initializer offsets require a mapped Mach-O header')
	}
	assert image_initializer_offset_address(base, 0) or { panic(err) } == base
	assert image_initializer_offset_address(ii_vm, ~u32(0)) or { panic(err) } == ii_vm + u64(~u32(0))
	assert image_initializer_offset_address(~u64(0) - 255, 255) or { panic(err) } == ~u64(0)
	ii_offset_reject(0, 0, 'iOS: initializer offsets require a mapped Mach-O header')
	for offset in [u32(256), ~u32(0)] {
		ii_offset_reject(~u64(0) - 255, offset, 'iOS: initializer offset address overflows')
	}
	assert image_runtime.destructors.len == 0
	write32(table, 4); write32(table + 4, 8)
	unsafe {
		*(&u64(table + 8)) = base + 12
		*(&u64(table + 16)) = base + 4
		*(&u64(table + 24)) = base
	}
	ordered := ii_module(base, page, [
		macho.Section{address: ii_vm + page, size: 8, flags: 0x16},
		macho.Section{address: ii_vm + page + 16, size: 16, flags: 10},
		macho.Section{address: ii_vm + page + 8, size: 8, flags: 9},
		macho.Section{address: ii_vm + page + ii_bytes, size: ~u64(0), flags: 0x17},
	], [ii_vm])
	functions := image_initializers(&ordered) or { panic(err) }
	assert functions == [base, base + 4, base + 8, base + 12]
	unsafe { functions.free() }
	assert image_runtime.destructors.len == 2
	assert u64(voidptr(image_runtime.destructors[0].exit_function)) == base + 4
	assert u64(voidptr(image_runtime.destructors[1].exit_function)) == base
	println('IOS-IMAGE-INITIALIZERS: 176816 Fortnite offsets, old/new count boundaries, readonly offset/pointer tables, aggregate routines/initializer/terminator limit, malformed/file-backed/executable/alignment/header/overflow rejection and ordered collection: PASS')
}

fn ii_put32(mut bytes []u8, at int, value u32) {
	for i in 0 .. 4 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn ii_put64(mut bytes []u8, at int, value u64) {
	for i in 0 .. 8 { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn ii_text(mut bytes []u8, at int, value string) {
	for i, byte in value { bytes[at + i] = byte }
}

fn ii_segment(mut bytes []u8, at int, name string, address u64, size u64,
	fileoff u64, filesize u64, prot u32, sections u32) int {
	ii_put32(mut bytes, at, 0x19)
	ii_put32(mut bytes, at + 4, 72 + sections * 80)
	ii_text(mut bytes, at + 8, name)
	ii_put64(mut bytes, at + 24, address)
	ii_put64(mut bytes, at + 32, size)
	ii_put64(mut bytes, at + 40, fileoff)
	ii_put64(mut bytes, at + 48, filesize)
	ii_put32(mut bytes, at + 56, prot)
	ii_put32(mut bytes, at + 60, prot)
	ii_put32(mut bytes, at + 64, sections)
	return at + 72
}

fn ii_adr(reg u32, from u64, to u64) u32 {
	distance := i64(to) - i64(from)
	assert distance >= -1048576 && distance < 1048576 && reg < 31
	immediate := u32(distance) & 0x1fffff
	return 0x10000000 | ((immediate & 3) << 29) | ((immediate >> 2) << 5) | reg
}

// Apple dyld Loader::findAndRunAllInitializers adds each initializer offset
// to its Mach-O header (ma), not the lowest mapped segment. This synthetic
// image supports a slide and an optional lower segment to distinguish those
// addresses. No Apple SDK, host callbacks or imported symbols are used.
fn ii_entry_image(lower_prot u32) macho.Image {
	page := u64(C.getpagesize())
	lower := lower_prot != 0
	header := ii_vm + if lower { page * 2 } else { u64(0) }
	data := header + page * 2
	entry := u64(0x400)
	constructor := u64(0x500)
	table := u64(0x600)
	mut bytes := []u8{len: int(page * 3)}
	defer { unsafe { bytes.free() } }
	ii_put32(mut bytes, 0, 0xfeedfacf)
	ii_put32(mut bytes, 4, 0x100000c)
	ii_put32(mut bytes, 12, 2)
	ii_put32(mut bytes, 16, u32(5 + int(lower)))
	ii_put32(mut bytes, 24, 0x200085)
	mut at := ii_segment(mut bytes, 32, '__PAGEZERO', 0, ii_vm, 0, 0, 0, 0)
	if lower { at = ii_segment(mut bytes, at, '__LOW', ii_vm, page, page, page, lower_prot, 0) }
	at = ii_segment(mut bytes, at, '__TEXT', header, page, 0, page, 5, 1)
	ii_text(mut bytes, at, '__init_offsets')
	ii_text(mut bytes, at + 16, '__TEXT')
	ii_put64(mut bytes, at + 32, header + table)
	ii_put64(mut bytes, at + 40, 4)
	ii_put32(mut bytes, at + 48, u32(table))
	ii_put32(mut bytes, at + 52, 2)
	ii_put32(mut bytes, at + 64, 0x16)
	at += 80
	at = ii_segment(mut bytes, at, '__DATA', data, page, page * 2, page, 3, 0)
	ii_put32(mut bytes, at, 0x80000028)
	ii_put32(mut bytes, at + 4, 24)
	ii_put64(mut bytes, at + 8, entry)
	at += 24
	ii_put32(mut bytes, at, 0x32)
	ii_put32(mut bytes, at + 4, 24)
	ii_put32(mut bytes, at + 8, 2)
	ii_put32(mut bytes, at + 12, 0xf0000)
	ii_put32(mut bytes, at + 16, 0xf0000)
	at += 24
	ii_put32(mut bytes, 20, u32(at - 32))
	assert u64(at) < entry

	// The constructor increments initially zeroed data exactly once. Entry
	// returns 37 only after that write; a missing/repeated/wrong ctor returns 99.
	for i, instruction in [
		ii_adr(9, header + constructor, data),
		u32(0xb940012a), // ldr w10, [x9]
		0x1100054a, // add w10, w10, #1
		0xb900012a, // str w10, [x9]
		0xd65f03c0, // ret
	]! { ii_put32(mut bytes, int(constructor) + i * 4, instruction) }
	for i, instruction in [
		ii_adr(9, header + entry, data),
		u32(0xb940012a), // ldr w10, [x9]
		0x7100055f, // cmp w10, #1
		0x54000061, // b.ne failure (+12)
		0x528004a0, // mov w0, #37
		0xd65f03c0, // ret
		0x52800c60, // failure: mov w0, #99
		0xd65f03c0, // ret
	]! { ii_put32(mut bytes, int(entry) + i * 4, instruction) }
	ii_put32(mut bytes, int(table), u32(constructor))
	if lower {
		// An executable lower segment also rejects a false success from the
		// old arithmetic: its decoy constructor deliberately writes 99.
		for i, instruction in [
			ii_adr(9, ii_vm + constructor, data),
			u32(0x52800c6a), // mov w10, #99
			0xb900012a, // str w10, [x9]
			0xd65f03c0, // ret
		]! { ii_put32(mut bytes, int(page + constructor) + i * 4, instruction) }
	}
	return macho.parse(bytes) or { panic(err) }
}

fn test_image_initializer_header_relative_entry() {
	// The string array owns the executable path; its typed free releases it.
	arguments := [os.executable()]
	defer { unsafe { arguments.free() } }
	for lower_prot in [u32(0), 1, 5] {
		image := ii_entry_image(lower_prot)
		for _ in 0 .. 2 {
			result := execute(image, arguments) or { panic(err) }
			assert result == 37, 'initializer did not run once before LC_MAIN (lower protection ${lower_prot}, exit ${result})'
			assert image_runtime == unsafe { nil } && module_runtime == unsafe { nil } && ios_runtime.live == 0
		}
		module_image_free(image)
	}
	println('IOS-IMAGE-INITIALIZER-ENTRY: six V-generated ARM64 Mach-O executions, header-relative constructor with normal/lower-readonly/lower-executable mappings, once-before-entry sentinel, executable decoy and teardown/reinitialization: PASS')
}
