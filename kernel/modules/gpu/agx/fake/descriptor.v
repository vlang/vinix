// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fake

// Pure software staging for the recovered G17 3D descriptor. The constants
// are the scalar defaults independently recovered from
// AGXTACommandDescriptor::MetaClass; resource-derived fields are deliberately
// left zero until their Mesa-to-G17 semantic mapping is proven.

pub const g17_command_bytes = u64(0x2240)
pub const g17_descriptor_bytes = u64(0x15b0)

fn write_descriptor_value(destination &u8, offset u64, bytes u64, value u64) {
	unsafe {
		C.memcpy(voidptr(destination + offset), &value, bytes)
	}
}

pub fn initialize_render_descriptor(descriptor voidptr, descriptor_bytes u64) bool {
	if descriptor == unsafe { nil } || descriptor_bytes < g17_descriptor_bytes {
		return false
	}
	unsafe {
		C.memset(descriptor, 0, g17_descriptor_bytes)
		destination := &u8(descriptor)
		write_descriptor_value(destination, 0x144, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0x1c1, 2, 0x101)
		write_descriptor_value(destination, 0x2d4, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0x400, 4, 1)
		write_descriptor_value(destination, 0x410, 4, 2)
		write_descriptor_value(destination, 0x900, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0x968, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0xaa0, 8, 0xffff_ffff)
		write_descriptor_value(destination, 0xb60, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0xc30, 4, 1)
		write_descriptor_value(destination, 0xe18, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0xf60, 4, 2)
		write_descriptor_value(destination, 0x1208, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0x1264, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0x126c, 4, 0xffff_ffff)
		write_descriptor_value(destination, 0x13a8, 8, 0xffff_ffff)
		write_descriptor_value(destination, 0x13e8, 4, 0xffff_ffff)
	}
	return true
}
