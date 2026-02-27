module fw

// Firmware fragment command structures
// These packed structs must match the firmware binary layout exactly.
// The FwFragmentCmd is submitted to the GPU via the fragment pipe channel
// and tells the firmware how to execute the fragment/pixel shading stage
// of a render pass. Byte-accurate layout for firmware version 12.3.0.

// Firmware fragment command descriptor
@[packed]
pub struct FwFragmentCmd {
pub mut:
	header       FwCmdHeader
	unk_10       u64
	scene_addr   u64
	buf_addr     u64
	buf_size     u64
	unk_30       u64
	unk_38       u64
	unk_40       u64
	width        u32
	height       u32
	tile_width   u32
	tile_height  u32
	unk_58       u64
	unk_60       u64
	stamp_addr   u64
	stamp_value  u32
	stamp_slot   u32
	unk_78       u64
	unk_80       u64
	unk_88       u64
	result_addr  u64
	result_size  u32
	pad_9c       u32
	unk_a0       u64
	layers       u32
	samples      u32
}
