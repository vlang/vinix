// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module vm

// Pure AGX VM contract shared by software and hardware backends. This module
// deliberately has no dependency on UAT, DART, firmware, MMIO, or an AGX
// manager; backends implement the validated operation in their own address
// space.

import drm.ioctl

pub const page_size = u64(0x4000)
pub const page_mask = page_size - 1
pub const address_space_end = u64(1) << 39
pub const user_start = page_size
pub const user_end = address_space_end - 2 * page_size
pub const kernel_min_size = u64(0x20000000)
// Asahi buffer::PAGE_SIZE, distinct from the 16 KiB UAT granule.
pub const driver_page_size = u64(0x8000)

pub struct DriverWindow {
pub:
	start u64
	midpoint u64
	end u64
}

// Validate the userspace reservation before aligning inward. Both driver
// heaps use 32 KiB boundaries, including the split of an odd-sized window.
pub fn driver_window(kernel_start u64, kernel_end u64) ?DriverWindow {
	if !valid_window(kernel_start, kernel_end) { return none }
	mask := driver_page_size - 1
	start := (kernel_start + mask) & ~mask
	end := kernel_end & ~mask
	if start >= end { return none }
	half := ((end - start) >> 1) & ~mask
	if half == 0 || half >= end - start { return none }
	return DriverWindow{ start: start, midpoint: start + half, end: end }
}

pub fn valid_window(kernel_start u64, kernel_end u64) bool {
	return kernel_start >= user_start && kernel_start < kernel_end
		&& kernel_start & page_mask == 0 && kernel_end & page_mask == 0
		&& kernel_end <= user_end && kernel_end - kernel_start >= kernel_min_size
}

pub fn valid_user_range(address u64, size u64, kernel_start u64, kernel_end u64) bool {
	if size == 0 || address & page_mask != 0 || size & page_mask != 0
		|| address < user_start || address >= user_end || size > user_end - address {
		return false
	}
	end := address + size
	return address >= kernel_end || end <= kernel_start
}

// BIND alignment and supported flag bits precede BO lookup. Global ranges and
// the requirement for a read/write permission are checked after BO lookup.
pub fn valid_bind_header(request &ioctl.DrmAsahiGemBind) bool {
	return request.extensions == 0 && request.op == ioctl.asahi_bind_op_bind
		&& request.flags & ~(ioctl.asahi_bind_read | ioctl.asahi_bind_write | ioctl.asahi_bind_single_page) == 0
		&& (request.addr | request.range | request.offset) & page_mask == 0
}

// Validate operation fields and global VA bounds. UNBIND_ALL names a BO by
// handle and does not carry a VA range. The private reservation follows VM lookup.
pub fn valid_bind_shape(request &ioctl.DrmAsahiGemBind) bool {
	// An empty reservation excludes no addresses. Validate the global range
	// and operation fields before looking up the VM's actual reservation.
	return valid_bind_request(request, 0, 0)
}

// SINGLE_PAGE repeats one complete UAT page; the VA range remains independent.
pub fn bind_backing_size(request &ioctl.DrmAsahiGemBind) u64 {
	return if request.flags & ioctl.asahi_bind_single_page != 0 { page_size } else { request.range }
}

pub fn valid_bind_request(request &ioctl.DrmAsahiGemBind, kernel_start u64,
	kernel_end u64) bool {
	if request.extensions != 0 {
		return false
	}
	match request.op {
		ioctl.asahi_bind_op_bind {
			return request.flags & (ioctl.asahi_bind_read | ioctl.asahi_bind_write) != 0
				&& request.flags & ~(ioctl.asahi_bind_read | ioctl.asahi_bind_write | ioctl.asahi_bind_single_page) == 0
				&& request.offset & page_mask == 0
				&& valid_user_range(request.addr, request.range, kernel_start, kernel_end)
		}
		ioctl.asahi_bind_op_unbind {
			return request.handle == 0 && request.flags == 0 && request.offset == 0
				&& valid_user_range(request.addr, request.range, kernel_start, kernel_end)
		}
		ioctl.asahi_bind_op_unbind_all {
			return request.handle != 0 && request.flags == 0 && request.offset == 0
				&& request.range == 0 && request.addr == 0
		}
		else {
			return false
		}
	}
}
