// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct DarwinDlInfo {
mut:
	filename &char = unsafe { nil }
	base voidptr
	symbol &char = unsafe { nil }
	address voidptr
}

fn dyld_error(message string) {
	unsafe { system_data.dl_error.free() }
	system_data.dl_error = message
	system_data.dl_error_pending = true
}

// Libraries linked from the bundle remain loaded for the process lifetime.
// Loading a new image from a running app is still unsupported.
fn darwin_dlopen(path &char, flags i32) u64 {
	_ = flags
	if path == unsafe { nil } { return u64(system_data) }
	raw_name := ctext(u64(path))
	name := if raw_name == '/usr/lib/libSystem.dylib' { '/usr/lib/libSystem.B.dylib' } else { raw_name }
	if module_runtime != unsafe { nil } {
		if index := module_runtime.modules[0].dependencies[name] {
			if index >= 0 { return u64(module_runtime.modules[index]) }
		}
		for loaded in module_runtime.modules {
			if loaded.path == name || loaded.image.install_name == name { return u64(loaded) }
		}
	}
	for i, library in image_runtime.image.libraries {
		if library.name == name && !name.ends_with('libMoltenVK.dylib') { return u64(i) + 1 }
	}
	dyld_error('iOS: external library loading is not implemented: ${name}')
	return 0
}

fn darwin_dlsym(handle u64, name &char) u64 {
	if name == unsafe { nil } { return 0 }
	text := ctext(u64(name))
	if text == '__isPlatformVersionAtLeast' { return u64(unsafe { voidptr(darwin_platform_at_least) }) }
	if text in ['csops', 'ptrace'] { return u64(unsafe { voidptr(darwin_unsupported_systemcall) }) }
	symbol := '_' + text
	if module_runtime != unsafe { nil } {
		for loaded in module_runtime.modules {
			if handle != u64(loaded) { continue }
			address := loaded.image.exported_address(symbol, loaded.layout, loaded.base) or {
				dyld_error(err.msg()); return 0
			}
			if address != 0 { return address }
		}
	}
	if handle > 0 && handle <= u64(image_runtime.image.libraries.len) {
		library := image_runtime.image.libraries[int(handle - 1)]
		if address := runtime_symbol(library.name, symbol) { return address }
	} else if handle == u64(system_data) || handle == ~u64(1) { // RTLD_DEFAULT
		if module_runtime != unsafe { nil } {
			for loaded in module_runtime.modules {
				address := loaded.image.exported_address(symbol, loaded.layout, loaded.base) or { u64(0) }
				if address != 0 { return address }
			}
		}
		own := image_runtime.image.exported_address(symbol, image_runtime.layout, image_runtime.base) or { u64(0) }
		if own != 0 { return own }
		for library in image_runtime.image.libraries {
			if address := module_symbol(0, library.name, symbol) { return address }
		}
	}
	dyld_error('iOS: dynamic symbol is not implemented: ${text}')
	return 0
}

fn darwin_dlclose(handle u64) i32 {
	if module_runtime != unsafe { nil } {
		for loaded in module_runtime.modules { if handle == u64(loaded) { return 0 } }
	}
	if handle == u64(system_data) || (handle > 0 && handle <= u64(image_runtime.image.libraries.len)) { return 0 }
	dyld_error('iOS: invalid dynamic library handle'.clone())
	return -1
}

fn darwin_dlerror() &char {
	if !system_data.dl_error_pending { return unsafe { nil } }
	system_data.dl_error_pending = false
	return unsafe { &char(system_data.dl_error.str) }
}

fn darwin_dladdr(address u64, info &DarwinDlInfo) i32 {
	if info == unsafe { nil } { return 0 }
	if module_runtime == unsafe { nil } { return 0 }
	for loaded in module_runtime.modules {
		for segment in loaded.image.segments {
			if segment.name == '__PAGEZERO' { continue }
			start := loaded.base + segment.address - loaded.layout.base
			if address >= start && address - start < segment.size {
				unsafe { *info = DarwinDlInfo{filename: &char(loaded.path.str), base: voidptr(loaded.base)} }
				return 1
			}
		}
	}
	return 0
}

fn darwin_getsectiondata(header u64, segment_name &char, section_name &char, size &u64) u64 {
	if size == unsafe { nil } { return 0 }
	unsafe { *size = 0 }
	if module_runtime == unsafe { nil } { return 0 }
	for loaded in module_runtime.modules {
		if header != loaded.base { continue }
		for segment in loaded.image.segments {
			if segment.name != ctext(u64(segment_name)) { continue }
			for section in segment.sections {
				if section.name != ctext(u64(section_name)) { continue }
				if section.address < segment.address || section.address - segment.address > segment.filesize
					|| section.size > segment.filesize - (section.address - segment.address) { return 0 }
				unsafe { *size = section.size }
				return loaded.section_address(section)
			}
		}
	}
	return 0
}

fn darwin_unsupported_systemcall(_ i64) i64 {
	// Vinix has no Darwin csops/ptrace services. Let native callers fall back
	// (PPSSPP selects its interpreter) instead of issuing a Linux syscall.
	darwin_set_errno(78) // Darwin ENOSYS
	return -1
}

fn C.ios_posix_spawn_default(voidptr, &char, &&char, &&char) i32

fn darwin_posix_spawnp(pid voidptr, path &char, actions voidptr, attributes voidptr, arguments &&char, environment &&char) i32 {
	if actions != unsafe { nil } || attributes != unsafe { nil } { return 22 }
	result := C.ios_posix_spawn_default(pid, path, arguments, environment)
	$if linux {
		return match result {
			11 { 35 } // EAGAIN
			35 { 11 } // EDEADLK
			36 { 63 } // ENAMETOOLONG
			38 { 78 } // ENOSYS
			40 { 62 } // ELOOP
			95 { 45 } // ENOTSUP
			else { result }
		}
	}
	return result
}

fn darwin_availability(count u32, versions &u32) bool {
	if count > 64 || (count != 0 && versions == unsafe { nil }) { return false }
	for i in 0 .. count {
		platform := unsafe { versions[i * 2] }
		version := unsafe { versions[i * 2 + 1] }
		if platform != 2 || version > 0x110000 { return false }
	}
	return true
}

fn darwin_platform_at_least(platform u32, major u32, minor u32, patch u32) bool {
	if platform != 2 { return false }
	return major < 17 || (major == 17 && minor == 0 && patch == 0)
}

fn dyld_symbol(symbol string) ?u64 {
	return match symbol {
		'_dlopen' { u64(unsafe { voidptr(darwin_dlopen) }) }
		'_dlsym' { u64(unsafe { voidptr(darwin_dlsym) }) }
		'_dlclose' { u64(unsafe { voidptr(darwin_dlclose) }) }
		'_dlerror' { u64(unsafe { voidptr(darwin_dlerror) }) }
		'_dladdr' { u64(unsafe { voidptr(darwin_dladdr) }) }
		'_getsectiondata' { u64(unsafe { voidptr(darwin_getsectiondata) }) }
		'_syscall' { u64(unsafe { voidptr(darwin_unsupported_systemcall) }) }
		'_posix_spawnp' { u64(unsafe { voidptr(darwin_posix_spawnp) }) }
		'__availability_version_check' { u64(unsafe { voidptr(darwin_availability) }) }
		else { return none }
	}
}
