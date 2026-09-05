module fw

// Firmware compute command structures
// Early G13 compute-command sketch. Hardware bootstrap and submission remain
// disabled until the complete v12.3 firmware object graph is represented.

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
