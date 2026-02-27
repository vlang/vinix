module fw

// Firmware vertex command structures
// These packed structs must match the firmware binary layout exactly.
// The FwVertexCmd is submitted to the GPU via the vertex pipe channel
// and tells the firmware how to execute the vertex/tiling stage of a
// render pass. Byte-accurate layout for firmware version 12.3.0.

// Firmware vertex command descriptor
@[packed]
pub struct FwVertexCmd {
pub mut:
	header         FwCmdHeader // tag, cmd_type=0, flags
	unk_10         u64
	scene_addr     u64 // GPU pointer to scene descriptor
	buf_addr       u64 // vertex buffer GPU address
	buf_size       u64
	unk_30         u64
	unk_38         u64
	tvb_addr       u64 // TVB base address
	unk_48         u64
	unk_50         u64
	unk_58         u64
	unk_60         u32
	vertex_count   u32
	instance_count u32
	unk_6c         u32
	stamp_addr     u64 // completion stamp address
	stamp_value    u32
	stamp_slot     u32
	unk_80         u64
	unk_88         u64
	unk_90         u64
	result_addr    u64
	result_size    u32
	pad_a4         u32
}
