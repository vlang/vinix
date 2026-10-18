// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The registry contains the main executable followed by its mapped bundled
// Mach-O libraries. Built-in V shims and native ELF libraries have no guest
// Mach-O header. Audit mode uses placeholder addresses, not loaded images.
// Loading finishes before application initializers; the registry and its
// owned paths survive until all application activity and destructors drain.
fn dyld_image_module(index u32) ?&LoadedModule {
	if module_runtime == unsafe { nil } || module_runtime.auditing
		|| u64(index) >= u64(module_runtime.modules.len) {
		return none
	}
	return module_runtime.modules[int(index)]
}

fn darwin_dyld_image_count() u32 {
	if module_runtime == unsafe { nil } || module_runtime.auditing { return 0 }
	return u32(module_runtime.modules.len)
}

// base is the reservation's start. The file's header need not occupy its
// lowest segment: find the readable mapping of file offset zero instead.
fn dyld_mapped_header(loaded &LoadedModule) u64 {
	for segment in loaded.image.segments {
		if segment.name != '__PAGEZERO' && segment.fileoff == 0
			&& segment.filesize >= 32 && segment.prot & 1 != 0 {
			return loaded.base + (segment.address - loaded.layout.base)
		}
	}
	return 0
}

fn darwin_dyld_get_image_header(index u32) voidptr {
	loaded := dyld_image_module(index) or { return unsafe { nil } }
	return unsafe { voidptr(dyld_mapped_header(loaded)) }
}

fn darwin_dyld_get_image_name(index u32) &char {
	loaded := dyld_image_module(index) or { return unsafe { nil } }
	return unsafe { &char(loaded.path.str) }
}

fn darwin_dyld_get_image_vmaddr_slide(index u32) i64 {
	loaded := dyld_image_module(index) or { return 0 }
	// Subtract address-width unsigned values, then interpret the result as
	// intptr_t. Negative slides preserve their bits without signed overflow.
	return i64(loaded.base - loaded.layout.base)
}
