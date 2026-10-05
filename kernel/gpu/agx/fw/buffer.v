module fw

import gpu.agx.hw

// Byte-exact G13/macOS 12.3 tiled-vertex-buffer control structures. The
// firmware ABI uses four-byte aggregate alignment, so every GPU pointer is an
// explicitly packed u64 and may be unaligned.

pub const g13_tvb_page_shift = u32(15)
pub const g13_tvb_page_size = u64(1) << g13_tvb_page_shift
pub const g13_tvb_pages_per_block = u32(4)
pub const g13_tvb_block_size = g13_tvb_page_size * g13_tvb_pages_per_block
pub const g13_tvb_slot_count = u32(127)

@[packed]
pub struct G13BufferBlockControl {
pub mut:
	total u32
	wptr  u32
	unk   u32
	pad   [0x34]u8
}

@[packed]
pub struct G13BufferCounter {
pub mut:
	count u32
	pad   [0x3c]u8
}

@[packed]
pub struct G13BufferStats {
pub mut:
	max_pages      u32
	max_b          u32
	overflow_count u32
	gpu_c          u32
	pad_10         [0x10]u8
	reset          u32
	pad_24         [0x1c]u8
}

@[packed]
pub struct G13BufferInfo {
pub mut:
	gpu_counter         u32
	unk_4               u32
	last_id             i32
	cur_id              i32
	unk_10              u32
	gpu_counter_2       u32
	unk_18              u32
	unk_1c              u32
	page_list           u64
	page_list_size      u32
	page_count          u32
	max_blocks          u32
	block_count         u32
	unk_38              u32
	block_list          u64
	block_control       u64
	last_page           u32
	gpu_page_ptr_1      u32
	gpu_page_ptr_2      u32
	unk_58              u32
	block_size          u32
	unk_60              u64
	counter             u64
	unk_70              u32
	unk_74              u32
	unk_78              u32
	unk_7c              u32
	unk_80              u32
	max_pages           u32
	max_pages_nomemless u32
	unk_8c              u32
	pad_90              [0x30]u8
}

@[packed]
struct G13BufferInfoV135 {
mut:
	gpu_counter         u32
	unk_4               u32
	last_id             i32
	cur_id              i32
	unk_10              u32
	gpu_counter_2       u32
	unk_18              u32
	page_list           u64
	page_list_size      u32
	page_count          u32
	max_blocks          u32
	block_count         u32
	unk_38              u32
	block_list          u64
	block_control       u64
	last_page           u32
	gpu_page_ptr_1      u32
	gpu_page_ptr_2      u32
	unk_58              u32
	block_size          u32
	unk_60              u64
	counter             u64
	unk_70              u32
	unk_74              u32
	unk_78              u32
	unk_7c              u32
	unk_80              u32
	max_pages           u32
	max_pages_nomemless u32
	unk_8c              u32
	pad_90              [0x30]u8
}

pub fn g13_buffer_info_active_size(abi hw.FirmwareAbi) ?u64 {
	return match abi {
		.v12_3 { u64(sizeof(G13BufferInfo)) }
		.v13_5_partial { u64(sizeof(G13BufferInfoV135)) }
		else { none }
	}
}

pub fn initialize_g13_buffer_info(data voidptr, size u64, abi hw.FirmwareAbi,
	page_list u64, page_list_size u32, max_blocks u32, block_list u64,
	block_control u64, block_size u32, counter u64, max_pages u32,
	max_pages_nomemless u32) bool {
	required := g13_buffer_info_active_size(abi) or { return false }
	if data == unsafe { nil } || size < required || page_list == 0 || block_list == 0
		|| block_control == 0 || counter == 0 {
		return false
	}
	unsafe {
		if abi == .v13_5_partial {
			mut info := &G13BufferInfoV135(data)
			info.cur_id = -1
			info.page_list = page_list
			info.page_list_size = page_list_size
			info.max_blocks = max_blocks
			info.block_list = block_list
			info.block_control = block_control
			info.block_size = block_size
			info.counter = counter
			info.unk_80 = 1
			info.max_pages = max_pages
			info.max_pages_nomemless = max_pages_nomemless
		} else {
			mut info := &G13BufferInfo(data)
			info.cur_id = -1
			info.page_list = page_list
			info.page_list_size = page_list_size
			info.max_blocks = max_blocks
			info.block_list = block_list
			info.block_control = block_control
			info.block_size = block_size
			info.counter = counter
			info.unk_80 = 1
			info.max_pages = max_pages
			info.max_pages_nomemless = max_pages_nomemless
		}
	}
	return true
}

pub fn update_g13_buffer_info_counts(data voidptr, abi hw.FirmwareAbi,
	page_count u32, block_count u32, last_page u32) bool {
	if data == unsafe { nil } {
		return false
	}
	unsafe {
		if abi == .v13_5_partial {
			mut info := &G13BufferInfoV135(data)
			info.page_count = page_count
			info.block_count = block_count
			info.last_page = last_page
		} else if abi == .v12_3 {
			mut info := &G13BufferInfo(data)
			info.page_count = page_count
			info.block_count = block_count
			info.last_page = last_page
		} else {
			return false
		}
	}
	return true
}

@[packed]
pub struct G13BufferScene {
pub mut:
	pass_page_count  u32
	unk_4            u32
	unk_8            u64
	unk_10           u64
	user_buffer      u64
	unk_20           u32
	stats            u64
	total_page_count u32
	unk_30           u64
	unk_38           u64
}

@[packed]
struct G13BufferSceneV135 {
mut:
	bytes [0x48]u8
}

pub fn g13_buffer_scene_active_size(abi hw.FirmwareAbi) ?u64 {
	return match abi {
		.v12_3 { u64(sizeof(G13BufferScene)) }
		.v13_5_partial { u64(sizeof(G13BufferSceneV135)) }
		else { none }
	}
}

pub fn initialize_g13_buffer_scene(data voidptr, size u64, abi hw.FirmwareAbi,
	user_buffer u64, stats u64) bool {
	required := g13_buffer_scene_active_size(abi) or { return false }
	if data == unsafe { nil } || size < required || user_buffer == 0 || stats == 0 {
		return false
	}
	legacy := G13BufferScene{
		user_buffer: user_buffer
		stats: stats
	}
	unsafe {
		if abi == .v13_5_partial {
			// Ventura inserts unk_28 before bm_misc_addr. The new word is zero.
			C.memcpy(data, &legacy, 0x24)
			C.memcpy(voidptr(u64(data) + 0x2c), voidptr(u64(&legacy) + 0x24), 0x1c)
		} else {
			C.memcpy(data, &legacy, sizeof(G13BufferScene))
		}
	}
	return true
}

@[packed]
pub struct G13InitBufferCommand {
pub mut:
	tag         u32
	vm_slot     u32
	buffer_slot u32
	unk_c       u32
	block_count u32
	buffer      u64
	stamp_value u32
}

pub fn validate_g13_buffer_layouts() bool {
	return sizeof(G13BufferBlockControl) == 0x40 && sizeof(G13BufferCounter) == 0x40
		&& sizeof(G13BufferStats) == 0x40 && sizeof(G13BufferInfo) == 0xc0
		&& sizeof(G13BufferInfoV135) == 0xbc
		&& sizeof(G13BufferScene) == 0x40 && sizeof(G13BufferSceneV135) == 0x48
		&& sizeof(G13InitBufferCommand) == 0x20
}
