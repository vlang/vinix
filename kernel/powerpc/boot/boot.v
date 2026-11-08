// SPDX-License-Identifier: GPL-2.0-or-later
module boot

pub const magic = u32(0x564f4631)
pub const version = u32(4)

pub struct MemoryRange {
pub mut:
	base u32
	size u32
}

// Firmware is still active at this handoff. Addresses refer to the inherited
// firmware mapping; the loader currently requires identity-mapped claims.
// The kernel must establish its own mappings before ending firmware use.
pub struct Info {
pub mut:
	magic           u32
	version         u32
	bytes           u32
	tree            u32
	tree_size       u32
	available_count u32
	available       [64]MemoryRange
	framebuffer     u32
	width           u32
	height          u32
	pitch           u32
	depth           u32
	kernel          MemoryRange
	stack           MemoryRange
	serial_control  u32
	serial_data     u32
	timebase_hz     u32
	initramfs       MemoryRange
}
