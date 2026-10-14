// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftNSObjectHashableFailure {}
fn (_ &SwiftNSObjectHashableFailure) msg() string { return 'iOS: NSObject witnesses require active registered Objective-C metadata and borrowed values' }
fn (_ &SwiftNSObjectHashableFailure) code() int { return 1 }
__global swift_nsobject_hashable_failure_value = SwiftNSObjectHashableFailure{}
fn swift_nsobject_hashable_failure() IError { return unsafe { &swift_nsobject_hashable_failure_value } }

fn swift_nsobject_class_locked(metadata u64) !u64 {
	// Establish identity before reading metadata. Native Swift class layouts,
	// metaclasses, unregistered classes and private heap records are excluded.
	for cls, wrapper in ios_runtime.swift_objc_metadata {
		if wrapper != metadata { continue }
		mut current := cls
		for _ in 0 .. 128 {
			info := ios_runtime.classes[current] or { return swift_nsobject_hashable_failure() }
			if info.meta || (info.dynamic && !info.registered) || read64(current + 32) & 2 != 0 { return swift_nsobject_hashable_failure() }
			if current == ios_runtime.names['NSObject'] { return cls }
			current = info.parent
			if current == 0 { break }
		}
		return swift_nsobject_hashable_failure()
	}
	return swift_nsobject_hashable_failure()
}
fn swift_nsobject_active_locked() ! {
	if ios_runtime.swift_nsobject_hashable_retired { return swift_nsobject_hashable_failure() }
}
fn swift_nsobject_owner_locked(owner u64, cls u64) ! {
	if owner == 0 { return } // Native nil messaging reads no object storage.
	mut current := u64(0)
	if header := ios_runtime.objects[owner] {
		if header.releasing || header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs },0) <= 0 || read64(owner) != header.cls { return swift_nsobject_hashable_failure() }
		current = header.cls
	} else if owner in ios_runtime.constants { current = read64(owner) }
	else { return swift_nsobject_hashable_failure() }
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return swift_nsobject_hashable_failure() }
		if info.meta || (info.dynamic && !info.registered) || read64(current + 32) & 2 != 0 { return swift_nsobject_hashable_failure() }
		if current == cls { return }
		current = info.parent
		if current == 0 { break }
	}
	return swift_nsobject_hashable_failure()
}

fn swift_nsobject_arena_checked() !u64 {
	$if !arm64 { return swift_nsobject_hashable_failure() }
	if ios_runtime == unsafe { nil } { return swift_nsobject_hashable_failure() }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	swift_nsobject_active_locked()!
	if ios_runtime.swift_nsobject_hashable_arena != 0 { return ios_runtime.swift_nsobject_hashable_arena }
	swift_integer_metadata()
	page := usize(C.getpagesize()); allocation := C.mmap(unsafe { nil },page * 3,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	if allocation == voidptr(-1) { return swift_nsobject_hashable_failure() }
	base := u64(allocation); data := base + u64(page); integer := ios_runtime.swift_integer_arena + u64(page)
	// Instance requirements carry an indirect borrowed reference in x20.
	for i, target in [u64(unsafe { voidptr(swift_nsobject_hash_value) }),u64(unsafe { voidptr(swift_nsobject_hash_into) }),u64(unsafe { voidptr(swift_nsobject_raw_hash) })]! {
		entry := base + u64(i * 32)
		write32(entry,if i == 0 {u32(0xaa1403e2)} else {u32(0xaa1403e3)})
		write32(entry + 4,0x58000070);write32(entry + 8,0xd61f0200);write32(entry + 12,0xd503201f)
		unsafe { *(&u64(entry + 16)) = target }
	}
	for i, target in [u64(unsafe { voidptr(swift_nsobject_hash_instantiate) }),u64(unsafe { voidptr(swift_nsobject_equal_instantiate) })]! {
		entry := base + 96 + u64(i * 32);write32(entry,0x58000050);write32(entry + 4,0xd61f0200)
		unsafe { *(&u64(entry + 8)) = target }
	}
	// Private non-resilient descriptors refer to the canonical core protocols.
	// Their generic patterns and separate RW caches follow the existing Array
	// witness profile; lookup specializes only registered ObjC wrappers.
	unsafe { *(&u64(data + 96)) = ios_runtime.names['NSObject'] }
	for i, protocol in [integer + 352,integer + 432]! {
		descriptor := data + u64(i * 32); pattern := data + if i == 0 {u64(128)} else {u64(176)}
		swift_protocol_relative(descriptor,protocol);swift_protocol_relative(descriptor + 4,data + 96)
		swift_protocol_relative(descriptor + 8,pattern);write32(descriptor + 12,0x20018)
		write32(descriptor + 16,if i == 0 {u32(0x10005)} else {u32(0x10002)})
		swift_protocol_relative(descriptor + 20,base + 96 + u64(i * 32))
		swift_protocol_relative(descriptor + 24,base + u64(page * 2) + u64(i * 128))
		unsafe { *(&u64(pattern)) = descriptor }
	}
	unsafe {
		*(&u64(data + 144)) = base;*(&u64(data + 152)) = base + 32;*(&u64(data + 160)) = base + 64
		*(&u64(data + 184)) = u64(voidptr(swift_nsobject_equal))
	}
	C.__builtin___clear_cache(allocation,voidptr(base + 144))
	if C.mprotect(allocation,page,C.PROT_READ | C.PROT_EXEC) != 0 || C.mprotect(voidptr(data),page,C.PROT_READ) != 0 {
		if C.munmap(allocation,page * 3) != 0 { panic('iOS: cannot retire unsealed NSObject witnesses') }
		return swift_nsobject_hashable_failure()
	}
	ios_runtime.swift_nsobject_hashable_arena = base
	return base
}
fn swift_nsobject_tables_locked(metadata u64) !u64 {
	swift_nsobject_active_locked()!
	swift_nsobject_class_locked(metadata)!
	if table := ios_runtime.swift_nsobject_hashable_tables[metadata] { return table }
	code := swift_nsobject_arena_checked()!;page := usize(C.getpagesize());data := code + u64(page)
	root := swift_objc_metadata_checked(ios_runtime.names['NSObject'])!
	// The native inherited Equatable requirement always uses NSObject's table,
	// even when the Hashable specialization itself belongs to a subclass.
	root_equal := if root == metadata {u64(0)} else {swift_nsobject_tables_locked(root)! + 64}
	allocation := C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	if allocation == voidptr(-1) { return swift_nsobject_hashable_failure() }
	base := u64(allocation)
	C.memcpy(allocation,voidptr(data + 128),40);C.memcpy(voidptr(base + 64),voidptr(data + 176),16)
	unsafe { *(&u64(base + 8)) = if root_equal == 0 {base + 64} else {root_equal} }
	if C.mprotect(allocation,page,C.PROT_READ) != 0 { C.munmap(allocation,page);return swift_nsobject_hashable_failure() }
	ios_runtime.swift_nsobject_hashable_tables[metadata] = base
	return base
}
fn swift_nsobject_table_checked(metadata u64, equal bool) !u64 {
	if ios_runtime == unsafe { nil } { return swift_nsobject_hashable_failure() }
	C.ios_objc_initialize_lock();defer { C.ios_objc_initialize_unlock() }
	return swift_nsobject_tables_locked(metadata)! + if equal {u64(64)} else {u64(0)}
}
fn swift_nsobject_borrow_checked(metadata u64, table u64, left u64, right u64, equal bool) !SwiftStringWords {
	if ios_runtime == unsafe { nil } { return swift_nsobject_hashable_failure() }
	C.ios_objc_initialize_lock();defer { C.ios_objc_initialize_unlock() }
	swift_nsobject_active_locked()!
	cls := swift_nsobject_class_locked(metadata)!
	canonical := ios_runtime.swift_nsobject_hashable_tables[metadata] or { return swift_nsobject_hashable_failure() }
	// An inherited base Equatable table is valid with subclass metadata too.
	if table != canonical + if equal {u64(64)} else {u64(0)} {
		if !equal || table != read64(canonical + 8) { return swift_nsobject_hashable_failure() }
	}
	if !swift_dispatch_word_span(left) || (equal && !swift_dispatch_word_span(right)) { return swift_nsobject_hashable_failure() }
	owner := read64(left);other := if equal {read64(right)} else {u64(0)}
	swift_nsobject_owner_locked(owner,cls)!
	if equal { swift_nsobject_owner_locked(other,cls)! }
	return SwiftStringWords{first:owner,second:other}
}

fn swift_nsobject_message(owner u64, other u64, equal bool) u64 {
	if owner == 0 { return 0 }
	selector := if equal {c'isEqual:'} else {c'hash'}
	cls := read64(owner);objc_initialize(cls)
	imp := native_method(cls,if equal {'isEqual:'} else {'hash'})
	if imp != 0 {
		return if equal {u64(unsafe { SetEqualImp(voidptr(imp))(owner,objc_selector(selector),other) })} else {unsafe { SetHashImp(voidptr(imp))(owner,objc_selector(selector)) }}
	}
	// Existing built-in implementations are messages too (NSValue, NSDate,
	// NSSet...). Plain NSObject and older Foundation primitives use the same
	// equality/hash helpers as the existing Foundation collection backend.
	mut frame := unsafe { &RegisterFrame(C.__builtin_alloca(sizeof(RegisterFrame))) }
	unsafe { *frame = RegisterFrame{} };frame.x[0] = owner;frame.x[1] = objc_selector(selector);frame.x[2] = other
	if framework_dispatch(owner,if equal {'isEqual:'} else {'hash'},mut frame) { return frame.x[0] }
	return if equal {u64(cf_equal_depth(owner,other,0))} else {cf_hash(owner)}
}
fn swift_nsobject_hash_checked(metadata u64, table u64, receiver u64) !u64 {
	value := swift_nsobject_borrow_checked(metadata,table,receiver,0,false)!
	return swift_nsobject_message(value.first,0,false) // No registry lock crosses a message.
}
fn swift_nsobject_hash_value(metadata u64, table u64, receiver u64) i64 { return i64(swift_nsobject_hash_checked(metadata,table,receiver) or {panic(err)}) }
fn swift_nsobject_hash_into_checked(state u64, metadata u64, table u64, receiver u64) ! {
	if !swift_dispatch_word_span(state) || state > ~u64(0) - 71 { return swift_nsobject_hashable_failure() }
	value := swift_nsobject_hash_checked(metadata,table,receiver)!
	swift_hasher_word(mut unsafe { &SwiftHasher(state) },value)
}
fn swift_nsobject_hash_into(state u64, metadata u64, table u64, receiver u64) { swift_nsobject_hash_into_checked(state,metadata,table,receiver) or {panic(err)} }
fn swift_nsobject_raw_hash(seed i64, metadata u64, table u64, receiver u64) i64 {
	value := swift_nsobject_hash_checked(metadata,table,receiver) or {panic(err)}
	return swift_hasher_hash_word(seed,value)
}
fn swift_nsobject_equal_checked(left u64, right u64, metadata u64, table u64) !bool {
	value := swift_nsobject_borrow_checked(metadata,table,left,right,true)!
	return swift_nsobject_message(value.first,value.second,true) & 1 != 0
}
fn swift_nsobject_equal(left u64, right u64, metadata u64, table u64) bool { return swift_nsobject_equal_checked(left,right,metadata,table) or {panic(err)} }
fn swift_nsobject_instantiate_checked(table u64, metadata u64, equal bool) ! {
	canonical := swift_nsobject_table_checked(metadata,equal)!
	length := if equal {u64(16)} else {u64(40)}
	if !swift_dispatch_word_span(table) || table > ~u64(0) - (length - 1) { return swift_nsobject_hashable_failure() }
	C.memcpy(voidptr(table),voidptr(canonical),usize(length))
}
fn swift_nsobject_hash_instantiate(table u64, metadata u64, _arguments u64) { swift_nsobject_instantiate_checked(table,metadata,false) or {panic(err)} }
fn swift_nsobject_equal_instantiate(table u64, metadata u64, _arguments u64) { swift_nsobject_instantiate_checked(table,metadata,true) or {panic(err)} }
fn swift_nsobject_hashable_symbol(symbol string) ?u64 {
	offset := match symbol { '_$sSo8NSObjectCSH10ObjectiveCMc' {u64(0)} '_$sSo8NSObjectCSQ10ObjectiveCMc' {u64(32)} else {return none} }
	return (swift_nsobject_arena_checked() or {return none}) + u64(C.getpagesize()) + offset
}
fn swift_nsobject_hashable_stop() {
	ios_runtime.swift_nsobject_hashable_retired = true;page := usize(C.getpagesize())
	for _, base in ios_runtime.swift_nsobject_hashable_tables { if C.munmap(voidptr(base),page) != 0 {panic('iOS: cannot retire NSObject witness specialization')} }
	unsafe { ios_runtime.swift_nsobject_hashable_tables.free() }
	if ios_runtime.swift_nsobject_hashable_arena != 0 {
		if C.munmap(voidptr(ios_runtime.swift_nsobject_hashable_arena),page * 3) != 0 {panic('iOS: cannot retire NSObject witnesses')}
		ios_runtime.swift_nsobject_hashable_arena = 0
	}
}
