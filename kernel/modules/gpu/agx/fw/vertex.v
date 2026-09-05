module fw

// Byte-exact G13/macOS 12.3 vertex/tiler work command.

pub const g13_vertex_unk_pointee_offset = u64(0x480)
pub const g13_vertex_job_params_1_offset = u64(0x38)
pub const g13_vertex_tiling_params_offset = u64(0x3bc)
pub const g13_vertex_job_params_2_offset = u64(0x488)
pub const g13_vertex_cur_ts_offset = u64(0x5ac)
pub const g13_vertex_start_ts_offset = u64(0x5b4)
pub const g13_vertex_end_ts_offset = u64(0x5bc)

@[packed]
pub struct G13TilingParameters {
pub mut:
	region_size         u32
	unk_4               u32
	ppp_control         u32
	x_max               u16
	y_max               u16
	te_screen           u32
	te_mtile_1          u32
	te_mtile_2          u32
	tiles_per_mtile     u32
	tail_pointer_stride u32
	unk_24              u32
	unk_28              u32
	helper_cfg          u32
	padding             [0x70]u8
}

@[packed]
pub struct G13VertexJobParameters1 {
pub mut:
	unk_0                 u64
	unk_8                 u32
	unk_c                 u32
	tvb_tilemap           u64
	tvb_cluster_tilemaps  u64
	tail_pointer_cache    u64
	tvb_heapmeta          u64
	iogpu_unk_54          u64
	iogpu_unk_56          u64
	tvb_cluster_meta_1    u64
	utile_config          u32
	unk_4c                u32
	ppp_multisamplectl    u64
	tvb_layermeta         u64
	tvb_cluster_layermeta u64
	core_mask             [2]u32
	preempt_buf_1         u64
	preempt_buf_2         u64
	unk_80                u64
	preempt_buf_3         u64
	encoder               u64
	tvb_cluster_meta_2    u64
	tvb_cluster_meta_3    u64
	tiling_control        u32
	unk_ac                u32
	unk_b0                [6]u64
	pipeline_base         u64
	tvb_cluster_meta_4    u64
	unk_f0                u64
	unk_f8                u64
	helper_program        u32
	unk_104               u32
	helper_arg            u64
	unk_110               u64
	unk_118               u32
	padding               [0x268]u8
}

@[packed]
pub struct G13VertexJobParameters2 {
pub mut:
	unk_480         [4]u32
	unk_498         u64
	unk_4a0         u32
	preempt_buf_1   u64
	unk_4ac         u32
	unk_4b0         u64
	unk_4b8         u32
	unk_4bc         u64
	unk_4c4_padding [0x48]u8
	unk_50c         u32
	unk_510         u64
	unk_518         u64
	unk_520         u64
}

@[packed]
pub struct G13RunVertex {
pub mut:
	tag                  u32
	vm_slot              u32
	unk_8                u32
	notifier             u64
	buffer_slot          u32
	unk_1c               u32
	buffer               u64
	scene                u64
	unk_buffer           u64
	unk_34               u32
	job_params_1         G13VertexJobParameters1
	tiling_params        G13TilingParameters
	tail_pointer_cache   u64
	tail_pointer_size    u64
	microsequence        u64
	microsequence_size   u32
	fragment_stamp_slot  u32
	fragment_stamp_value u32
	unk_pointee          u32
	unk_pad              u32
	job_params_2         G13VertexJobParameters2
	encoder_params       G13EncoderParams
	unk_55c              u32
	unk_560              u32
	sync_grow            u32
	unk_568              u32
	spills               u32
	meta                 G13JobMeta
	unk_after_meta       u32
	unk_buf_0            u64
	unk_buf_8            u64
	unk_buf_10           u64
	cur_ts               u64
	start_ts             u64
	end_ts               u64
	unk_5c4              u32
	unk_5c8              u32
	unk_5cc              u32
	unk_5d0              u32
	client_sequence      u8
	pad_5d5              [3]u8
	unk_5d8              u32
	unk_5dc              u8
	tail_padding         [3]u8
}

pub fn validate_g13_vertex_layouts() bool {
	return sizeof(G13TilingParameters) == 0xa0
		&& sizeof(G13VertexJobParameters1) == 0x384
		&& sizeof(G13VertexJobParameters2) == 0xa0 && sizeof(G13RunVertex) == 0x5e0
}
