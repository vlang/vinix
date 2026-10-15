// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftArrayBridgeFailure {}
fn (_ &SwiftArrayBridgeFailure) msg() string { return 'iOS: NSArray bridge requires live registered object storage and supported String, URL or NSObject-derived elements' }
fn (_ &SwiftArrayBridgeFailure) code() int { return 1 }
__global swift_array_bridge_failure_value = SwiftArrayBridgeFailure{}
fn swift_array_bridge_failure() IError { return unsafe { &swift_array_bridge_failure_value } }

struct SwiftArrayBridgeSnapshot { items u64 count u64 }

fn swift_array_bridge_snapshot(source u64) !SwiftArrayBridgeSnapshot {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[source] or { return swift_array_bridge_failure() }
	if header.releasing || header.destroying || header.destroyed || read64(source) != header.cls
		|| header.cf_raw_values || header.items.len > 4096
		|| !objc_is_kind(source, ios_runtime.names['NSArray']) { return swift_array_bridge_failure() }
	for item in header.items {
		if item == 0 { return swift_array_bridge_failure() }
		swift_nsobject_owner_locked(item, ios_runtime.names['NSObject'])!
	}
	count := u64(header.items.len)
	if count == 0 { return SwiftArrayBridgeSnapshot{} }
	items := u64(C.malloc(usize(count * 8)))
	if items == 0 { return swift_array_bridge_failure() }
	for i, item in header.items { unsafe { *(&u64(items + u64(i * 8))) = objc_retain(item) } }
	return SwiftArrayBridgeSnapshot{items, count}
}

fn swift_array_bridge_snapshot_release(snapshot SwiftArrayBridgeSnapshot) {
	for i in u64(0) .. snapshot.count { objc_release(read64(snapshot.items + i * 8)) }
	if snapshot.items != 0 { C.free(voidptr(snapshot.items)) }
}

fn swift_array_bridge_element(element u64) !u64 {
	if element == swift_string_metadata() { return u64(0) }
	if element == swift_foundation_arena() + u64(C.getpagesize()) + 144 { return u64(1) }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return swift_nsobject_class_locked(element)!
}

// The installed ARM64 export borrows optional NSArray in x0 and Element
// metadata in x1, ignores Self/x8 and returns an owned Array word in x0.
// Nil reads no Element metadata. Materialize existing typed storage so all
// Array value witnesses and Sequence operations can consume the result.
fn swift_foundation_array_unbridge_checked(source u64, element u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return swift_array_bridge_failure() }
	if source == 0 { return swift_array_empty() }
	kind := swift_array_bridge_element(element)!
	snapshot := swift_array_bridge_snapshot(source)!
	defer { swift_array_bridge_snapshot_release(snapshot) }
	layout := swift_array_layout(i64(snapshot.count), element)!
	allocation := swift_array_allocate_layout(layout, 0)
	mut published := false
	defer { if !published { swift_bridge_release(allocation.owner) } }
	for i in u64(0) .. snapshot.count {
		item := read64(snapshot.items + i * 8)
		destination := allocation.bytes + i * layout.storage.stride
		if kind == 0 {
			words := swift_foundation_unbridge_checked(item)!
			unsafe { *(&SwiftStringWords(destination)) = words }
		} else if kind == 1 {
			words := swift_array_bridge_url_checked(item)!
			unsafe { *(&SwiftURLWords(destination)) = words }
		} else {
			C.ios_objc_initialize_lock()
			swift_nsobject_owner_locked(item, kind) or { C.ios_objc_initialize_unlock(); return err }
			unsafe { *(&u64(destination)) = objc_retain(item) }
			C.ios_objc_initialize_unlock()
		}
		// Only initialized elements participate in partial-result destruction.
		unsafe { *(&u64(allocation.owner + 16)) = i + 1 }
	}
	published = true
	return allocation.owner
}

fn swift_foundation_array_unbridge(source u64, element u64) u64 {
	return swift_foundation_array_unbridge_checked(source, element) or { panic(err) }
}

// NSURL itself is a valid unknown-ARC implementation owner for URL's existing
// two-word value. The private sealed table supplies its borrowed bridge slot.
fn swift_array_bridge_url_checked(item u64) !SwiftURLWords {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[item] or { return swift_array_bridge_failure() }
	if header.releasing || header.destroying || header.destroyed || read64(item) != ios_runtime.names['NSURL']
		|| header.cls != ios_runtime.names['NSURL'] { return swift_array_bridge_failure() }
	return SwiftURLWords{owner: objc_retain(item), table: swift_foundation_arena() + u64(C.getpagesize()) + 3520}
}

fn swift_array_bridge_url_object(owner u64) u64 {
	return (swift_array_bridge_url_checked(owner) or { panic(err) }).owner
}

fn swift_array_bridge_url_path(owner u64) !string {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[owner] or { return swift_array_bridge_failure() }
	if header.releasing || header.destroying || header.destroyed || read64(owner) != ios_runtime.names['NSURL']
		|| header.cls != ios_runtime.names['NSURL'] || header.number == 1 || header.fields[0] == 0 { return swift_array_bridge_failure() }
	swift_nsobject_owner_locked(header.fields[0], ios_runtime.names['NSString'])!
	path := string_text(header.fields[0])
	if path.len == 0 || path.len > 65536 || path[0] != `/` || path.contains('\x00') { return swift_array_bridge_failure() }
	return path
}

fn swift_array_bridge_file_url(path string, directory bool) SwiftURLWords {
	// A deleted parent is a bounded prefix, with no NUL at its end. Preserve
	// the explicit length instead of passing its bytes to a C-string factory.
	url := objc_allocate(ios_runtime.names['NSURL'])
	text_path := owned_string(path)
	store_field(url, 0, text_path); objc_release(text_path)
	if directory && path != '/' {
		text := string_text(ui_file_url_string(url))
		with_slash := text + '/'
		defer { unsafe { with_slash.free() } }
		absolute := owned_string(with_slash)
		store_field(url, 1, absolute); objc_release(absolute)
	}
	return SwiftURLWords{owner: url, table: swift_foundation_arena() + u64(C.getpagesize()) + 3520}
}

fn swift_array_bridge_url_append_checked(first u64, second u64, directory u64, owner u64) !SwiftURLWords {
	if directory > 1 { return swift_array_bridge_failure() }
	path := swift_array_bridge_url_path(owner)!
	scratch := u64(C.__builtin_alloca(16))
	bytes := swift_string_bytes(SwiftStringWords{first, second}, scratch)!
	if bytes.count == 0 || bytes.count > 4096 { return swift_array_bridge_failure() }
	component := unsafe { tos(&u8(bytes.address), int(bytes.count)) }
	if component in ['.', '..']! || component.contains('/') || component.contains('\\') || component.contains('\x00') { return swift_array_bridge_failure() }
	mut end := path.len
	for end > 1 && path[end - 1] == `/` { end-- }
	separator := if end == 1 { 0 } else { 1 }
	length := end + separator + component.len
	if length > 65536 { return swift_array_bridge_failure() }
	joined := C.malloc(usize(length))
	if joined == unsafe { nil } { return swift_array_bridge_failure() }
	defer { C.free(joined) }
	C.memcpy(joined, path.str, usize(end))
	if separator != 0 { unsafe { *(&u8(u64(joined) + u64(end))) = `/` } }
	C.memcpy(voidptr(u64(joined) + u64(end + separator)), component.str, usize(component.len))
	return swift_array_bridge_file_url(unsafe { tos(&u8(joined), length) }, directory != 0)
}

fn swift_array_bridge_url_append(first u64, second u64, directory u64, _metadata u64, _table u64, owner u64, output u64) {
	words := swift_array_bridge_url_append_checked(first, second, directory, owner) or { panic(err) }
	unsafe { *(&SwiftURLWords(output)) = words }
}

fn swift_array_bridge_url_delete_checked(owner u64) !SwiftURLWords {
	path := swift_array_bridge_url_path(owner)!
	mut end := path.len
	for end > 1 && path[end - 1] == `/` { end-- }
	for end > 1 && path[end - 1] != `/` { end-- }
	for end > 1 && path[end - 1] == `/` { end-- }
	return swift_array_bridge_file_url(unsafe { tos(path.str, end) }, true)
}

fn swift_array_bridge_url_delete(_metadata u64, _table u64, owner u64, output u64) {
	words := swift_array_bridge_url_delete_checked(owner) or { panic(err) }
	unsafe { *(&SwiftURLWords(output)) = words }
}

fn swift_array_unbridge_emit(code u64, data u64) {
	// Private URL implementation table: append/delete/owned NSURL bridge.
	write32(code + 3712, 0xaa1403e0); write32(code + 3716, 0x58000070); write32(code + 3720, 0xd61f0200)
	unsafe { *(&u64(code + 3728)) = u64(voidptr(swift_array_bridge_url_object)) }
	for offset, target in [u64(unsafe { voidptr(swift_array_bridge_url_append) }), u64(unsafe { voidptr(swift_array_bridge_url_delete) })]! {
		entry := code + 3744 + u64(offset) * 32
		write32(entry, if offset == 0 { u32(0xaa1403e5) } else { u32(0xaa1403e2) })
		write32(entry + 4, if offset == 0 { u32(0xaa0803e6) } else { u32(0xaa0803e3) })
		write32(entry + 8, 0x58000050); write32(entry + 12, 0xd61f0200)
		unsafe { *(&u64(entry + 16)) = target }
	}
	unsafe {
		*(&u64(data + 3520 + 336)) = code + 3744
		*(&u64(data + 3520 + 368)) = code + 3776
		*(&u64(data + 3520 + 432)) = code + 3712
	}
}
