// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftObjectAnyFailure {}

fn (_ &SwiftObjectAnyFailure) msg() string {
	return 'iOS: AnyObject-to-Any bridging requires an active runtime, aligned result storage and a live registered class instance'
}

fn (_ &SwiftObjectAnyFailure) code() int { return 1 }

__global swift_object_any_failure_value = SwiftObjectAnyFailure{}

fn swift_object_any_failure() IError { return unsafe { &swift_object_any_failure_value } }

// Swift's input is borrowed, with the uninitialized 32-byte Any result in x8.
// Only its first word and metadata word are written; the buffer's padding is
// untouched. Nil is an Any containing Optional<AnyObject>.none, not a nil Any.
fn swift_object_any_checked(destination u64, owner u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_object_any_retired || destination == 0 || destination & 7 != 0
		|| destination > ~u64(0) - 32 {
		return swift_object_any_failure()
	}
	mut metadata := u64(0)
	if owner == 0 {
		base := swift_object_any_arena_checked()!
		metadata = swift_optional_access_checked(0, base + u64(C.getpagesize()) + 16)!.metadata
	} else {
		// Reject private storage, contexts, tagged and stale pointers without
		// reading unknown memory or attempting to acquire a dying object.
		if owner & 0x8000000000000007 != 0 { return swift_object_any_failure() }
		C.ios_objc_initialize_lock()
		mut live := false
		if header := ios_runtime.objects[owner] {
			live = !header.releasing && !header.destroying && !header.destroyed
				&& C.ios_ref_change(unsafe { &header.refs }, 0) > 0 && read64(owner) == header.cls
		} else if storage := ios_runtime.swift_heap[owner] {
			live = !storage.deiniting && read64(owner) == storage.metadata
		} else {
			live = owner in ios_runtime.constants || swift_main_actor_is_singleton_locked(owner)
				|| swift_main_executor_is_singleton_locked(owner)
		}
		C.ios_objc_initialize_unlock()
		if !live { return swift_object_any_failure() }
		// Formal-class lookup can call application code. The caller keeps the
		// borrowed owner alive; no registry lock spans that callback.
		metadata = swift_object_type_checked(owner) or { return swift_object_any_failure() }
		layout := swift_sequence_value_checked(metadata) or { return swift_object_any_failure() }
		if layout.size != 8 || layout.alignment != 8 || read32(read64(metadata - 8) + 80) & 0x30000 != 0x10000 {
			return swift_object_any_failure()
		}
		swift_unknown_retain(owner)
	}
	unsafe {
		*(&u64(destination + 24)) = metadata
		*(&u64(destination)) = owner
	}
}

fn swift_object_any(destination u64, owner u64) {
	swift_object_any_checked(destination, owner) or { panic(err) }
}

fn swift_object_any_arena_checked() !u64 {
	$if !arm64 {
		return swift_object_any_failure()
	}
	if ios_runtime == unsafe { nil } { return swift_object_any_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_object_any_retired || ios_runtime.swift_concurrency_retired {
		return swift_object_any_failure()
	}
	if ios_runtime.swift_object_any_arena != 0 { return ios_runtime.swift_object_any_arena }
	witness := swift_unknown_value_witnesses()
	page := u64(C.getpagesize())
	arena := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if arena == voidptr(-1) { return swift_object_any_failure() }
	base := u64(arena)
	data := base + page
	write32(base, 0xaa0003e1) // mov x1,x0 (borrowed owner)
	write32(base + 4, 0xaa0803e0) // mov x0,x8 (indirect Any result)
	write32(base + 8, 0x58000050)
	write32(base + 12, 0xd61f0200)
	unsafe {
		*(&u64(base + 16)) = u64(voidptr(swift_object_any))
		*(&u64(data + 8)) = witness
		*(&u64(data + 16)) = 0x303 // Class-constrained existential, zero protocols.
		// Flags/protocol count at +8 are zero; no superclass/protocol tail.
	}
	C.__builtin___clear_cache(arena, voidptr(base + 24))
	if C.mprotect(arena, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data), usize(page), C.PROT_READ) != 0 {
		if C.munmap(arena, usize(page * 2)) != 0 {
			panic('iOS: cannot retire unsealed AnyObject bridge')
		}
		return swift_object_any_failure()
	}
	ios_runtime.swift_object_any_arena = base
	return base
}

fn swift_object_any_symbol(symbol string) ?u64 {
	if symbol != '_$ss018_bridgeAnyObjectToB0yypyXlSgF' { return none }
	return swift_object_any_arena_checked() or { return none }
}

fn swift_object_any_stop() {
	// All values/workers have drained and Optional metadata has retired first.
	ios_runtime.swift_object_any_retired = true
	if ios_runtime.swift_object_any_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_object_any_arena), usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire AnyObject bridge')
	}
	ios_runtime.swift_object_any_arena = 0
}
