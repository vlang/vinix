module fw

// Copy between packed firmware objects without imposing host alignment. The
// caller supplies bounds established by the corresponding ABI layout.
fn g13_copy_bytes(destination voidptr, destination_offset u32, source voidptr,
	source_offset u32, length u32) {
	unsafe {
		mut dst := &u8(destination)
		src := &u8(source)
		for index := u32(0); index < length; index++ {
			dst[destination_offset + index] = src[source_offset + index]
		}
	}
}

fn g13_put_u64(destination voidptr, offset u32, value u64) {
	unsafe {
		mut dst := &u8(destination)
		for index := u32(0); index < 8; index++ {
			dst[offset + index] = u8(value >> (index * 8))
		}
	}
}

// Small common types shared by the byte-validated G13 v12.3 implementation.

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
	tag      u32
	cmd_type u32
	unk_8    u32
	flags    u32
	control  u64
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
