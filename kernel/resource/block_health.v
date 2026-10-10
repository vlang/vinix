// SPDX-License-Identifier: GPL-2.0-or-later
module resource

pub const block_health_ioctl = u64(0x56560005)
pub const health_ata = u64(1)
pub const health_supported = u64(1)
pub const health_enabled = u64(2)
pub const health_data_valid = u64(4)
pub const health_status_valid = u64(8)
pub const health_threshold_exceeded = u64(16)

// Output-only, native little-endian version-one ABI (1088 bytes). ATA data
// is preserved byte-for-byte: attribute meanings and raw units are vendor
// specific. No userspace command, address or DMA buffer enters the driver.
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
