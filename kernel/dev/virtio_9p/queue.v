// SPDX-License-Identifier: GPL-2.0-or-later
module virtio_9p

pub const buffer_bytes = u32(65536)
const queue_align = u64(4096)

pub fn queue_size(maximum u32) u16 {
	// Legacy PCI's size is read-only. Never install a smaller ring there.
	return if maximum >= 2 && maximum <= 1024 && maximum & (maximum - 1) == 0 {
		u16(maximum)
	} else {
		u16(0)
	}
}

pub fn used_offset(size u16) u64 {
	return (u64(size) * 18 + 6 + queue_align - 1) & ~(queue_align - 1)
}

pub fn ring_bytes(size u16) u64 { return used_offset(size) + 6 + u64(size) * 8 }

pub fn valid_completion(previous u16, current u16, id u32, length u32, capacity u32) bool {
	return u16(current - previous) == 1 && id == 0 && length >= 7
		&& length <= capacity && capacity <= buffer_bytes
}

pub fn valid_ring(address u64, bytes u64, page u64) bool {
	if page < 4096 || page > 65536 || page & (page - 1) != 0 { return false }
	limit := page << 32
	return address != 0 && address & (page - 1) == 0 && address < limit
		&& bytes != 0 && bytes <= limit - address
}
