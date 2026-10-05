// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

#include <sys/mman.h>
#include <unistd.h>

fn C.mmap(voidptr, usize, int, int, int, i64) voidptr
fn C.munmap(voidptr, usize) int
fn C.mprotect(voidptr, usize, int) int
fn C.getpagesize() int
fn C.__builtin___clear_cache(voidptr, voidptr)

type AppMain = fn (int, &&char, &&char, &&char) int

fn execute(image macho.Image, arguments []string) !int {
	$if !arm64 {
		return error('iOS: native execution requires an ARM64 host; --inspect works on any host')
	}
	issues := image.execution_issues()
	if issues.len != 0 { return error('iOS: cannot execute:\n  ' + issues.join('\n  ')) }
	page := u64(C.getpagesize())
	layout := image.layout(page)!
	flags := C.MAP_PRIVATE | C.MAP_ANONYMOUS
	mapping := C.mmap(unsafe { nil }, usize(layout.size), C.PROT_READ | C.PROT_WRITE, flags, -1, 0)
	if mapping == unsafe { voidptr(-1) } { return error('iOS: cannot allocate image mapping') }
	defer { C.munmap(mapping, usize(layout.size)) }
	base := u64(mapping)
	objc_start()
	defer { objc_stop() }
	fixups := image.plan_fixups(layout, base, runtime_symbol)!
	for segment in image.segments {
		if segment.name == '__PAGEZERO' || segment.filesize == 0 { continue }
		unsafe {
			C.memcpy(voidptr(base + segment.address - layout.base), &image.data[int(segment.fileoff)], usize(segment.filesize))
		}
	}
	for fixup in fixups {
		// PTR_64 chains can have 4-byte alignment; memcpy handles unaligned
		// stores and avoids imposing a host alignment requirement.
		value := fixup.value
		unsafe { C.memcpy(voidptr(base + fixup.offset), &value, 8) }
	}
	objc_register_image(image, layout, base)!
	C.__builtin___clear_cache(mapping, unsafe { voidptr(base + layout.size) })
	if C.mprotect(mapping, usize(layout.size), C.PROT_NONE) != 0 {
		return error('iOS: cannot protect image gaps')
	}
	for segment in image.segments {
		if segment.name == '__PAGEZERO' || segment.size == 0 { continue }
		size := (segment.size + page - 1) & ~(page - 1)
		// SG_READ_ONLY is sealed only after binding (__DATA_CONST).
		prot := if segment.flags & 0x10 != 0 { segment.prot & ~u32(2) } else { segment.prot }
		if C.mprotect(unsafe { voidptr(base + segment.address - layout.base) }, usize(size), int(prot)) != 0 {
			return error('iOS: cannot apply segment protections to ${segment.name}')
		}
	}
	mut argv := []&char{cap: arguments.len + 1}
	for argument in arguments { argv << unsafe { &char(argument.str) } }
	argv << unsafe { &char(nil) }
	// A private null-terminated environment/Apple vector. No Darwin loader
	// globals are advertised until they have a compatible implementation.
	mut empty := [unsafe { &char(nil) }]!
	entry := unsafe { AppMain(voidptr(base + layout.entry)) }
	return unsafe { entry(arguments.len, &&char(argv.data), &empty[0], &empty[0]) }
}
