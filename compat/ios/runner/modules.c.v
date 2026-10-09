// SPDX-License-Identifier: GPL-2.0-or-later
// Native app-bundled Mach-O libraries; no host Apple library is loaded.
module main

import macho
import os

struct LoadedModule {
	image  macho.Image
	layout macho.Layout
	base   u64
	path   string
mut:
	dependencies map[string]int
	initializers []u64
	visiting     bool
}

struct ModuleRuntime {
mut:
	modules  []&LoadedModule
	paths    map[string]int
	order    []int
	binding  int
	bytes    u64
	auditing bool
}

__global module_runtime = unsafe { &ModuleRuntime(nil) }

fn module_builtin(name string) bool {
	return name.starts_with('/System/Library/') || name.starts_with('/usr/lib/')
}

fn module_expand_path(name string, owner &LoadedModule) !string {
	if name.starts_with('@executable_path/') {
		root := os.dir(module_runtime.modules[0].path)
		defer { unsafe { root.free() } }
		return os.join_path(root, name[17..])
	}
	if name.starts_with('@loader_path/') {
		root := os.dir(owner.path)
		defer { unsafe { root.free() } }
		return os.join_path(root, name[13..])
	}
	if name.starts_with('/') { return name.clone() }
	return error('iOS: unsupported library path: ${name}')
}

fn module_path(name string, owner &LoadedModule) !string {
	if name.starts_with('@rpath/') {
		// Search the loading image, then the executable's inherited runpaths.
		for provider in [owner, module_runtime.modules[0]]! {
			for runpath in provider.image.rpaths {
				expanded := runpath + '/'
				defer { unsafe { expanded.free() } }
				root := module_expand_path(expanded, provider) or { continue }
				candidate := os.join_path(root, name[7..])
				unsafe { root.free() }
				defer { unsafe { candidate.free() } }
				if os.is_file(candidate) { return os.real_path(candidate) }
			}
		}
		return error('iOS: library not found in runpaths: ${name}')
	}
	path := module_expand_path(name, owner)!
	defer { unsafe { path.free() } }
	if !os.is_file(path) { return error('iOS: bundled library not found: ${path}') }
	return os.real_path(path)
}

fn module_image_free(image macho.Image) {
	for segment in image.segments {
		for section in segment.sections {
			unsafe { section.name.free() }
		}
		unsafe {
			segment.sections.free()
			segment.name.free()
		}
	}
	for library in image.libraries {
		unsafe { library.name.free() }
	}
	unsafe {
		image.data.free()
		image.segments.free()
		image.libraries.free()
		image.install_name.free()
		image.rpaths.free()
		image.routines.free()
		image.required_unknown.free()
	}
}

fn modules_start(image macho.Image, layout macho.Layout, base u64, path string, auditing bool) {
	module_runtime = &ModuleRuntime{ auditing: auditing }
	module_runtime.modules.flags |= .noslices
	module_runtime.order.flags |= .noslices
	main_module := &LoadedModule{ image: image, layout: layout, base: base, path: path.clone() }
	module_runtime.modules << main_module
	module_runtime.paths[path] = 0
	module_runtime.bytes = layout.size
}

fn module_dependencies(index int, depth int) ! {
	if depth > 64 { return error('iOS: library dependency depth exceeds limit') }
	mut owner := module_runtime.modules[index]
	if owner.visiting {
		return error('iOS: cyclic library initialization is not implemented: ${owner.path}')
	}
	owner.visiting = true
	for library in owner.image.libraries {
		if module_builtin(library.name) { continue }
		path := module_path(library.name, owner) or {
			if library.weak {
				owner.dependencies[library.name] = -1
				continue
			}
			return err
		}
		defer { unsafe { path.free() } }
		mut target := module_runtime.paths[path] or { -1 }
		if target < 0 {
			if module_runtime.modules.len >= 64 {
				return error('iOS: loaded library count exceeds limit')
			}
			data := os.read_bytes(path)!
			defer { unsafe { data.free() } }
			image := macho.parse(data)!
			mut transferred := false
			defer { if !transferred { module_image_free(image) } }
			issues := image.dylib_issues()
			defer { unsafe { issues.free() } }
			if issues.len != 0 {
				return error('iOS: cannot load ${path}:\n  ' + issues.join('\n  '))
			}
			layout := image.layout(u64(C.getpagesize()))!
			if module_runtime.bytes + layout.size > 1024 * 1024 * 1024 {
				return error('iOS: loaded library span exceeds limit')
			}
			mapping := if module_runtime.auditing {
				unsafe { voidptr(1) }
			} else {
				C.mmap(unsafe { nil }, usize(layout.size), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			}
			if mapping == unsafe { voidptr(-1) } {
				return error('iOS: cannot allocate library mapping')
			}
			target = module_runtime.modules.len
			module_runtime.modules << &LoadedModule{ image: image, layout: layout, base: u64(mapping), path: path.clone() }
			module_runtime.paths[path] = target
			module_runtime.bytes += layout.size
			transferred = true
			module_dependencies(target, depth + 1)!
		} else if module_runtime.modules[target].visiting {
			return error('iOS: cyclic library initialization is not implemented: ${path}')
		}
		owner.dependencies[library.name] = target
	}
	owner.visiting = false
	module_runtime.order << index
}

fn module_symbol(owner_index int, library string, symbol string) !u64 {
	if module_runtime == unsafe { nil } { return runtime_symbol(library, symbol) }
	owner := module_runtime.modules[owner_index]
	if library in ['<self>', '<main executable>'] {
		target := module_runtime.modules[if library == '<self>' { owner_index } else { 0 }]
		address := target.image.exported_address(symbol, target.layout, target.base)!
		if address != 0 { return address }
		return error('iOS: image does not export ${symbol}')
	}
	if target_index := owner.dependencies[library] {
		if target_index < 0 { return error('iOS: weak library is absent: ${library}') }
		target := module_runtime.modules[target_index]
		address := target.image.exported_address(symbol, target.layout, target.base)!
		if address != 0 { return address }
		return error('iOS: bundled library does not export ${symbol}: ${library}')
	}
	return runtime_symbol(library, symbol)
}

fn module_bind_symbol(library string, symbol string) !u64 {
	return module_symbol(module_runtime.binding, library, symbol)
}

fn module_bind_all() ! {
	for index in module_runtime.order {
		module_runtime.binding = index
		loaded := module_runtime.modules[index]
		fixups := loaded.image.plan_fixups_with_lazy(loaded.layout, loaded.base, module_bind_symbol, lazy_symbol) or {
			return error('iOS: linking ${loaded.path}: ${err}')
		}
		defer { unsafe { fixups.free() } }
		for segment in loaded.image.segments {
			if segment.name == '__PAGEZERO' || segment.filesize == 0 { continue }
			unsafe { C.memcpy(voidptr(loaded.base + segment.address - loaded.layout.base), &loaded.image.data[int(segment.fileoff)], usize(segment.filesize)) }
		}
		for fixup in fixups {
			lazy_register_slot(loaded, fixup.offset, fixup.value)
			value := fixup.value
			unsafe { C.memcpy(voidptr(loaded.base + fixup.offset), &value, 8) }
		}
		objc_register_image(loaded.image, loaded.layout, loaded.base)!
		module_runtime.modules[index].initializers = image_initializers(loaded)!
		image_tls_prepare(loaded)!
	}
	module_runtime.binding = 0
	lazy_seal()!
	page := u64(C.getpagesize())
	for loaded in module_runtime.modules {
		C.__builtin___clear_cache(unsafe { voidptr(loaded.base) }, unsafe { voidptr(loaded.base + loaded.layout.size) })
		if C.mprotect(unsafe { voidptr(loaded.base) }, usize(loaded.layout.size), C.PROT_NONE) != 0 {
			return error('iOS: cannot protect image gaps')
		}
		for segment in loaded.image.segments {
			if segment.name == '__PAGEZERO' || segment.size == 0 { continue }
			size := (segment.size + page - 1) & ~(page - 1)
			prot := if segment.flags & 0x10 != 0 { segment.prot & ~u32(2) } else { segment.prot }
			if C.mprotect(unsafe { voidptr(loaded.base + segment.address - loaded.layout.base) }, usize(size), int(prot)) != 0 {
				return error('iOS: cannot apply segment protections to ${segment.name}')
			}
		}
	}
}

fn modules_stop() {
	for index, loaded in module_runtime.modules {
		if index != 0 {
			if !module_runtime.auditing {
				C.munmap(unsafe { voidptr(loaded.base) }, usize(loaded.layout.size))
			}
			module_image_free(loaded.image)
		}
		unsafe {
			loaded.dependencies.free()
			loaded.initializers.free()
			loaded.path.free()
			free(loaded)
		}
	}
	unsafe {
		module_runtime.modules.free()
		module_runtime.paths.free()
		module_runtime.order.free()
		free(module_runtime)
	}
	module_runtime = unsafe { nil }
}
