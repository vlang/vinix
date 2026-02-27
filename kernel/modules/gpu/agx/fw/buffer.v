module fw

// Buffer/memory firmware structures
// Tiled vertex buffer (TVB), parameter buffer, and scene descriptors
// Translates fw/buffer.rs from the Asahi Linux GPU driver

// Tiled Vertex Buffer (TVB) configuration
@[packed]
pub struct FwTvbConfig {
pub mut:
	tag         u32
	unk_4       u32
	slot        u32
	unk_c       u32
	unk_10      u64
	unk_18      u64
	unk_20      u64
	unk_28      u64
	block_count u32
	block_size  u32
	unk_38      u64
}

// Parameter buffer info (shared between vertex and fragment)
@[packed]
pub struct FwParamBuffer {
pub mut:
	gpu_addr    u64
	gpu_size    u64
	block_count u32
	pad         u32
	unk_18      u64
}

// Scene descriptor
@[packed]
pub struct FwScene {
pub mut:
	tag        u32
	unk_4      u32
	params_addr u64
	unk_10     u64
	tvb_addr   u64
	unk_20     u64
	unk_28     u64
	width      u32
	height     u32
	unk_38     u32
	unk_3c     u32
	tile_count u32
	pad_44     u32
	unk_48     u64
	unk_50     u64
}
