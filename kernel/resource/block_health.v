// SPDX-License-Identifier: GPL-2.0-or-later
module resource

pub const block_health_ioctl = u64(0x56560005)
pub const health_ata = u64(1)
pub const health_nvme = u64(2)
pub const health_supported = u64(1)
pub const health_enabled = u64(2)
pub const health_data_valid = u64(4)
pub const health_status_valid = u64(8)
pub const health_threshold_exceeded = u64(16)

// Output-only, native little-endian version-one ABI (1088 bytes). Protocol 1
// contains ATA IDENTIFY and SMART READ DATA. Protocol 2 contains the first 512
// bytes of NVMe Identify Controller and the controller-wide SMART/Health log.
// Payloads are preserved byte-for-byte. No userspace command, address or DMA
// buffer enters the driver. Flag 16 means ATA threshold exceeded or any NVMe
// critical warning; it is not a prediction of future failure.
pub struct BlockHealth {
pub mut:
	version u64 = 1
	protocol u64
	flags u64
	disk_id u64
	reserved [4]u64
	identify [512]u8
	data [512]u8
}

pub interface BlockHealthResource {
mut:
	block_health() ?BlockHealth
}

struct BlockHealthCall {
mut:
	device BlockHealthResource
}
