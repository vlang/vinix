module fw

// Exact G13/macOS 12.3 microsequence operations. GPU pointers are encoded as
// packed u64 values because Apple permits them at unaligned firmware offsets.

pub const g13_useq_wait_for_idle = u32(0x01)
pub const g13_useq_wait_for_idle_2 = u32(0x02)
pub const g13_useq_retire_stamp = u32(0x40000018)
pub const g13_useq_timestamp = u32(0x19)
pub const g13_useq_start_vertex = u32(0x22)
pub const g13_useq_finalize_vertex = u32(0x23)
pub const g13_useq_start_fragment = u32(0x24)
pub const g13_useq_finalize_fragment = u32(0x25)
pub const g13_useq_start_compute = u32(0x29)
pub const g13_useq_finalize_compute = u32(0x2a)

pub const g13_useq_pipe_vertex = u32(1) << 0
pub const g13_useq_pipe_fragment = u32(1) << 8
pub const g13_useq_pipe_compute = u32(1) << 15
pub const g13_max_attachments = 16

@[packed]
pub struct G13MicroseqAttachment {
pub mut:
	address u64
	size    u32
	unk_c   u16
	unk_e   u16
}

@[packed]
pub struct G13MicroseqAttachments {
pub mut:
	list  [g13_max_attachments]G13MicroseqAttachment
	count u32
}

@[packed]
pub struct G13MicroseqTimestamp {
pub mut:
	header     u32
	cur_ts     u64
	start_ts   u64
	update_ts  u64
	work_queue u64
	unk_24     u64
	uuid       u32
	pad_30     u32
}

@[packed]
pub struct G13MicroseqStartVertex {
pub mut:
	header           u32
	tiling_params    u64
	job_params_1     u64
	buffer           u64
	scene            u64
	stats            u64
	work_queue       u64
	vm_slot          u32
	unk_38           u32
	event_generation u32
	buffer_slot      u32
	unk_44           u32
	event_sequence   u64
	unk_50           u32
	unk_pointer      u64
	unk_job_buffer   u64
	unk_64           u32
	unk_68           u32
	uuid             u32
	attachments      G13MicroseqAttachments
	padding          u32
	unk_178          u32
}

@[packed]
pub struct G13MicroseqFinalizeVertex {
pub mut:
	header                u32
	scene                 u64
	buffer                u64
	stats                 u64
	work_queue            u64
	vm_slot               u32
	unk_28                u32
	unk_pointer           u64
	unk_34                u32
	uuid                  u32
	fw_stamp              u64
	stamp_value           u32
	unk_48                u64
	unk_50                u32
	unk_54                u32
	unk_58                u64
	unk_60                u32
	unk_64                u32
	unk_68                u32
	restart_branch_offset i32
	has_attachments       u32
}

@[packed]
pub struct G13MicroseqStartFragment {
pub mut:
	header             u32
	job_params_2       u64
	job_params_1       u64
	scene              u64
	stats              u64
	busy_flag          u64
	tvb_overflow_count u64
	unk_pointer        u64
	work_queue         u64
	work_item          u64
	vm_slot            u32
	unk_50             u32
	event_generation   u32
	buffer_slot        u32
	sync_grow          u32
	event_sequence     u64
	unk_68             u32
	unk_758_flag       u64
	unk_job_buffer     u64
	unk_7c             u32
	unk_80             u32
	unk_84             u32
	uuid               u32
	attachments        G13MicroseqAttachments
	padding            u32
}

@[packed]
pub struct G13MicroseqFinalizeFragment {
pub mut:
	header                u32
	uuid                  u32
	unk_8                 u32
	fw_stamp              u64
	stamp_value           u32
	unk_18                u32
	scene                 u64
	buffer                u64
	unk_2c                u64
	stats                 u64
	unk_pointer           u64
	busy_flag             u64
	work_queue            u64
	work_item             u64
	vm_slot               u32
	unk_60                u32
	unk_758_flag          u64
	unk_6c                u64
	unk_74                u64
	unk_7c                u64
	unk_84                u64
	unk_8c                u64
	restart_branch_offset i32
	has_attachments       u32
}

@[packed]
pub struct G13MicroseqStartCompute {
pub mut:
	header           u32
	unk_pointer      u64
	job_params_1     u64
	stats            u64
	work_queue       u64
	vm_slot          u32
	unk_28           u32
	event_generation u32
	event_sequence   u64
	unk_38           u32
	job_params_2     u64
	unk_44           u32
	uuid             u32
	attachments      G13MicroseqAttachments
	padding          u32
}

@[packed]
pub struct G13MicroseqFinalizeCompute {
pub mut:
	header                u32
	stats                 u64
	work_queue            u64
	vm_slot               u32
	unk_18                u32
	job_params_2          u64
	unk_24                u32
	uuid                  u32
	fw_stamp              u64
	stamp_value           u32
	unk_38                u32
	unk_3c                u32
	unk_40                u32
	unk_44                u32
	unk_48                u32
	unk_4c                u32
	unk_50                u32
	unk_54                u32
	unk_58                u32
	restart_branch_offset i32
	has_attachments       u32
}

@[packed]
pub struct G13MicroseqSimpleOp {
pub mut:
	header u32
}

@[packed]
pub struct G13MicroseqTimestampV135 {
pub mut:
	bytes [0x3c]u8
}
@[packed]
pub struct G13MicroseqStartVertexV135 {
pub mut:
	bytes [0x18c]u8
}
@[packed]
pub struct G13MicroseqFinalizeVertexV135 {
pub mut:
	bytes [0x84]u8
}
@[packed]
pub struct G13MicroseqStartFragmentV135 {
pub mut:
	bytes [0x1ac]u8
}
@[packed]
pub struct G13MicroseqFinalizeFragmentV135 {
pub mut:
	bytes [0xb4]u8
}
@[packed]
pub struct G13MicroseqStartComputeV135 {
pub mut:
	bytes [0x16c]u8
}
@[packed]
pub struct G13MicroseqFinalizeComputeV135 {
pub mut:
	bytes [0x7c]u8
}

pub fn g13_microseq_timestamp_v13_5(legacy &G13MicroseqTimestamp,
	unknown_timestamp_address u64) G13MicroseqTimestampV135 {
	mut out := G13MicroseqTimestampV135{}
	g13_copy_bytes(voidptr(&out), 0, voidptr(legacy), 0, 0x2c)
	g13_put_u64(voidptr(&out), 0x2c, unknown_timestamp_address)
	g13_copy_bytes(voidptr(&out), 0x34, voidptr(legacy), 0x2c, 8)
	return out
}

pub fn g13_microseq_start_vertex_v13_5(legacy &G13MicroseqStartVertex,
	counter u64, event_control_buffer u64) G13MicroseqStartVertexV135 {
	mut out := G13MicroseqStartVertexV135{}
	g13_copy_bytes(voidptr(&out), 0, voidptr(legacy), 0, 0x178)
	g13_put_u64(voidptr(&out), 0x178, counter)
	g13_put_u64(voidptr(&out), 0x180, event_control_buffer)
	g13_copy_bytes(voidptr(&out), 0x188, voidptr(legacy), 0x178, 4)
	return out
}

pub fn g13_microseq_finalize_vertex_v13_5(legacy &G13MicroseqFinalizeVertex) G13MicroseqFinalizeVertexV135 {
	mut out := G13MicroseqFinalizeVertexV135{}
	g13_copy_bytes(voidptr(&out), 0, voidptr(legacy), 0, 0x74)
	return out
}

pub fn g13_microseq_start_fragment_v13_5(legacy &G13MicroseqStartFragment,
	counter u64, event_control_buffer u64) G13MicroseqStartFragmentV135 {
	mut out := G13MicroseqStartFragmentV135{}
	g13_copy_bytes(voidptr(&out), 0, voidptr(legacy), 0, 0x7c)
	g13_copy_bytes(voidptr(&out), 0x84, voidptr(legacy), 0x7c, 0x118)
	g13_put_u64(voidptr(&out), 0x19c, counter)
	g13_put_u64(voidptr(&out), 0x1a4, event_control_buffer)
	return out
}

pub fn g13_microseq_finalize_fragment_v13_5(legacy &G13MicroseqFinalizeFragment) G13MicroseqFinalizeFragmentV135 {
	mut out := G13MicroseqFinalizeFragmentV135{}
	g13_copy_bytes(voidptr(&out), 0, voidptr(legacy), 0, 0x6c)
	g13_copy_bytes(voidptr(&out), 0x74, voidptr(legacy), 0x6c, 0x30)
	return out
}

pub fn g13_microseq_start_compute_v13_5(legacy &G13MicroseqStartCompute,
	flag_address u64, counter u64, event_control_buffer u64) G13MicroseqStartComputeV135 {
	mut out := G13MicroseqStartComputeV135{}
	g13_copy_bytes(voidptr(&out), 0, voidptr(legacy), 0, 0x154)
	g13_put_u64(voidptr(&out), 0x154, flag_address)
	g13_put_u64(voidptr(&out), 0x15c, counter)
	g13_put_u64(voidptr(&out), 0x164, event_control_buffer)
	return out
}

pub fn g13_microseq_finalize_compute_v13_5(legacy &G13MicroseqFinalizeCompute) G13MicroseqFinalizeComputeV135 {
	mut out := G13MicroseqFinalizeComputeV135{}
	g13_copy_bytes(voidptr(&out), 0, voidptr(legacy), 0, 0x18)
	g13_copy_bytes(voidptr(&out), 0x18, voidptr(legacy), 0x1c, 0x48)
	return out
}

pub fn g13_wait_for_idle_header(pipe u32) ?u32 {
	if pipe != g13_useq_pipe_vertex && pipe != g13_useq_pipe_fragment
		&& pipe != g13_useq_pipe_compute {
		return none
	}
	return g13_useq_wait_for_idle | (pipe << 8)
}

pub fn validate_g13_microsequence_layouts() bool {
	return sizeof(G13MicroseqAttachment) == 0x10
		&& sizeof(G13MicroseqAttachments) == 0x104
		&& sizeof(G13MicroseqTimestamp) == 0x34
		&& sizeof(G13MicroseqStartVertex) == 0x17c
		&& sizeof(G13MicroseqFinalizeVertex) == 0x74
		&& sizeof(G13MicroseqStartFragment) == 0x194
		&& sizeof(G13MicroseqFinalizeFragment) == 0x9c
		&& sizeof(G13MicroseqStartCompute) == 0x154
		&& sizeof(G13MicroseqFinalizeCompute) == 0x64
		&& sizeof(G13MicroseqTimestampV135) == 0x3c
		&& sizeof(G13MicroseqStartVertexV135) == 0x18c
		&& sizeof(G13MicroseqFinalizeVertexV135) == 0x84
		&& sizeof(G13MicroseqStartFragmentV135) == 0x1ac
		&& sizeof(G13MicroseqFinalizeFragmentV135) == 0xb4
		&& sizeof(G13MicroseqStartComputeV135) == 0x16c
		&& sizeof(G13MicroseqFinalizeComputeV135) == 0x7c
		&& sizeof(G13MicroseqSimpleOp) == 4
}
