module fw

// Job descriptor firmware structures
// These packed structs define the top-level job descriptors that wrap
// individual vertex/fragment/compute commands for submission to the
// firmware work queue. Byte-accurate layout for firmware version 12.3.0.

// Must match workqueue.max_job_slots
const fw_max_job_slots = 127

// Firmware job descriptor -- wraps a pointer to a command and
// carries scheduling metadata (priority, stamps, completion tags).
@[packed]
pub struct FwJob {
pub mut:
	tag               u32
	unk_4             u32
	cmd_addr          u64 // GPU pointer to command (vertex/fragment/compute)
	cmd_count         u32
	unk_14            u32
	completion_tag    u32
	unk_1c            u32
	stamp_addr        u64
	stamp_value_start u32
	stamp_value_end   u32
	unk_30            u64
	unk_38            u64
	unk_40            u32
	priority          u32
	unk_48            u64
}

// Firmware job list -- an array of job descriptors that the firmware
// processes sequentially from its work queue ring buffer.
@[packed]
pub struct FwJobList {
pub mut:
	count u32
	pad   u32
	jobs  [fw_max_job_slots]FwJob
}
