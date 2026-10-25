// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Builtin.NativeObject uses native Swift ARC even when its metadata describes
// a class. Publish assignments before releasing the old owner, since the
// deallocating destructor may inspect or copy the replacement.
fn swift_native_value_copy(destination u64, source u64, _metadata u64) u64 {
	owner := swift_retain(read64(source))
	unsafe { *(&u64(voidptr(destination))) = owner }
	return destination
}

fn swift_native_value_destroy(value u64, _metadata u64) {
	swift_release(read64(value))
}

fn swift_native_value_assign_copy(destination u64, source u64, _metadata u64) u64 {
	previous := read64(destination)
	owner := swift_retain(read64(source))
	unsafe { *(&u64(voidptr(destination))) = owner }
	swift_release(previous)
	return destination
}

fn swift_native_value_assign_take(destination u64, source u64, _metadata u64) u64 {
	previous := read64(destination)
	unsafe { *(&u64(voidptr(destination))) = read64(source) }
	swift_release(previous)
	return destination
}

// The native, unknown and bridge reference tables share their measured enum
// encoding and quiescent lifetime, but have distinct ownership operations.
fn swift_native_value_publish(table u64) {
	for i, target in [u64(unsafe { voidptr(swift_native_value_copy) }),
		u64(unsafe { voidptr(swift_native_value_destroy) }),
		u64(unsafe { voidptr(swift_native_value_copy) }),
		u64(unsafe { voidptr(swift_native_value_assign_copy) }),
		u64(unsafe { voidptr(swift_unknown_value_take) }),
		u64(unsafe { voidptr(swift_native_value_assign_take) }),
		u64(unsafe { voidptr(swift_unknown_value_enum_get) }),
		u64(unsafe { voidptr(swift_unknown_value_enum_store) })]! {
		unsafe { *(&u64(voidptr(table + u64(i * 8)))) = target }
	}
	unsafe {
		*(&u64(voidptr(table + 64))) = 8
		*(&u64(voidptr(table + 72))) = 8
	}
	write32(table + 80, 0x10007)
	write32(table + 84, 0x7fffffff)
}

fn swift_native_value_witnesses() u64 {
	return swift_unknown_value_witnesses() + 256
}
