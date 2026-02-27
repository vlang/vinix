module queue

// Compute command building
// Constructs GPU work descriptors for compute dispatch (GPGPU).
// Defines workgroup and grid dimensions, shared memory allocation,
// and completion stamps. Translates queue/ compute code from the
// Asahi Linux GPU driver.

import gpu.agx.fw

// Maximum compute dispatch dimensions
const max_workgroup_dim = u32(1024)
const max_grid_dim = u32(65535)
const max_shared_mem = u32(32768)

pub struct ComputeCommand {
pub mut:
	flags            u32
	compute_buf_addr u64
	compute_buf_size u64
	// Workgroup dimensions
	wg_x             u32
	wg_y             u32
	wg_z             u32
	// Grid dimensions
	grid_x           u32
	grid_y           u32
	grid_z           u32
	// Shared memory
	shared_mem_size  u32
	// Stamp
	stamp_addr       u64
	stamp_value      u32
	// Result
	result_addr      u64
	result_size      u32
}

pub struct ComputeSubmit {
pub mut:
	tag         u32
	cmd         ComputeCommand
	barrier_tag u32
	unk_pad     [8]u32
}

// Build a compute submission descriptor from a compute command.
// Sets the tag to identify this as a compute workload.
pub fn build_compute_cmd(cmd &ComputeCommand) ComputeSubmit {
	return ComputeSubmit{
		tag: fw.cmd_type_run_compute
		cmd: unsafe { *cmd }
	}
}

// Validate a compute command before submission.
// Checks workgroup dimensions, grid dimensions, buffer addresses,
// and shared memory size for sanity.
pub fn validate_compute_cmd(cmd &ComputeCommand) bool {
	// Compute buffer must be provided
	if cmd.compute_buf_addr == 0 || cmd.compute_buf_size == 0 {
		return false
	}

	// Workgroup dimensions must be non-zero and within limits
	if cmd.wg_x == 0 || cmd.wg_x > max_workgroup_dim {
		return false
	}
	if cmd.wg_y == 0 || cmd.wg_y > max_workgroup_dim {
		return false
	}
	if cmd.wg_z == 0 || cmd.wg_z > max_workgroup_dim {
		return false
	}

	// Total workgroup size must not exceed hardware limit
	total_wg := cmd.wg_x * cmd.wg_y * cmd.wg_z
	if total_wg > max_workgroup_dim {
		return false
	}

	// Grid dimensions must be non-zero
	if cmd.grid_x == 0 || cmd.grid_x > max_grid_dim {
		return false
	}
	if cmd.grid_y == 0 || cmd.grid_y > max_grid_dim {
		return false
	}
	if cmd.grid_z == 0 || cmd.grid_z > max_grid_dim {
		return false
	}

	// Shared memory must not exceed hardware limit
	if cmd.shared_mem_size > max_shared_mem {
		return false
	}

	return true
}
