module fw

import gpu.agx.hw

// G13/macOS 12.3 fragment carrier. Parameter-block extents and the versioned
// firmware pointers must follow the packaged Asahi declarations together.
// The first block includes eight legacy padding bytes; the third ends at
// depth_dimensions without another padding word. Host layout checks compare
// the constants with the actual carrier and the selected source-layout model.

pub const g13_fragment_job_params_1_offset = u64(0x78)
pub const g13_fragment_job_params_2_offset = u64(0x3c0)
pub const g13_fragment_job_params_3_offset = u64(0x4b0)
pub const g13_fragment_unk_758_flag_offset = u64(0x758)
pub const g13_fragment_busy_flag_offset = u64(0x870)
pub const g13_fragment_overflow_count_offset = u64(0x874)
pub const g13_fragment_unk_pointee_offset = u64(0x8b0)
pub const g13_fragment_unk_buf_0_offset = u64(0x8e4)
pub const g13_fragment_cur_ts_offset = u64(0x8fc)
pub const g13_fragment_start_ts_offset = u64(0x904)
pub const g13_fragment_end_ts_offset = u64(0x90c)
pub const g13_fragment_v12_3_size = u64(0x930)
pub const g13_fragment_v13_5_size = u64(0x96c)

@[packed]
pub struct G13ClearPipelineBinding {
pub mut:
	pipeline_bind u64
	address       u64
}

@[packed]
pub struct G13StorePipelineBinding {
pub mut:
	unk_0         u64
	unk_8         u32
	pipeline_bind u32
	unk_10        u32
	address       u32
	unk_18        u32
	padding       u32
}

@[packed]
pub struct G13ArrayAddress {
pub mut:
	pointer u64
	padding u64
}

@[packed]
pub struct G13AuxFramebufferInfo {
pub mut:
	iogpu_unk_214 u32
	unk_2         u32
	width         u32
	height        u32
}

@[packed]
pub struct G13FragmentJobParameters1 {
pub mut:
	utile_config                 u32
	unk_4                        u32
	clear_pipeline               G13ClearPipelineBinding
	ppp_multisamplectl           u64
	scissor_array                u64
	depth_bias_array             u64
	aux_fb_info                  G13AuxFramebufferInfo
	depth_dimensions             u64
	visibility_result_buffer     u64
	zls_control                  u64
	depth_buffer_ptr_1           u64
	depth_buffer_ptr_2           u64
	stencil_buffer_ptr_1         u64
	stencil_buffer_ptr_2         u64
	depth_buffer_stride_1        u64
	depth_buffer_stride_2        u64
	stencil_buffer_stride_1      u64
	stencil_buffer_stride_2      u64
	depth_meta_buffer_ptr_1      u64
	depth_meta_buffer_stride_1   u64
	depth_meta_buffer_ptr_2      u64
	depth_meta_buffer_stride_2   u64
	stencil_meta_buffer_ptr_1    u64
	stencil_meta_buffer_stride_1 u64
	stencil_meta_buffer_ptr_2    u64
	stencil_meta_buffer_stride_2 u64
	tvb_tilemap                  u64
	tvb_layermeta                u64
	mtile_stride_dwords          u64
	tvb_heapmeta                 u64
	tile_config                  u64
	aux_fb                       u64
	unk_108                      [6]u64
	pipeline_base                u64
	unk_140                      u64
	helper_program               u32
	unk_14c                      u32
	helper_arg                   u64
	unk_158                      u64
	unk_160                      u64
	padding                      [0x1e0]u8
}

@[packed]
pub struct G13FragmentJobParameters2 {
pub mut:
	store_pipeline_bind u32
	store_pipeline_addr u32
	unk_8               u32
	unk_c               u32
	merge_upper_x       u32
	merge_upper_y       u32
	unk_18              u64
	utiles_per_mtile_y  u16
	utiles_per_mtile_x  u16
	unk_24              u32
	tile_counts         u32
	tib_blocks          u32
	isp_bgobjdepth      u32
	isp_bgobjvals       u32
	unk_38              u32
	unk_3c              u32
	helper_cfg          u32
	padding             [0xac]u8
}

@[packed]
pub struct G13FragmentJobParameters3 {
pub mut:
	depth_bias_array             G13ArrayAddress
	scissor_array                G13ArrayAddress
	visibility_result_buffer     u64
	unk_118                      u64
	unk_120                      [0x25]u64
	unk_reload_pipeline          G13ClearPipelineBinding
	unk_258                      u64
	unk_260                      u64
	unk_268                      u64
	unk_270                      u64
	reload_pipeline              G13ClearPipelineBinding
	zls_control                  u64
	unk_290                      u64
	depth_buffer_ptr_1           u64
	depth_buffer_stride_3        u64
	depth_meta_buffer_stride_3   u64
	depth_buffer_ptr_2           u64
	depth_buffer_ptr_3           u64
	depth_meta_buffer_ptr_3      u64
	stencil_buffer_ptr_1         u64
	stencil_buffer_stride_3      u64
	stencil_meta_buffer_stride_3 u64
	stencil_buffer_ptr_2         u64
	stencil_buffer_ptr_3         u64
	stencil_meta_buffer_ptr_3    u64
	unk_2f8                      [2]u64
	tib_blocks                   u32
	unk_30c                      u32
	aux_fb_info                  G13AuxFramebufferInfo
	tile_config                  u64
	unk_328_padding              [8]u8
	unk_partial_store_pipeline   G13StorePipelineBinding
	partial_store_pipeline       G13StorePipelineBinding
	isp_bgobjdepth               u32
	isp_bgobjvals                u32
	sample_size                  u32
	unk_37c                      u32
	unk_380                      u64
	unk_388                      u64
	depth_dimensions             u64
}

@[packed]
pub struct G13RunFragment {
pub mut:
	tag                        u32
	vm_slot                    u32
	unk_8                      u32
	microsequence              u64
	microsequence_size         u32
	notifier                   u64
	buffer                     u64
	scene                      u64
	unk_buffer                 u64
	tvb_tilemap                u64
	ppp_multisamplectl         u64
	samples                    u32
	tiles_per_mtile_y          u16
	tiles_per_mtile_x          u16
	unk_50                     u64
	unk_58                     u64
	merge_upper_x              u32
	merge_upper_y              u32
	unk_68                     u64
	tile_count                 u64
	job_params_1               G13FragmentJobParameters1
	job_params_2               G13FragmentJobParameters2
	job_params_3               G13FragmentJobParameters3
	unk_758_flag               u32
	unk_75c_flag               u32
	unk_buf                    [0x110]u8
	busy_flag                  u32
	tvb_overflow_count         u32
	unk_878                    u32
	encoder_params             G13EncoderParams
	process_empty_tiles        u32
	no_clear_pipeline_textures u32
	msaa_zs                    u32
	unk_pointee                u32
	meta                       G13JobMeta
	unk_after_meta             u32
	unk_buf_0                  u64
	unk_buf_8                  u64
	unk_buf_10                 u64
	cur_ts                     u64
	start_ts                   u64
	end_ts                     u64
	// Two opaque user-timestamp pointer words; all three legacy fields stay
	// zero in native preparation and occupy the reference's full 16 bytes.
	unk_914                    u32
	unk_918                    u64
	unk_920                    u32
	client_sequence            u8
	pad_925                    [3]u8
	unk_928                    u32
	unk_92c                    u8
	tail_padding               [3]u8
}

@[packed]
pub struct G13RunFragmentV135 {
pub mut:
	bytes [0x96c]u8
}

// Asahi submit_render derives the number of 2 KiB tile-image blocks from
// the uTile's sample footprint. Legacy inputs have a wider sample-size field,
// so calculate in 64 bits and check the firmware word before narrowing it.
pub fn g13_fragment_tib_blocks(utile_width u32, utile_height u32, samples u32,
	sample_size u32) ?u32 {
	if !((utile_width == 32 && utile_height == 32)
		|| (utile_width == 32 && utile_height == 16)
		|| (utile_width == 16 && utile_height == 16))
		|| (samples != 1 && samples != 2 && samples != 4) { return none }
	bytes := u64(utile_width) * utile_height * samples * sample_size
	blocks := (bytes + 2047) / 2048
	if blocks > u64(~u32(0)) { return none }
	return u32(blocks)
}

pub fn g13_fragment_active_size(abi hw.FirmwareAbi) ?u64 {
	return match abi {
		.v12_3 { u64(sizeof(G13RunFragment)) }
		.v13_5_partial { g13_fragment_v13_5_size }
		else { none }
	}
}

pub fn g13_fragment_job_params_1_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x78 } .v13_5_partial { 0x80 } else { none } }
}

pub fn g13_fragment_job_params_2_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x3c0 } .v13_5_partial { 0x3c8 } else { none } }
}

pub fn g13_fragment_job_params_3_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x4b0 } .v13_5_partial { 0x4b8 } else { none } }
}

pub fn g13_fragment_unk_758_flag_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { g13_fragment_unk_758_flag_offset } .v13_5_partial { 0x770 } else { none } }
}

pub fn g13_fragment_busy_flag_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { g13_fragment_busy_flag_offset } .v13_5_partial { 0x888 } else { none } }
}

pub fn g13_fragment_overflow_count_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { g13_fragment_overflow_count_offset } .v13_5_partial { 0x88c } else { none } }
}

pub fn g13_fragment_unk_pointee_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { g13_fragment_unk_pointee_offset } .v13_5_partial { 0x8c8 } else { none } }
}

pub fn g13_fragment_unk_buf_0_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { g13_fragment_unk_buf_0_offset } .v13_5_partial { 0x900 } else { none } }
}

pub fn g13_fragment_cur_ts_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { g13_fragment_cur_ts_offset } .v13_5_partial { 0x918 } else { none } }
}

pub fn g13_fragment_start_ts_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { g13_fragment_start_ts_offset } .v13_5_partial { 0x920 } else { none } }
}

pub fn g13_fragment_end_ts_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { g13_fragment_end_ts_offset } .v13_5_partial { 0x928 } else { none } }
}

pub fn make_g13_fragment_v13_5(legacy &G13RunFragment, counter u64) G13RunFragmentV135 {
	mut out := G13RunFragmentV135{}
	g13_copy_bytes(voidptr(&out), 0x000, voidptr(legacy), 0x000, 0x004)
	g13_put_u64(voidptr(&out), 0x004, counter)
	g13_copy_bytes(voidptr(&out), 0x00c, voidptr(legacy), 0x004, 0x074)
	// Start3DStruct2's AuxFBInfo gains an eight-byte tail while the opaque
	// suffix shrinks by the same amount, keeping the enclosing size at 0x348.
	g13_copy_bytes(voidptr(&out), 0x080, voidptr(legacy), 0x078, 0x040)
	// Queue::render sets AuxFBInfo::unk3 in both Ventura instances.
	g13_put_u64(voidptr(&out), 0x0c0, 0x100000)
	g13_copy_bytes(voidptr(&out), 0x0c8, voidptr(legacy), 0x0b8, 0x128)
	g13_copy_bytes(voidptr(&out), 0x1f0, voidptr(legacy), 0x1e0, 0x1d8)
	// Preserve the complete 0xf0-byte block, including its declared padding.
	// The next parameter block starts immediately after it at 0x4b8.
	g13_copy_bytes(voidptr(&out), 0x3c8, voidptr(legacy), 0x3c0, 0x0f0)
	// The third block gains the larger AuxFBInfo and one tail word. Copy its
	// stable regions around those insertions.
	g13_copy_bytes(voidptr(&out), 0x4b8, voidptr(legacy), 0x4b0, 0x220)
	g13_copy_bytes(voidptr(&out), 0x6d8, voidptr(legacy), 0x6d0, 0x010)
	g13_put_u64(voidptr(&out), 0x6e8, 0x100000)
	g13_copy_bytes(voidptr(&out), 0x6f0, voidptr(legacy), 0x6e0, 0x070)
	// unk_390_0 is inserted before depth_dimensions, not after it.
	g13_copy_bytes(voidptr(&out), 0x768, voidptr(legacy), 0x750, 0x008)
	// Preserve the scratch word before the new 13.3 reserved word. Metadata
	// follows that insertion; the scratch word itself must not move into it.
	g13_copy_bytes(voidptr(&out), 0x770, voidptr(legacy), 0x758, 0x11c)
	g13_copy_bytes(voidptr(&out), 0x88c, voidptr(legacy), 0x874, 0x03c)
	g13_copy_bytes(voidptr(&out), 0x8c8, voidptr(legacy), 0x8b0, 0x004)
	g13_copy_bytes(voidptr(&out), 0x8d0, voidptr(legacy), 0x8b4, 0x030)
	// Copy the complete common tail, including both timestamp-pointer pairs,
	// client_sequence and its following flags. The added 13.x tail stays zero.
	g13_copy_bytes(voidptr(&out), 0x900, voidptr(legacy), 0x8e4, 0x049)
	return out
}

pub fn g13_store_pipeline_binding(pipeline_bind u32, address u32) G13StorePipelineBinding {
	return G13StorePipelineBinding{
		pipeline_bind: pipeline_bind
		address: address
	}
}

pub fn validate_g13_fragment_layouts() bool {
	return sizeof(G13ClearPipelineBinding) == 0x10
		&& sizeof(G13StorePipelineBinding) == 0x20 && sizeof(G13ArrayAddress) == 0x10
		&& sizeof(G13AuxFramebufferInfo) == 0x10
		&& sizeof(G13FragmentJobParameters1) == 0x348
		&& sizeof(G13FragmentJobParameters2) == 0xf0
		&& sizeof(G13FragmentJobParameters3) == 0x2a8
		&& sizeof(G13RunFragment) == g13_fragment_v12_3_size
		&& sizeof(G13RunFragmentV135) == g13_fragment_v13_5_size
}
