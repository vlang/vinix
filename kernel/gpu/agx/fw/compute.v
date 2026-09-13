module fw

// Exact G13/macOS 12.3 compute work command. The firmware reads this command
// from the queue's GPU-read-only heap while retaining write access to its
// timestamp and bookkeeping fields.

pub const g13_compute_unk_pointee_offset = u64(0x14)
pub const g13_compute_job_params_1_offset = u64(0x68)
pub const g13_compute_microsequence_offset = u64(0x1e8)
pub const g13_compute_job_params_2_offset = u64(0x1f4)
pub const g13_compute_cur_ts_offset = u64(0x2a8)
pub const g13_compute_start_ts_offset = u64(0x2b0)
pub const g13_compute_end_ts_offset = u64(0x2b8)

@[packed]
pub struct G13ComputeJobParameters1 {
pub mut:
	preempt_buf_1  u64
	encoder        u64
	preempt_buf_2  u64
	preempt_buf_3  u64
	preempt_buf_4  u64
	preempt_buf_5  u64
	pipeline_base  u64
	unk_38         u64
	helper_program u32
	unk_44         u32
	helper_arg     u64
	helper_cfg     u32
	unk_54         u32
	unk_58         u32
	unk_5c         u32
	iogpu_unk_40   u32
	padding        [0xfc]u8
}

@[packed]
pub struct G13ComputeJobParameters2 {
pub mut:
	unk_0         [0x24]u8
	preempt_buf_1 u64
	encoder_end   u64
	unk_34        [0x20]u8
	unk_g14x      u32
	unk_58        u32
	unk_5c        u32
}

@[packed]
pub struct G13RunCompute {
pub mut:
	tag                u32
	unk_4              u32
	vm_slot            u32
	notifier           u64
	unk_pointee        u32
	pad_18             [0x50]u8
	job_params_1       G13ComputeJobParameters1
	pad_1c8            [0x20]u8
	microsequence      u64
	microsequence_size u32
	job_params_2       G13ComputeJobParameters2
	encoder_params     G13EncoderParams
	meta               G13JobMeta
	cur_ts             u64
	start_ts           u64
	end_ts             u64
	unk_2c0            u32
	unk_2c4            u32
	unk_2c8            u32
	unk_2cc            u32
	client_sequence    u8
	pad_2d1            [3]u8
	unk_2d4            u32
	unk_2d8            u8
	// The source ABI is repr(C) with four-byte aggregate alignment. V's
	// packed structs have no implicit tail padding, so encode it explicitly.
	tail_padding [3]u8
}

pub fn validate_g13_compute_layouts() bool {
	return sizeof(G13ComputeJobParameters1) == 0x160
		&& sizeof(G13ComputeJobParameters2) == 0x60
		&& sizeof(G13RunCompute) == 0x2dc
}
