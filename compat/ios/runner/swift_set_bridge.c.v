// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftSetBridgeSnapshot {
	items u64
	count u64
}

// Borrow a registered NSSet and copy its members under the registry lock.
// Retain every member before finishing the source read. No guest hash/equality
// callback runs while the registry lock protects validation and capture.
fn swift_set_bridge_snapshot(source u64, element u64, hashable u64) !SwiftSetBridgeSnapshot {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	cls := swift_nsobject_class_locked(element)!
	if hashable != swift_nsobject_tables_locked(element)! {
		return error('iOS: Set bridge requires canonical NSObject Hashable witnesses')
	}
	header := ios_runtime.objects[source] or { return error('iOS: Set bridge requires a registered NSSet') }
	if header.releasing || header.destroying || header.destroyed || !header.set_owned
		|| !header.set_initialized || header.cf_raw_values || header.items.len > 4096
		|| !objc_is_kind(source,ios_runtime.names['NSSet']) {
		return error('iOS: Set bridge requires initialized object NSSet storage')
	}
	// Validate all identities/types before retaining or inspecting a foreign
	// member. Scalar/value bridging requires a separate element conversion.
	for item in header.items {
		if item == 0 { return error('iOS: Set bridge contains a nil member') }
		swift_nsobject_owner_locked(item,cls)!
	}
	count := u64(header.items.len)
	if count == 0 { return SwiftSetBridgeSnapshot{} }
	items := u64(C.malloc(usize(count * 8)))
	if items == 0 { return error('iOS: cannot allocate Set bridge snapshot') }
	for i,item in header.items {
		unsafe { *(&u64(items + u64(i * 8))) = objc_retain(item) }
	}
	return SwiftSetBridgeSnapshot{items:items,count:count}
}
fn swift_set_bridge_snapshot_release(snapshot SwiftSetBridgeSnapshot) {
	for i in u64(0) .. snapshot.count { objc_release(read64(snapshot.items + i * 8)) }
	if snapshot.items != 0 { C.free(voidptr(snapshot.items)) }
}

// Native ARM64 uses ordinary arguments x0/x1/x2 and an owned Set word in
// x0. Self x20 is unused. Vinix materializes its existing native Set layout
// instead of exporting a Cocoa tagged pointer that its Sequence cannot read.
fn swift_foundation_set_unbridge_checked(source u64, element u64, hashable u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Set bridge outside runtime lifetime')
	}
	// The native nil fast path reads neither generic argument, including a
	// protected/unused metadata address. No conformance/type query is needed.
	if source == 0 { return swift_set_arena() + u64(C.getpagesize()) + 1024 }
	snapshot := swift_set_bridge_snapshot(source,element,hashable)!
	defer { swift_set_bridge_snapshot_release(snapshot) }
	metadata := swift_set_access(0,element,hashable).metadata
	owner := swift_set_minimum_capacity(i64(snapshot.count),element,hashable)
	mut published := false
	defer { if !published { swift_bridge_release(owner) } }
	view := swift_set_owner_view_checked(metadata - 8,owner,false)!
	if snapshot.count != 0 {
		value := swift_sequence_value_checked(element)!
		copy_value := unsafe { SwiftSequenceCopy(voidptr(value.copy)) }
		equatable := read64(hashable + 8)
		equals := unsafe { SwiftSetEqual(voidptr(read64(equatable + 8))) }
		hash_value := unsafe { SwiftSetHash(voidptr(ios_runtime.swift_set_arena + 896)) }
		for i in u64(0) .. snapshot.count {
			member := snapshot.items + i * 8
			mut bucket := hash_value(read64(hashable + 32),read64(owner + 40),element,hashable,member) & (view.buckets - 1)
			mut found := false
			for _ in u64(0) .. view.buckets {
				bitmap := view.words + bucket / 64 * 8
				bit := u64(1) << (bucket & 63)
				if read64(bitmap) & bit == 0 {
					copy_value(view.bytes + bucket * view.stride,member,element)
					unsafe { *(&u64(bitmap)) |= bit; *(&u64(owner + 16)) += 1 }
					found = true
					break
				}
				if equals(view.bytes + bucket * view.stride,member,element,equatable) {
					found = true
					break
				}
				bucket = (bucket + 1) & (view.buckets - 1)
			}
			if !found { return error('iOS: Set bridge hash table has no empty bucket') }
		}
	}
	published = true
	return owner
}
fn swift_foundation_set_unbridge(source u64, element u64, hashable u64) u64 {
	return swift_foundation_set_unbridge_checked(source,element,hashable) or { panic(err) }
}
