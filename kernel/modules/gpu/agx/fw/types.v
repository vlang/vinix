module fw

// Early common-type sketches for the partial G13 v12.3 implementation.
// Hardware bootstrap remains gated off until every firmware-visible type is
// independently byte-validated.

// GPU firmware version
pub const fw_ver_major = u32(12)
pub const fw_ver_minor = u32(3)
pub const fw_ver_patch = u32(0)

// Stamp value for completion tracking
@[packed]
pub struct FwStamp {
pub mut:
	value u32
	pad   u32
}

// Notification type
@[packed]
pub struct FwNotifier {
pub mut:
	state u32
	pad   u32
}

// GPU pointer (64-bit VA in GPU address space)
@[packed]
pub struct GpuPointer {
pub mut:
	addr u64
}

// Completion message
@[packed]
pub struct FwCompletion {
pub mut:
	tag         u32
	stamp_slot  u32
	stamp_value u32
	pad         u32
}

// Work command header
@[packed]
pub struct FwCmdHeader {
pub mut:
	tag     u32
	cmd_type u32
	unk_8   u32
	flags   u32
	control u64
}

// Buffer descriptor
@[packed]
pub struct FwBufferDesc {
pub mut:
	gpu_addr u64
	size     u64
	flags    u32
	pad      u32
}

// Shared memory region descriptor
@[packed]
pub struct FwShmemDesc {
pub mut:
	iova  u64
	size  u64
	flags u32
	pad   u32
}
