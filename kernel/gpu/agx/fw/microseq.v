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
		&& sizeof(G13MicroseqSimpleOp) == 4
}
