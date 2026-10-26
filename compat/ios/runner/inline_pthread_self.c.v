// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

// Linux does not expose Darwin's pthread TSD through TPIDRRO_EL0. Translate
// only complete, verified pthread_self idioms, never an arbitrary TSD read.
struct InlineThreadSelf {
	address u64
	size usize
}

struct InlineSelfMapping {
	base u64
	prefix usize
}

// Reserve trampoline pages with the image: a large image can fill the entire
// branch window before later mmap hints get a chance to claim nearby space.
fn inline_self_map(image macho.Image, layout macho.Layout) !InlineSelfMapping {
	loaded := LoadedModule{image: image}
	page := u64(C.getpagesize())
	mut prefix := u64(0)
	for segment in image.segments {
		if segment.prot & 4 == 0 || segment.name == '__PAGEZERO' { continue }
		for section in segment.sections {
			if section.flags & 0x80000400 == 0 { continue }
			if section.address & 3 != 0 || section.address < segment.address { return error('iOS: invalid instruction section') }
			delta := section.address - segment.address
			if delta > segment.filesize || section.size > segment.filesize - delta { return error('iOS: instruction section is not file-backed') }
			if section.address > ~u64(0) - section.size { return error('iOS: invalid instruction range') }
			for offset := u64(0); offset + 12 <= section.size; offset += 4 {
				if inline_self_pattern(&loaded, section.address + offset) == 0 { continue }
				prefix += page
				if prefix > 16 * 1024 * 1024 { return error('iOS: inline pthread_self trampoline limit exceeded') }
			}
		}
	}
	if layout.size > ~u64(0) - prefix { return error('iOS: image mapping size overflow') }
	mapping := C.mmap(unsafe { nil }, usize(layout.size + prefix), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if mapping == unsafe { voidptr(-1) } { return error('iOS: cannot allocate image mapping') }
	if prefix > 0 && C.mprotect(mapping, usize(prefix), C.PROT_NONE) != 0 {
		C.munmap(mapping, usize(layout.size + prefix))
		return error('iOS: cannot protect trampoline reservation')
	}
	return InlineSelfMapping{base: u64(mapping) + prefix, prefix: usize(prefix)}
}

fn inline_self_instruction(loaded &LoadedModule, address u64) ?u32 {
	if address & 3 != 0 { return none }
	for segment in loaded.image.segments {
		if segment.prot & 4 == 0 || segment.name == '__PAGEZERO' || address < segment.address { continue }
		delta := address - segment.address
		if delta > segment.filesize || segment.filesize - delta < 4 { continue }
		if segment.fileoff > u64(loaded.image.data.len) || delta > u64(loaded.image.data.len) - segment.fileoff { return none }
		offset := segment.fileoff + delta
		if u64(loaded.image.data.len) - offset < 4 { return none }
		p := int(offset)
		return u32(loaded.image.data[p]) | u32(loaded.image.data[p + 1]) << 8 | u32(loaded.image.data[p + 2]) << 16 | u32(loaded.image.data[p + 3]) << 24
	}
	return none
}

fn inline_self_branch(from u64, to u64) ?u32 {
	if from & 3 != 0 || to & 3 != 0 { return none }
	if to >= from {
		if to - from >= 0x8000000 { return none }
		return u32(0x14000000) | u32((to - from) / 4)
	}
	if from - to > 0x8000000 { return none }
	return u32(0x14000000) | (u32(-i64((from - to) / 4)) & 0x3ffffff)
}

// 1: mrs Rt; and Rt, Rt, ~7; ldr Rt, [Rt].
// 2: mrs x9; and x9, x9, ~7; bl { ldr x9,[x9]; cmp x8,x9; ret }.
fn inline_self_pattern(loaded &LoadedModule, address u64) u32 {
	first := inline_self_instruction(loaded, address) or { return 0 }
	if first & 0xffffffe0 != 0xd53bd060 || first & 31 == 31 || address > ~u64(0) - 12 { return 0 }
	rt := first & 31
	second := inline_self_instruction(loaded, address + 4) or { return 0 }
	third := inline_self_instruction(loaded, address + 8) or { return 0 }
	if second != u32(0x927df000) | rt << 5 | rt { return 0 }
	if third == u32(0xf9400000) | rt << 5 | rt { return 1 }
	if rt != 9 || third & 0xfc000000 != 0x94000000 { return 0 }
	distance := i64(i32(third << 6) >> 6) * 4
	pc := address + 8
	if (distance < 0 && pc < u64(-distance)) || (distance >= 0 && pc > ~u64(0) - u64(distance)) { return 0 }
	target := if distance < 0 { pc - u64(-distance) } else { pc + u64(distance) }
	if target > ~u64(0) - 8 { return 0 }
	if (inline_self_instruction(loaded, target) or { return 0 }) != 0xf9400129 { return 0 }
	if (inline_self_instruction(loaded, target + 4) or { return 0 }) != 0xeb09011f { return 0 }
	if (inline_self_instruction(loaded, target + 8) or { return 0 }) != 0xd65f03c0 { return 0 }
	return 2
}

fn inline_self_pair(base u32, rt u32, offset u32, vector bool) u32 {
	scale := if vector { u32(16) } else { u32(8) }
	return base | (offset / scale) << 15 | (rt + 1) << 10 | 31 << 5 | rt
}

fn inline_self_slot(base u32, rt u32, offset u32) u32 {
	return base | (offset / 8) << 10 | 31 << 5 | rt
}

// Preserve all registers, FP state, flags and the 128-byte Darwin red zone.
// The compare form also reproduces its leaf's flags and BL return address.
fn inline_self_emit(address u64, resume u64, rt u32, compare bool) ! {
	mut code := []u32{cap: 112}
	defer { unsafe { code.free() } }
	code << u32(0xd11003ff) // sub sp, sp, #1024
	for r := u32(0); r < 30; r += 2 { code << inline_self_pair(0xa9000000, r, r * 8, false) }
	code << inline_self_slot(0xf9000000, 30, 240)
	for r := u32(0); r < 32; r += 2 { code << inline_self_pair(0xad000000, r, 256 + r * 16, true) }
	for index, mrs in [u32(0xd53b4200), 0xd53b4400, 0xd53b4420]! {
		code << mrs
		code << inline_self_slot(0xf9000000, 0, 768 + u32(index) * 8)
	}
	load_function := code.len
	code << u32(0) // ldr x16, native pthread_self
	code << u32(0xd63f0200) // blr x16
	code << inline_self_slot(0xf9000000, 0, rt * 8)
	for index, msr in [u32(0xd51b4200), 0xd51b4400, 0xd51b4420]! {
		code << inline_self_slot(0xf9400000, 0, 768 + u32(index) * 8)
		code << msr
	}
	for r := u32(0); r < 32; r += 2 { code << inline_self_pair(0xad400000, r, 256 + r * 16, true) }
	for r := u32(0); r < 30; r += 2 { code << inline_self_pair(0xa9400000, r, r * 8, false) }
	code << inline_self_slot(0xf9400000, 30, 240)
	code << u32(0x911003ff) // add sp, sp, #1024
	if compare {
		code << u32(0xeb09011f) // cmp x8, x9
		code << u32(0x5800009e) // ldr x30, resume literal (16 bytes forward)
	}
	jump := inline_self_branch(address + u64(code.len) * 4, resume) or { return error('iOS: inline pthread_self return is out of range') }
	code << jump
	// Keep the compare form's resume literal exactly 16 bytes after its LDR.
	if compare {
		code << u32(0xd503201f)
		code << u32(0xd503201f)
		code << u32(resume)
		code << u32(resume >> 32)
	}
	if code.len & 1 != 0 { code << u32(0xd503201f) }
	code[load_function] = 0x58000010 | u32(code.len - load_function) << 5
	for index, instruction in code { write32(address + u64(index) * 4, instruction) }
	write64(address + u64(code.len) * 4, u64(voidptr(C.pthread_self)))
}

fn inline_self_allocate(site u64, loaded &LoadedModule) !InlineThreadSelf {
	page := u64(C.getpagesize())
	reserved_offset := u64(loaded.thread_self_thunks.len) * page
	if reserved_offset < u64(loaded.thread_self_prefix) {
		address := loaded.base - u64(loaded.thread_self_prefix) + reserved_offset
		if _ := inline_self_branch(site, address) {
			if _ := inline_self_branch(address + 512, site + 12) {
				if C.mprotect(unsafe { voidptr(address) }, usize(page), C.PROT_READ | C.PROT_WRITE) != 0 { return error('iOS: cannot open trampoline reservation') }
				return InlineThreadSelf{address: address, size: usize(page)}
			}
		}
	}
	for attempt in 0 .. 257 {
		// Hints never replace an existing mapping. Check the actual address
		// because both Linux and Darwin may choose a different free region.
		distance := u64((attempt + 1) / 2) * 0x100000
		hint := if attempt == 0 {
			if loaded.base < page { continue }
			loaded.base - page
		} else if attempt & 1 != 0 {
			if site < distance { continue }
			(site - distance) & ~(page - 1)
		} else {
			if site > ~u64(0) - distance { continue }
			(site + distance) & ~(page - 1)
		}
		mapping := C.mmap(unsafe { voidptr(hint) }, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if mapping == unsafe { voidptr(-1) } { continue }
		address := u64(mapping)
		if _ := inline_self_branch(site, address) {
			if _ := inline_self_branch(address + 512, site + 12) { return InlineThreadSelf{address: address, size: usize(page)} }
		}
		C.munmap(mapping, usize(page))
	}
	return error('iOS: cannot allocate a nearby inline pthread_self thunk')
}

fn inline_self_prepare(mut loaded LoadedModule) ! {
	loaded.thread_self_thunks.flags |= .noslices
	for segment in loaded.image.segments {
		if segment.prot & 4 == 0 || segment.name == '__PAGEZERO' { continue }
		for section in segment.sections {
			if section.flags & 0x80000400 == 0 { continue }
			if section.address & 3 != 0 || section.address < segment.address { return error('iOS: invalid instruction section') }
			if section.address > ~u64(0) - section.size { return error('iOS: invalid instruction range') }
			delta := section.address - segment.address
			if delta > segment.filesize || section.size > segment.filesize - delta { return error('iOS: instruction section is not file-backed') }
			for offset := u64(0); offset + 12 <= section.size; offset += 4 {
				preferred := section.address + offset
				kind := inline_self_pattern(loaded, preferred)
				if kind == 0 { continue }
				site := loaded.base + preferred - loaded.layout.base
				thunk := inline_self_allocate(site, loaded)!
				inline_self_emit(thunk.address, site + 12, (inline_self_instruction(loaded, preferred) or { 0 }) & 31, kind == 2) or {
					inline_self_release(loaded, thunk)
					return err
				}
				C.__builtin___clear_cache(unsafe { voidptr(thunk.address) }, unsafe { voidptr(thunk.address + u64(thunk.size)) })
				if C.mprotect(unsafe { voidptr(thunk.address) }, thunk.size, C.PROT_READ | C.PROT_EXEC) != 0 {
					inline_self_release(loaded, thunk)
					return error('iOS: cannot protect inline pthread_self thunk')
				}
				loaded.thread_self_thunks << thunk
				write32(site, inline_self_branch(site, thunk.address) or { panic('validated inline pthread_self branch') })
			}
		}
	}
	if loaded.thread_self_thunks.len > 0 { eprintln('iOS: translated ${loaded.thread_self_thunks.len} inline pthread_self operations in ${loaded.path}') }
}

fn inline_self_release(loaded &LoadedModule, thunk InlineThreadSelf) {
	if thunk.address < loaded.base && loaded.base - thunk.address <= u64(loaded.thread_self_prefix) {
		C.mprotect(unsafe { voidptr(thunk.address) }, thunk.size, C.PROT_NONE)
	} else {
		C.munmap(unsafe { voidptr(thunk.address) }, thunk.size)
	}
}

fn inline_self_stop(mut loaded LoadedModule) {
	for thunk in loaded.thread_self_thunks { inline_self_release(loaded, thunk) }
	unsafe { loaded.thread_self_thunks.free() }
}
