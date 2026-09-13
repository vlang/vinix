module fw

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
		&& sizeof(G13BufferScene) == 0x40 && sizeof(G13InitBufferCommand) == 0x20
}
