// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

const ii_vm = u64(0x100000000)
const ii_bytes = u64(2 * 1024 * 1024)

fn ii_module(base u64, page u64, sections []macho.Section, routines []u64) LoadedModule {
	return LoadedModule{
		base: base
		layout: macho.Layout{base: ii_vm, size: page + ii_bytes + page}
		image: macho.Image{
			routines: routines
			segments: [
				macho.Segment{name: '__TEXT', address: ii_vm, size: page, filesize: 16, prot: 5},
				macho.Segment{name: '__DATA', address: ii_vm + page, size: ii_bytes + page,
					filesize: ii_bytes, prot: 3, sections: sections},
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
		for offset in [u64(1), 16, page, page + ii_bytes, ~u64(0) - base] {
			if kind == 0x16 { write32(table, u32(offset)) }
			else { unsafe { *(&u64(table)) = base + offset } }
			loaded := ii_module(base, page, [macho.Section{address: ii_vm + page,
				size: if kind == 0x16 { u64(4) } else { u64(8) }, flags: kind}], []u64{})
			ii_reject(&loaded, 'iOS: initializer/terminator is not executable')
		}
	}
	for offset in [u64(1), 16, page, page + ii_bytes] {
		loaded := ii_module(base, page, []macho.Section{}, [ii_vm + offset])
		ii_reject(&loaded, 'iOS: initializer is not executable')
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
	println('IOS-IMAGE-INITIALIZERS: 176816 Fortnite offsets, old/new count boundaries, readonly offset/pointer tables, aggregate routines/initializer/terminator limit, malformed/file-backed/executable/alignment rejection and ordered collection: PASS')
}
