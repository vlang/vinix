// SPDX-License-Identifier: GPL-2.0-or-later
module main

type ObjSwiftInitializer = fn (u64, u64) u64
struct ObjSwiftImageClass { descriptor u64 initializer u64 }

// Registration runs while images are RW and non-executable. Validate against
// file-backed storage and the final protections, including SG_READ_ONLY.
fn (m ObjMetadata) swift_range(address u64, size u64, alignment u64, protection u32) ! {
	if address == 0 || address % alignment != 0 || size > m.layout.size { return swift_singleton_metadata_failure() }
	for segment in m.image.segments {
		if segment.name == '__PAGEZERO' { continue }
		start := m.base + segment.address - m.layout.base
		prot := segment.prot & if segment.flags & 0x10 != 0 { ~u32(2) } else { ~u32(0) }
		if address >= start && address - start <= segment.filesize
			&& size <= segment.filesize - (address - start) && prot & protection == protection { return }
	}
	return swift_singleton_metadata_failure()
}

// Bounded Swift 5, version-zero, nongeneric formal roots. All storage used by
// the singleton/class-layout path is checked before publishing the class.
fn (m ObjMetadata) swift_class(cls u64, ro u64) !ObjSwiftImageClass {
	m.swift_range(cls, 80, 8, 3)!
	m.swift_range(ro, 80, 8, 3)!
	d := read64(cls + 64)
	m.swift_range(d, 56, 4, 1)!
	flags := read32(d); count := u64(read32(d + 36))
	ap := u64(read32(cls + 60)); size := u64(read32(cls + 56))
	parent := read64(cls + 8)
	info := ios_runtime.classes[parent] or { return swift_singleton_metadata_failure() }
	if info.meta || info.parent != 0 || info.size != 16 || info.name != '_TtCs12_SwiftObject'
		|| read32(ro) != 0xc0 || read32(ro + 4) < 16 || read32(ro + 8) < read32(ro + 4)
		|| read32(ro + 8) > 1048576 || read64(cls + 32) & 7 !in [u64(1),2]!
		|| read32(cls + 40) != 2 || read32(cls + 44) != 0
		|| flags & ~u32(0x80000040) != 0x10010 || read32(d + 20) != 0 || count > 64
		|| (count != 0 && read32(d + 40) != 10) || ap !in [u64(16),24]!
		|| u64(read32(d + 24)) * 8 != ap || size < ap + 80 + count * 8 || size > 1048576
		|| u64(read32(d + 28)) * 8 + ap != size || read32(d + 32) < count
		|| read32(d + 32) > read32(d + 28) { return swift_singleton_metadata_failure() }
	m.swift_range(cls - ap, size, 8, 3)!
	value := swift_singleton_metadata_descriptor(d)!
	if !value.is_class || value.metadata != cls { return swift_singleton_metadata_failure() }
	m.swift_range(value.cache, 16, 8, 3)!
	m.swift_range(value.complete, 4, 4, 5)!
	if read64(value.cache) != 0 || read64(value.cache + 8) != 0 { return swift_singleton_metadata_failure() }
	initializer := read64(ro + 72)
	m.swift_range(initializer, 4, 4, 5)!
	meta := read64(cls)
	m.swift_range(meta, 40, 8, 1)!
	mr := read64(meta + 32) & ~u64(7)
	m.swift_range(mr, 72, 8, 1)!
	if read32(mr) != 0x81 || read64(meta) != read64(parent) || read64(meta + 8) != read64(parent) {
		return swift_singleton_metadata_failure()
	}
	// Validate the metaclass before the ordinary registrar reads its lists.
	mut methods := m.methods(read64(mr + 32))!
	unsafe { methods.free() }
	if read64(mr + 48) != 0 { return swift_singleton_metadata_failure() }
	if flags & 0x80000000 != 0 {
		m.swift_range(d + 56, 8, 4, 1)!
		offset := u64(read32(d + 56)); entries := u64(read32(d + 60))
		if entries > 64 || offset < 10 + count || offset > read32(d + 28)
			|| entries > u64(read32(d + 28)) - offset { return swift_singleton_metadata_failure() }
		m.swift_range(d + 64, entries * 8, 4, 1)!
		for i in u64(0)..entries {
			e := d + 68 + i * 8
			slot := read64(cls + (offset + i) * 8)
			if read32(e) == 0 {
				// Swift emits a null implementation for a deleted method, with
				// its vtable slot bound to this exact libswiftCore import.
				if read32(e - 4) != 1 || slot != u64(unsafe { voidptr(swift_deleted_method_failure) }) {
					return swift_singleton_metadata_failure()
				}
			} else {
				target := swift_generic_metadata_relative(e, 4)!
				m.swift_range(target, 4, 4, 5)!
				if slot != target { return swift_singleton_metadata_failure() }
			}
		}
	}
	list := read64(ro + 48)
	if count != 0 && list == 0 { return swift_singleton_metadata_failure() }
	if list != 0 {
		m.swift_range(list, 8 + count * 32, 8, 1)!
		if read32(list) != 32 || read32(list + 4) != count { return swift_singleton_metadata_failure() }
	}
	mut names := map[string]bool{}
	defer { unsafe { names.free() } }
	for i in u64(0)..count {
		e := list + 8 + i * 32; cell := read64(e)
		m.swift_range(cell, 8, 8, 3)!
		position := read64(cell)
		if position != read64(cls + 80 + i * 8) || position > read32(ro + 8)
			|| read32(e + 28) > u64(read32(ro + 8)) - position || read32(e + 24) > 8 { return swift_singleton_metadata_failure() }
		name := m.string_at(read64(e + 8))!
		m.type_at(read64(e + 16))!
		if name in names { return swift_singleton_metadata_failure() }
		names[name] = true
		for j in u64(0)..i { if read64(list + 8 + j * 32) == cell { return swift_singleton_metadata_failure() } }
	}
	return ObjSwiftImageClass{d, initializer}
}

fn objc_complete_swift_class(cls u64) ! {
	swift_generic_metadata_begin()!
	defer { swift_generic_metadata_end() }
	C.ios_objc_initialize_lock()
	mut info := ios_runtime.classes[cls] or { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
	if info.swift_initializer == 0 || info.swift_image_phase == 2 { C.ios_objc_initialize_unlock(); return }
	if info.swift_image_phase != 0 { C.ios_objc_initialize_unlock(); return swift_singleton_metadata_failure() }
	info.swift_image_phase = 1
	initializer := info.swift_initializer; descriptor := info.swift_descriptor
	C.ios_objc_initialize_unlock()
	// Apple's metadata initializer is C ABI (Class, void*) -> Class. Keep the
	// registry unlocked for runtime reentry. Relocated identities stay guarded.
	result := unsafe { ObjSwiftInitializer(voidptr(initializer))(cls, 0) }
	witness := swift_native_value_witnesses()
	C.ios_objc_initialize_lock()
	mut valid := result == cls
	value := swift_singleton_metadata_descriptor(descriptor) or { valid = false; SwiftSingletonMetadata{} }
	mut completed := false
	if valid && value.metadata == cls && ios_runtime.swift_generic_metadata_arena != 0 {
		cache := unsafe { &SwiftGenericMetadataCache(ios_runtime.swift_generic_metadata_arena) }
		for i in u64(0)..ios_runtime.swift_generic_metadata_count {
			e := unsafe { &cache.entries[int(i)] }
			if e.descriptor == descriptor && e.singleton_cache == value.cache && e.metadata == cls && e.phase == 2 { completed = true; break }
		}
	}
	valid = valid && completed
	if valid {
		valid = read64(value.cache) == cls
		swift_singleton_class_layout_locked(value, descriptor, witness, true) or { valid = false }
	}
	info.swift_image_phase = if valid { u8(2) } else { u8(3) }
	C.ios_objc_initialize_unlock()
	if !valid { return swift_singleton_metadata_failure() }
}

fn objc_complete_swift_images() ! {
	// Called only after module_bind_all has bound and sealed every image, before
	// +load or module initializers. No image code runs in the registrar.
	for cls in ios_runtime.load_classes { objc_complete_swift_class(cls)! }
}
