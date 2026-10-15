// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDictionaryView { count u64 buckets u64 bitmap u64 keys u64 values u64 stride u64 }

fn swift_dictionary_empty_locked(owner u64) bool {
	return ios_runtime.swift_foundation_arena != 0 && owner == ios_runtime.swift_foundation_arena + u64(C.getpagesize()) + 3328
}

fn swift_dictionary_cocoa_checked(word u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || word & 0x8000000000000000 != 0 {
		return error('iOS: Dictionary bridge requires a live runtime and registered Cocoa storage')
	}
	object := word & 0x0ffffffffffffff8
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { return error('iOS: Dictionary bridge requires registered Cocoa storage') }
	if header.destroyed || header.destroying || header.releasing || read64(object) != header.cls
		|| !objc_is_kind(object, ios_runtime.names['NSDictionary']) {
		return error('iOS: Dictionary bridge requires live NSDictionary storage')
	}
	return object
}

fn swift_dictionary_view_checked(owner u64, key u64, value u64, hashable u64) !SwiftDictionaryView {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || owner == 0 || owner & 7 != 0 {
		return error('iOS: Dictionary bridge requires native storage')
	}
	C.ios_objc_initialize_lock()
	if swift_dictionary_empty_locked(owner) || swift_json_decoder_empty_locked(owner) || swift_json_encoder_empty_locked(owner) {
		C.ios_objc_initialize_unlock()
		return SwiftDictionaryView{}
	}
	storage := ios_runtime.swift_heap[owner] or { C.ios_objc_initialize_unlock(); return error('iOS: Dictionary bridge requires registered native storage') }
	C.ios_objc_initialize_unlock()
	if storage.deiniting || storage.size < 72 || storage.size > 16777216 || read64(owner) != storage.metadata {
		return error('iOS: invalid native Dictionary storage lifetime or extent')
	}
	metadata := storage.metadata
	if read64(metadata) <= 0x7ff { return error('iOS: Dictionary bridge requires native class metadata') }
	descriptor := read64(metadata + 64)
	if descriptor == 0 || descriptor & 3 != 0 || read32(descriptor) & 0x9f != 0x90 {
		return error('iOS: Dictionary bridge requires generic storage metadata')
	}
	name := swift_foreign_relative(descriptor + 8)!
	parent := swift_foreign_relative(descriptor + 4)!
	module_name := swift_foreign_relative(parent + 8)!
	if C.memcmp(voidptr(name), c'_DictionaryStorage', 19) != 0 || read32(parent) & 31 != 0
		|| C.memcmp(voidptr(module_name), c'Swift', 6) != 0 {
		return error('iOS: Dictionary bridge requires Swift._DictionaryStorage')
	}
	positive := u64(read32(descriptor + 28)); immediate := u64(read32(descriptor + 32))
	if immediate != 4 || positive < 14 || positive > 128 || read32(metadata + 56) < (positive * 8 + u64(read32(metadata + 60))) {
		return error('iOS: unsupported Dictionary generic metadata layout')
	}
	arguments := metadata + (positive - immediate) * 8
	if read64(arguments) != key || read64(arguments + 8) != value || read64(arguments + 16) != hashable {
		return error('iOS: Dictionary bridge generic arguments do not match storage')
	}
	if key != swift_string_metadata() { return error('iOS: native Dictionary bridge currently requires String keys') }
	if value != swift_string_metadata() && value != swift_integer_metadata() && value != swift_any_full_metadata() + 8 {
		C.ios_objc_initialize_lock()
		if _ := swift_nsobject_class_locked(value) {} else { C.ios_objc_initialize_unlock(); return error('iOS: Dictionary bridge value type is not implemented') }
		C.ios_objc_initialize_unlock()
	}
	layout := swift_sequence_value_checked(value)!
	stride := read64(read64(value - 8) + 72)
	scale := unsafe { *(&u8(owner + 32)) }
	if scale == 0 || scale > 14 || layout.alignment > 8 { return error('iOS: Dictionary bridge storage exceeds supported scale or alignment') }
	buckets := u64(1) << scale; words := (buckets + 63) / 64
	keys := u64(64) + words * 8
	values := keys + buckets * 16
	count := read64(owner + 16)
	if count > 4096 || count > read64(owner + 24) || read64(owner + 24) != buckets - buckets / 4 - if buckets == 2 { u64(1) } else { u64(0) }
		|| values > storage.size || buckets > (storage.size - values) / stride
		|| read64(owner + 48) != owner + keys || read64(owner + 56) != owner + values {
		return error('iOS: Dictionary bridge storage fields are inconsistent')
	}
	mut occupied := u64(0)
	for bucket in u64(0) .. buckets { if read64(owner + 64 + bucket / 64 * 8) & (u64(1) << (bucket & 63)) != 0 { occupied++ } }
	if occupied != count { return error('iOS: Dictionary bridge occupancy does not match count') }
	return SwiftDictionaryView{count: count, buckets: buckets, bitmap: owner + 64, keys: owner + keys, values: owner + values, stride: stride}
}

fn swift_dictionary_bridge_value(address u64, metadata u64) !u64 {
	if metadata == swift_any_full_metadata() + 8 {
		layout := swift_any_layout(address)!
		if layout.boxed || layout.metadata == metadata { return error('iOS: Dictionary bridge boxed or nested Any values are not implemented') }
		return swift_dictionary_bridge_value(address, layout.metadata)
	}
	if metadata == swift_string_metadata() {
		scratch := u64(C.__builtin_alloca(16))
		words := unsafe { *(&SwiftStringWords(address)) }
		bytes := swift_string_bytes(words, scratch)!
		if bytes.count > 1048576 { return error('iOS: Dictionary bridge String exceeds supported size') }
		return owned_string(unsafe { tos(&u8(bytes.address), int(bytes.count)) })
	}
	if metadata == swift_integer_metadata() {
		object := objc_allocate(ios_runtime.names['NSNumber'])
		obj_header(object).number = unsafe { *(&i64(address)) }
		return object
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	cls := swift_nsobject_class_locked(metadata)!
	object := read64(address)
	if object == 0 { return error('iOS: Dictionary bridge does not accept nil object values') }
	swift_nsobject_owner_locked(object, cls)!
	return objc_retain(object)
}

// Ordinary x0..x3 arguments: borrowed storage word, Key/Value metadata and
// Key:Hashable table. Self and x8 are unused; x0 returns an owned NSDictionary.
fn swift_foundation_dictionary_bridge_checked(source u64, key u64, value u64, hashable u64) !u64 {
	if source & 0xc000000000000001 != 0 { return objc_retain(swift_dictionary_cocoa_checked(source)!) }
	view := swift_dictionary_view_checked(source, key, value, hashable)!
	if view.count == 0 { return objc_retain(framework_empty_dictionary()) }
	object := objc_allocate(ios_runtime.names['NSDictionary'])
	mut published := false
	defer { if !published { objc_release(object) } }
	mut capacity := u64(2)
	for capacity < view.count * 2 { capacity *= 2 }
	indices := u64(C.calloc(usize(capacity), 8))
	if indices == 0 { return error('iOS: cannot allocate Dictionary duplicate-key index') }
	defer { C.free(voidptr(indices)) }
	mut header := obj_header(object)
	// These two arrays belong to the Objective-C owner. Zeroed unused entries
	// make a partially converted snapshot safe to destroy on a conversion error.
	header.keys = []u64{len: int(view.count)}; header.keys.flags |= .noslices
	header.items = []u64{len: int(view.count)}; header.items.flags |= .noslices
	mut index := 0
	for bucket in u64(0) .. view.buckets {
		if read64(view.bitmap + bucket / 64 * 8) & (u64(1) << (bucket & 63)) == 0 { continue }
		header.keys[index] = swift_dictionary_bridge_value(view.keys + bucket * 16, key)!
		mut slot := cf_hash(header.keys[index]) & (capacity - 1)
		for read64(indices + slot * 8) != 0 {
			previous := int(read64(indices + slot * 8) - 1)
			if object_equal(header.keys[previous], header.keys[index]) { return error('iOS: Dictionary bridge contains duplicate bridged keys') }
			slot = (slot + 1) & (capacity - 1)
		}
		unsafe { *(&u64(indices + slot * 8)) = u64(index + 1) }
		header.items[index] = swift_dictionary_bridge_value(view.values + bucket * view.stride, value)!
		index++
	}
	published = true
	return object
}

fn swift_foundation_dictionary_bridge(source u64, key u64, value u64, hashable u64) u64 {
	return swift_foundation_dictionary_bridge_checked(source, key, value, hashable) or { panic(err) }
}

fn swift_dictionary_emit(data u64) {
	owner := data + 3328
	unsafe {
		*(&u64(owner)) = data + 3456; *(&u64(owner + 8)) = 0x80000004ffffffff
		*(&u64(owner + 48)) = 1; *(&u64(owner + 56)) = 1; *(&u64(owner + 64)) = ~u64(1)
		*(&u64(data + 3456)) = 0x500
	}
}
