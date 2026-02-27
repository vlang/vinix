module fw

// Firmware compute command structures
// These packed structs must match the firmware binary layout exactly.
// The FwComputeCmd is submitted to the GPU via the compute pipe channel
// and tells the firmware how to dispatch a compute workload.
// Byte-accurate layout for firmware version 12.3.0.

// Firmware compute command descriptor
@[packed]
pub struct FwComputeCmd {
pub mut:
	header          FwCmdHeader
	unk_10          u64
	buf_addr        u64
	buf_size        u64
	unk_28          u64
	unk_30          u64
	wg_x            u32
	wg_y            u32
	wg_z            u32
	grid_x          u32
	grid_y          u32
	grid_z          u32
	shared_mem_size u32
	pad_54          u32
	stamp_addr      u64
	stamp_value     u32
	stamp_slot      u32
	unk_68          u64
	unk_70          u64
	result_addr     u64
	result_size     u32
	pad_84          u32
}
