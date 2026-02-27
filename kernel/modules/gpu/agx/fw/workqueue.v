module fw

// Firmware workqueue structures
// Defines the work descriptors submitted to the GPU via pipe channels
// Translates fw/workqueue.rs from the Asahi Linux GPU driver

// Command types
pub const cmd_type_run_vertex = u32(0x00)
pub const cmd_type_run_fragment = u32(0x01)
pub const cmd_type_run_compute = u32(0x02)
pub const cmd_type_barrier = u32(0x03)
pub const cmd_type_timestamp = u32(0x04)
pub const cmd_type_end = u32(0x18)

// Work error codes
pub const work_err_none = u32(0)
pub const work_err_timeout = u32(1)
pub const work_err_fault = u32(2)
pub const work_err_killed = u32(3)
pub const work_err_channel_error = u32(4)

// Workqueue header in shared memory
@[packed]
pub struct FwWorkqueueHeader {
pub mut:
	tag            u32
	unk_4          u32
	unk_8          u32
	cur_cmdqueue   u32
	unk_10         u32
	cur_count      u32
	unk_18         u64
	unk_20         u64
	gpu_pointer    u64
	unk_30         u64
	unk_38         u64
	event_count    u32
	pad_44         u32
	unk_48         u64
	unk_50         u64
	unk_58         u64
	unk_60         u64
	unk_68         u64
}

// Command queue descriptor
@[packed]
pub struct FwCmdQueueDescriptor {
pub mut:
	gpu_buf_addr u64
	gpu_buf_size u32
	unk_c        u32
	unk_10       u64
	unk_18       u64
	unk_20       u32
	unk_24       u32
	ring_addr    u64
	ring_size    u32
	pad_34       u32
}
