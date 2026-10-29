// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import faultprobe

#include <sys/mman.h>
#include <unistd.h>

fn C.mmap(voidptr, usize, int, int, int, i64) voidptr
fn C.munmap(voidptr, usize) int
fn C.mprotect(voidptr, usize, int) int
fn C.getpagesize() int
fn C.__builtin___clear_cache(voidptr, voidptr)

type AppMain = fn (int, &&char, &&char, &&char) int

struct ExecutionOptions {
	probe_no_ads bool
}

fn execute(image macho.Image, arguments []string) !int {
	return execute_with_options(image, arguments, ExecutionOptions{})
}

fn execute_with_options(image macho.Image, arguments []string, options ExecutionOptions) !int {
	$if !arm64 {
		return error('iOS: native execution requires an ARM64 host; --inspect works on any host')
	}
	issues := image.execution_issues()
	if issues.len != 0 { return error('iOS: cannot execute:\n  ' + issues.join('\n  ')) }
	page := u64(C.getpagesize())
	layout := image.layout(page)!
	mut probe := faultprobe.install(options.probe_no_ads)!
	defer { faultprobe.restore(mut probe) or { eprintln(err) } }
	mapping := inline_self_map(image, layout)!
	defer { C.munmap(unsafe { voidptr(mapping.base - u64(mapping.prefix)) }, usize(layout.size) + mapping.prefix) }
	base := mapping.base
	objc_start()
	ns_process_info_start(arguments)
	$if ios_text ? { text_start()! }
	$if ios_gles ? { gles_start()! }
	if ios_runtime.trace { eprintln('iOS Mach-O mapping: 0x${base.hex()}') }
	image_runtime_start(image, layout, base)
	path := os.real_path(arguments[0])
	defer { unsafe { path.free() } }
	modules_start(image, layout, base, path, false)
	module_runtime.modules[0].thread_self_prefix = mapping.prefix
	module_runtime.probe_no_ads = options.probe_no_ads
	if options.probe_no_ads {
		eprintln('iOS DIAGNOSTIC PROBE: SKAdNetwork class import will bind to nil; application behavior is modified')
	}
	defer {
		url_session_task_require_shutdown()
		url_session_workers_stop()
		dispatch_stop()
		url_session_transfers_stop()
		ns_threads_join()
		swift_tasks_join()
		nw_stop()
		reachability_stop()
		image_tls_require_current()
		image_tls_finalize_current()
		if image_runtime.started { image_cxa_finalize(0) }
		image_tls_finalize_current()
		signals_stop()
		dyld_images_retire()
		image_tls_require_current()
		image_tls_finalize_current()
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
	image_progname_start(arguments[0])
	module_dependencies(0, 0)!
	lazy_start()!
	module_bind_all()!
	if options.probe_no_ads {
		for module in module_runtime.modules {
			eprintln('iOS probe image: base=0x${module.base.hex()} size=0x${module.layout.size.hex()} vmaddr=0x${module.layout.base.hex()} path=${module.path}')
		}
	}
	mut argv := []&char{cap: arguments.len + 1}
	for argument in arguments { argv << unsafe { &char(argument.str) } }
	argv << unsafe { &char(nil) }
	// A private null-terminated environment/Apple vector. No Darwin loader
	// globals are advertised until they have a compatible implementation.
	mut empty := [unsafe { &char(nil) }]!
	image_runtime.started = true
	if ios_runtime.trace { eprintln('iOS startup: Swift image metadata') }
	objc_complete_swift_images()!
	if ios_runtime.trace { eprintln('iOS startup: Objective-C +load') }
	objc_load_image()
	for index in module_runtime.order {
		if ios_runtime.trace { eprintln('iOS startup: initializers for ${module_runtime.modules[index].path}') }
		for address in module_runtime.modules[index].initializers {
			initializer := unsafe { ImageInitializer(voidptr(address)) }
			unsafe { initializer(arguments.len, &&char(argv.data), &empty[0], &empty[0]) }
		}
	}
	entry := unsafe { AppMain(voidptr(base + layout.entry)) }
	if ios_runtime.trace { eprintln('iOS startup: application entry') }
	return unsafe { entry(arguments.len, &&char(argv.data), &empty[0], &empty[0]) }
}
