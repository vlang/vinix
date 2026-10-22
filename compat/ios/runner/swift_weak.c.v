// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native Swift WeakReference has the same pointer-sized storage and lifetime
// tracking as unknown-object weak references, but accepts only native objects.
// Validate both old and new referents before touching a cell or reading headers.
fn swift_weak_initialize(destination u64, object u64) u64 {
	return swift_weak_update_checked(destination, 0, object, .initialize, true) or { panic(err) }
}
fn swift_weak_assign(destination u64, object u64) u64 {
	return swift_weak_update_checked(destination, 0, object, .assign, true) or { panic(err) }
}
fn swift_weak_copy_initialize(destination u64, source u64) u64 {
	return swift_weak_update_checked(destination, source, 0, .copy_initialize, true) or { panic(err) }
}
fn swift_weak_take_initialize(destination u64, source u64) u64 {
	return swift_weak_update_checked(destination, source, 0, .take_initialize, true) or { panic(err) }
}
fn swift_weak_copy_assign(destination u64, source u64) u64 {
	return swift_weak_update_checked(destination, source, 0, .copy_assign, true) or { panic(err) }
}
fn swift_weak_take_assign(destination u64, source u64) u64 {
	return swift_weak_update_checked(destination, source, 0, .take_assign, true) or { panic(err) }
}
fn swift_weak_load(location u64) u64 {
	return swift_weak_load_checked(location, false, true) or { panic(err) }
}
fn swift_weak_take(location u64) u64 {
	return swift_weak_load_checked(location, true, true) or { panic(err) }
}
fn swift_weak_destroy(location u64) {
	swift_weak_destroy_checked(location, true) or { panic(err) }
}
