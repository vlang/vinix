module fw

import gpu.agx.hw

// Byte-exact G13/macOS 12.3 fragment work command.
//
// The offsets below are the ones g13.v hands to the microsequence, so firmware
// dereferences them directly and they are the authority on where each region
// starts. Both parameter blocks carry trailing bytes that no recovered field
// names: without them job_params_2 lands at 0x3b8 instead of 0x3c0 and every
// later offset in the command is eight bytes adrift of the pointers already
// published to firmware. validate_g13_fragment_layouts() is what catches that.

pub const g13_fragment_job_params_1_offset = u64(0x78)
pub const g13_fragment_job_params_2_offset = u64(0x3c0)
pub const g13_fragment_job_params_3_offset = u64(0x4b0)
pub const g13_fragment_unk_758_flag_offset = u64(0x760)
pub const g13_fragment_busy_flag_offset = u64(0x878)
pub const g13_fragment_overflow_count_offset = u64(0x87c)
pub const g13_fragment_unk_pointee_offset = u64(0x8b8)
pub const g13_fragment_unk_buf_0_offset = u64(0x8ec)
pub const g13_fragment_cur_ts_offset = u64(0x904)
pub const g13_fragment_start_ts_offset = u64(0x90c)
pub const g13_fragment_end_ts_offset = u64(0x914)
pub const g13_fragment_v13_5_size = u64(0x974)

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
	unk_398_padding              [8]u8
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
	bytes [0x974]u8
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
	return match abi { .v12_3 { 0x4b0 } .v13_5_partial { 0x4a8 } else { none } }
}

pub fn g13_fragment_unk_758_flag_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x760 } .v13_5_partial { 0x770 } else { none } }
}

pub fn g13_fragment_busy_flag_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x878 } .v13_5_partial { 0x888 } else { none } }
}

pub fn g13_fragment_overflow_count_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x87c } .v13_5_partial { 0x88c } else { none } }
}

pub fn g13_fragment_unk_pointee_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x8b8 } .v13_5_partial { 0x8c8 } else { none } }
}

pub fn g13_fragment_unk_buf_0_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x8ec } .v13_5_partial { 0x900 } else { none } }
}

pub fn g13_fragment_cur_ts_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x904 } .v13_5_partial { 0x918 } else { none } }
}

pub fn g13_fragment_start_ts_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x90c } .v13_5_partial { 0x920 } else { none } }
}

pub fn g13_fragment_end_ts_offset_for(abi hw.FirmwareAbi) ?u64 {
	return match abi { .v12_3 { 0x914 } .v13_5_partial { 0x928 } else { none } }
}

pub fn make_g13_fragment_v13_5(legacy &G13RunFragment) G13RunFragmentV135 {
	mut out := G13RunFragmentV135{}
	g13_copy_bytes(voidptr(&out), 0x000, voidptr(legacy), 0x000, 0x004)
	g13_copy_bytes(voidptr(&out), 0x00c, voidptr(legacy), 0x004, 0x074)
	// Start3DStruct2's AuxFBInfo gains an eight-byte tail while the opaque
	// suffix shrinks by the same amount, keeping the enclosing size at 0x348.
	g13_copy_bytes(voidptr(&out), 0x080, voidptr(legacy), 0x078, 0x040)
	g13_copy_bytes(voidptr(&out), 0x0c8, voidptr(legacy), 0x0b8, 0x128)
	g13_copy_bytes(voidptr(&out), 0x1f0, voidptr(legacy), 0x1e0, 0x1d8)
	// Struct1 is 0xe0 at both Ventura and the pinned m1n1 12.3 definition.
	g13_copy_bytes(voidptr(&out), 0x3c8, voidptr(legacy), 0x3c0, 0x0e0)
	// Struct3 gains a 0x10 register prefix, the larger AuxFBInfo, and one tail
	// pointer. Copy its three stable regions around those insertions.
	g13_copy_bytes(voidptr(&out), 0x4b8, voidptr(legacy), 0x4b0, 0x220)
	g13_copy_bytes(voidptr(&out), 0x6d8, voidptr(legacy), 0x6d0, 0x010)
	g13_copy_bytes(voidptr(&out), 0x6f0, voidptr(legacy), 0x6e0, 0x080)
	// The command tail is grouped as flags/busy, Struct6, Struct7, then
	// timestamps. Struct7 gains a four-byte prefix at 13.5.
	g13_copy_bytes(voidptr(&out), 0x770, voidptr(legacy), 0x760, 0x11c)
	g13_copy_bytes(voidptr(&out), 0x88c, voidptr(legacy), 0x87c, 0x03c)
	g13_copy_bytes(voidptr(&out), 0x8cc, voidptr(legacy), 0x8b8, 0x034)
	// Copy through client_sequence. Ventura's two additional timestamp words
	// and trailing flags remain zero-initialised after it.
	g13_copy_bytes(voidptr(&out), 0x900, voidptr(legacy), 0x8ec, 0x041)
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
		&& sizeof(G13FragmentJobParameters3) == 0x2b0
		&& sizeof(G13RunFragment) == 0x938
		&& sizeof(G13RunFragmentV135) == g13_fragment_v13_5_size
}
