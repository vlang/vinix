// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native URL path operations borrow Self and arguments, dispatch with formal
// implementation metadata, and return an owned two-word URL through x8. A nil
// witness result means retain and return the original implementation/table.
// These entries do not construct URL implementations or parse path strings.
fn swift_url_path_emit(address u64, deleting bool) {
	if deleting {
		for i, op in [u32(0xd10103ff), u32(0xa90157f6), u32(0xa9024ff4), u32(0xa9037bfd),
			u32(0x9100c3fd), u32(0xaa0803f3), u32(0xa9405696), u32(0xaa1603e0), u32(0x58000690),
			u32(0xd63f0200), u32(0x9105c2a9), u32(0xf940baaa), u32(0x910003e8), u32(0xaa1603f4),
			u32(0xaa1503e1), u32(0xd63f0140), u32(0xf94003e8), u32(0xb4000068), u32(0xf94007f5),
			u32(0x14000005), u32(0xaa1603e0), u32(0x58000530), u32(0xd63f0200), u32(0xaa1603e8),
			u32(0xa9005668), u32(0xa9437bfd), u32(0xa9424ff4), u32(0xa94157f6), u32(0x910103ff),
			u32(0xd65f03c0)]! {
			write32(address + u64(i * 4), op)
		}
	} else {
		for i, op in [u32(0xd10183ff), u32(0xa90167fa), u32(0xa9025ff8), u32(0xa90357f6),
			u32(0xa9044ff4), u32(0xa9057bfd), u32(0x910143fd), u32(0xaa0203f7), u32(0xaa0103f8),
			u32(0xaa0003f9), u32(0xaa0803f3), u32(0xa9405696), u32(0xaa1603e0), u32(0x580005f0),
			u32(0xd63f0200), u32(0xaa0003e3), u32(0x910542a9), u32(0xf940aaaa), u32(0x910003e8),
			u32(0xaa1903e0), u32(0xaa1803e1), u32(0xaa1703e2), u32(0xaa1603f4), u32(0xaa1503e4),
			u32(0xd63f0140), u32(0xf94003e8), u32(0xb4000068), u32(0xf94007f5), u32(0x14000005),
			u32(0xaa1603e0), u32(0x58000410), u32(0xd63f0200), u32(0xaa1603e8), u32(0xa9005668),
			u32(0xa9457bfd), u32(0xa9444ff4), u32(0xa94357f6), u32(0xa9425ff8), u32(0xa94167fa),
			u32(0x910183ff), u32(0xd65f03c0)]! {
			write32(address + u64(i * 4), op)
		}
	}
	unsafe {
		*(&u64(address + 240)) = u64(voidptr(swift_object_type))
		*(&u64(address + 248)) = u64(voidptr(swift_unknown_retain))
	}
}
