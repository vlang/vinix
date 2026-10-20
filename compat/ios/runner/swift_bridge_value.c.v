// SPDX-License-Identifier: GPL-2.0-or-later
module main

// BridgeObject preserves the encoded word while ARC follows its bridge bits.
// Assignment publishes the replacement before releasing the previous owner,
// so a reentrant destructor observes the new value. Takes leave moved bytes
// unchanged, as the native witnesses do.
fn swift_bridge_value_copy(destination u64, source u64, _metadata u64) u64 {
	owner := swift_bridge_retain(read64(source))
	unsafe { *(&u64(voidptr(destination))) = owner }
	return destination
}

fn swift_bridge_value_destroy(value u64, _metadata u64) {
	swift_bridge_release(read64(value))
}

fn swift_bridge_value_assign_copy(destination u64, source u64, _metadata u64) u64 {
	previous := read64(destination)
	owner := swift_bridge_retain(read64(source))
	unsafe { *(&u64(voidptr(destination))) = owner }
	swift_bridge_release(previous)
	return destination
}

fn swift_bridge_value_assign_take(destination u64, source u64, _metadata u64) u64 {
	previous := read64(destination)
	unsafe { *(&u64(voidptr(destination))) = read64(source) }
	swift_bridge_release(previous)
	return destination
}

// Both reference tables share the same size, flags, extra inhabitants and
// quiescent lifetime. Populate this distinct table before sealing their page;
// ownership entries differ, while take and enum operations are shared.
fn swift_bridge_value_publish(table u64) {
	for i, target in [u64(unsafe { voidptr(swift_bridge_value_copy) }),
		u64(unsafe { voidptr(swift_bridge_value_destroy) }),
		u64(unsafe { voidptr(swift_bridge_value_copy) }),
		u64(unsafe { voidptr(swift_bridge_value_assign_copy) }),
		u64(unsafe { voidptr(swift_unknown_value_take) }),
		u64(unsafe { voidptr(swift_bridge_value_assign_take) }),
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

fn swift_bridge_value_witnesses() u64 {
	return swift_unknown_value_witnesses() + 128
}
