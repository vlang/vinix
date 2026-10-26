// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

type InlineSelfCapture = fn (&u64, &u64)

fn self_test_state(mut code []u32, save bool) {
	for r := u32(0); r < 30; r += 2 { code << inline_self_pair(if save { u32(0xa9000000) } else { u32(0xa9400000) }, r, r * 8, false) }
	code << inline_self_slot(if save { u32(0xf9000000) } else { u32(0xf9400000) }, 30, 240)
	for r := u32(0); r < 32; r += 2 { code << inline_self_pair(if save { u32(0xad000000) } else { u32(0xad400000) }, r, 256 + r * 16, true) }
	for index, mrs in [u32(0xd53b4200), 0xd53b4400, 0xd53b4420]! {
		if save {
			code << mrs
			code << inline_self_slot(0xf9000000, 0, 768 + u32(index) * 8)
		} else {
			// Restore FP state before x0, restored again below.
			code << inline_self_slot(0xf9400000, 0, 768 + u32(index) * 8)
			code << mrs & ~u32(0x200000)
		}
	}
	if !save { code << inline_self_slot(0xf9400000, 0, 0) }
}

fn self_test_emit(address u64, rt u32, compare bool) (u64, u64) {
	mut code := []u32{cap: 512}
	defer { unsafe { code.free() } }
	code << u32(0xd11003ff)
	self_test_state(mut code, true) // Native caller state in the upper frame.
	code << u32(0xd11003ff)
	code << inline_self_slot(0xf9000000, 18, 928)
	code << u32(0x910003e0) // mov x0, sp
	code << inline_self_slot(0xf9000000, 0, 936)
	code << u32(0xd280b4a0) // mov x0, #0x5a5
	for offset := u32(0); offset < 128; offset += 8 {
		code << u32(0xf80003e0) | ((offset + 384) & 511) << 12 // stur x0, [sp, #-128+offset]
	}
	for index, msr in [u32(0xd51b4200), 0xd51b4400, 0xd51b4420]! {
		code << u32(0xf9400020) | ((768 + u32(index) * 8) / 8) << 10 // ldr x0, [x1, state]
		code << msr
	}
	for r := u32(0); r < 32; r += 2 { code << (inline_self_pair(0xad400000, r, 256 + r * 16, true) & ~u32(0x3e0)) | 1 << 5 }
	for r := u32(0); r < 31; r++ {
		if r == 1 || r == 18 { continue }
		code << u32(0xf9400020) | r << 10 | r
	}
	code << u32(0xf9400421) // ldr x1, [x1, #8], last input load
	site := address + u64(code.len) * 4
	code << u32(0xd53bd060) | rt
	code << u32(0x927df000) | rt << 5 | rt
	third := code.len
	code << u32(0xf9400000) | rt << 5 | rt
	self_test_state(mut code, true) // Capture before using any scratch register.
	code << u32(0x910003e0)
	code << inline_self_slot(0xf9000000, 0, 792)
	for offset := u32(0); offset < 128; offset += 8 {
		code << u32(0xf84003e0) | ((offset + 384) & 511) << 12
		code << inline_self_slot(0xf9000000, 0, 800 + offset)
	}
	code << inline_self_slot(0xf9400000, 0, 1024) // output pointer in native frame
	code << u32(0x910003e1) // mov x1, sp
	code << u32(0xd2808002) // mov x2, #1024
	memcpy_load := code.len
	code << u32(0)
	code << u32(0xd63f0200)
	code << u32(0x911003ff)
	self_test_state(mut code, false)
	code << u32(0x911003ff)
	code << u32(0xd65f03c0)
	helper := address + u64(code.len) * 4
	code << [u32(0xf9400129), 0xeb09011f, 0xd65f03c0]
	if compare { code[third] = (inline_self_branch(site + 8, helper) or { panic('fixture branch') }) | 0x80000000 }
	if code.len & 1 != 0 { code << u32(0xd503201f) }
	code[memcpy_load] = 0x58000010 | u32(code.len - memcpy_load) << 5
	for index, instruction in code { write32(address + u64(index) * 4, instruction) }
	write64(address + u64(code.len) * 4, u64(voidptr(C.memcpy)))
	return site, helper
}

fn self_test_call(address u64, site u64, rt u32, compare bool, delta i64) {
	mut seed := [128]u64{}
	mut capture := [128]u64{}
	for i in 0 .. 96 { seed[i] = 0x12340000 + u64(i) }
	identity := u64(C.pthread_self())
	seed[8] = u64(i64(identity) + delta)
	seed[96] = 0xa0000000
	seed[97] = 0x400000 // Nondefault FP rounding mode.
	seed[98] = 0x10
	mut key := u64(0)
	assert C.pthread_key_create(unsafe { voidptr(&key) }, unsafe { nil }) == 0
	defer { C.pthread_key_delete(key) }
	assert C.pthread_setspecific(key, unsafe { voidptr(0x12345678) }) == 0
	darwin_set_errno(37)
	unsafe { InlineSelfCapture(voidptr(address))(&capture[0], &seed[0]) }
	assert u64(C.pthread_self()) == identity
	assert C.pthread_getspecific(key) == unsafe { voidptr(0x12345678) }
	assert unsafe { *C.ios_errno_address() } == 37
	for r in 0 .. 31 {
		expected := if u32(r) == rt { identity } else if r == 18 { capture[116] } else if r == 30 && compare { site + 12 } else { seed[r] }
		assert capture[r] == expected, 'register x${r}: ${capture[r].hex()} expected ${expected.hex()}'
	}
	for i in 32 .. 96 { assert capture[i] == seed[i], 'vector word ${i}' }
	expected_flags := if !compare { seed[96] } else if delta == 0 { u64(0x60000000) } else if delta < 0 { u64(0x80000000) } else { u64(0x20000000) }
	assert capture[96] == expected_flags
	assert capture[97] == seed[97] && capture[98] == seed[98]
	assert capture[99] == capture[117]
	for i in 100 .. 116 { assert capture[i] == 0x5a5, 'red zone word ${i}' }
}

fn self_test_worker(address u64, site u64, rt u32, compare bool) {
	for delta in [i64(-1), 0, 1]! { self_test_call(address, site, rt, compare, delta) }
}

fn test_inline_pthread_self_translation() {
	page := usize(C.getpagesize())
	for compare in [false, true]! {
		registers := if compare { [u32(9)] } else { [u32(0), 1, 8, 9, 10, 16, 17, 19, 29, 30] }
		for rt in registers {
			for _ in 0 .. 2 {
				mapping := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
				assert mapping != unsafe { voidptr(-1) }
				address := u64(mapping)
				site, helper := self_test_emit(address, rt, compare)
				data := unsafe { (&u8(mapping)).vbytes(int(page)).clone() }
				mut loaded := LoadedModule{base: address, path: 'inline pthread_self fixture', layout: macho.Layout{base: address, size: u64(page)}, image: macho.Image{data: data, segments: [macho.Segment{name: '__TEXT', address: address, size: u64(page), filesize: u64(page), prot: 5, sections: [macho.Section{address: site, size: 12, flags: 0x80000400}]}]}}
				assert inline_self_pattern(&loaded, site) == if compare { u32(2) } else { u32(1) }
				// Unaligned/truncated/malformed reads never produce a patch.
				assert inline_self_pattern(&loaded, site + 1) == 0
				assert inline_self_pattern(&loaded, address + u64(page) - 8) == 0
				second := int(site - address + 4)
				unsafe { loaded.image.data[second] ^= 1 }
				assert inline_self_pattern(&loaded, site) == 0
				unsafe { loaded.image.data[second] ^= 1 }
				if compare {
					p := int(helper - address + 4)
					unsafe { loaded.image.data[p] ^= 1 }
					assert inline_self_pattern(&loaded, site) == 0
					unsafe { loaded.image.data[p] ^= 1 }
				}
				inline_self_prepare(mut loaded)!
				assert loaded.thread_self_thunks.len == 1
				assert read32(site + 4) == 0x927df000 | rt << 5 | rt
				C.__builtin___clear_cache(mapping, unsafe { voidptr(address + u64(page)) })
				assert C.mprotect(mapping, page, C.PROT_READ | C.PROT_EXEC) == 0
				self_test_worker(address, site, rt, compare)
				mut workers := []thread{}
				for _ in 0 .. 4 { workers << spawn self_test_worker(address, site, rt, compare) }
				workers.wait()
				unsafe { workers.free() }
				inline_self_stop(mut loaded)
				assert C.munmap(mapping, page) == 0
				unsafe { loaded.image.data.free(); loaded.image.segments[0].sections.free(); loaded.image.segments.free() }
			}
		}
		unsafe { registers.free() }
	}
	assert inline_self_branch(0x10000000, 0x08000000)? == 0x16000000
	assert inline_self_branch(0x10000000, 0x17fffffc)? == 0x15ffffff
	for target in [u64(0x07fffffc), 0x18000000, 0x10000001, ~u64(0)]! { if _ := inline_self_branch(0x10000000, target) { assert false } }
	println('IOS-INLINE-PTHREAD-SELF: both idioms, registers, vectors, FP state, flags, SP/LR, red zone, native TLS/errno, workers and unload PASS')
}

fn test_inline_pthread_self_application_inventory() {
	path := os.getenv('VINIX_IOS_INLINE_SELF_IMAGE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	loaded := LoadedModule{image: image}
	mut counts := [3]int{}
	for segment in image.segments {
		if segment.prot & 4 == 0 { continue }
		for section in segment.sections {
			if section.flags & 0x80000400 == 0 { continue }
			for offset := u64(0); offset + 4 <= section.size; offset += 4 {
				pc := section.address + offset
				instruction := inline_self_instruction(&loaded, pc) or { panic('bad instruction range') }
				if instruction & 0xffffffe0 != 0xd53bd060 { continue }
				kind := inline_self_pattern(&loaded, pc)
				counts[kind]++
				println('IOS-INLINE-PTHREAD-SELF-INVENTORY: pc=0x${pc.hex()} register=${instruction & 31} kind=${kind}')
			}
		}
	}
	assert counts == [0, 8, 5]!
	println('IOS-INLINE-PTHREAD-SELF-INVENTORY: all 13 application reads recognized PASS')
}

fn test_inline_pthread_self_large_image_reservation() {
	page := usize(C.getpagesize())
	preferred := u64(0x100000000)
	offset := u64(0x48f0000)
	// Match the real image span and a distant code site without allocating
	// hundreds of MiB of physical memory or depending on mmap hint behavior.
	for compare in [false, true]! {
		source := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		assert source != unsafe { voidptr(-1) }
		site, _ := self_test_emit(u64(source), 9, compare)
		data := unsafe { (&u8(source)).vbytes(int(page)).clone() }
		assert C.munmap(source, page) == 0
		site_offset := site - u64(source)
		layout := macho.Layout{base: preferred, size: 0x15598000}
		image := macho.Image{data: data, segments: [macho.Segment{name: '__TEXT', address: preferred + offset, size: u64(page), filesize: u64(page), prot: 5, sections: [macho.Section{address: preferred + offset + site_offset, size: 12, flags: 0x80000400}]}]}
		mapping := inline_self_map(image, layout)!
		assert mapping.prefix == page
		actual := mapping.base + offset
		actual_site, _ := self_test_emit(actual, 9, compare)
		mut loaded := LoadedModule{base: mapping.base, thread_self_prefix: mapping.prefix, path: 'large inline pthread_self fixture', layout: layout, image: image}
		inline_self_prepare(mut loaded)!
		assert loaded.thread_self_thunks.len == 1
		assert loaded.thread_self_thunks[0].address == mapping.base - u64(page)
		C.__builtin___clear_cache(unsafe { voidptr(actual) }, unsafe { voidptr(actual + u64(page)) })
		assert C.mprotect(unsafe { voidptr(actual) }, page, C.PROT_READ | C.PROT_EXEC) == 0
		self_test_worker(actual, actual_site, 9, compare)
		inline_self_stop(mut loaded)
		assert C.munmap(unsafe { voidptr(mapping.base - u64(page)) }, usize(layout.size) + page) == 0
		unsafe { image.data.free(); image.segments[0].sections.free(); image.segments.free() }
	}
	println('IOS-INLINE-PTHREAD-SELF: large image reserved trampoline placement PASS')
}
