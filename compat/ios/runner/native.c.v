// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

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
	$if ios_text ? { text_start()! }
	$if ios_gles ? { gles_start()! }
	if ios_runtime.trace { eprintln('iOS Mach-O mapping: 0x${base.hex()}') }
	image_runtime_start(image, layout, base)
	path := os.real_path(arguments[0])
	defer { unsafe { path.free() } }
	modules_start(image, layout, base, path, false)
	defer {
		dispatch_stop()
		if image_runtime.started { image_cxa_finalize(0) }
		objc_stop()
		$if ios_gles ? { gles_stop() }
		image_runtime_stop()
		if lazy_runtime != unsafe { nil } { lazy_stop() }
		modules_stop()
		system_data_stop()
	}
	system_data_start()!
	image_atfork_start()!
	ios_runtime.bundle = os.dir(path)
	image_runtime.path = path.clone()
	module_dependencies(0, 0)!
	lazy_start()!
	module_bind_all()!
	mut argv := []&char{cap: arguments.len + 1}
	for argument in arguments { argv << unsafe { &char(argument.str) } }
	argv << unsafe { &char(nil) }
	// A private null-terminated environment/Apple vector. No Darwin loader
	// globals are advertised until they have a compatible implementation.
	mut empty := [unsafe { &char(nil) }]!
	image_runtime.started = true
	objc_load_image()
	for index in module_runtime.order {
		for address in module_runtime.modules[index].initializers {
			initializer := unsafe { ImageInitializer(voidptr(address)) }
			unsafe { initializer(arguments.len, &&char(argv.data), &empty[0], &empty[0]) }
		}
	}
	entry := unsafe { AppMain(voidptr(base + layout.entry)) }
	return unsafe { entry(arguments.len, &&char(argv.data), &empty[0], &empty[0]) }
}
