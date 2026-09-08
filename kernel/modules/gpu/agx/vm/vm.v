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

// Validate fields according to their operation before either backend looks up
// a BO or changes mappings. In particular, UNBIND_ALL names a BO by handle and
// does not carry a VA range.
pub fn valid_bind_request(request &ioctl.DrmAsahiGemBind, kernel_start u64,
	kernel_end u64) bool {
	if request.extensions != 0 {
		return false
	}
	match request.op {
		ioctl.asahi_bind_op_bind {
			return request.flags != 0
				&& request.flags & ~(ioctl.asahi_bind_read | ioctl.asahi_bind_write) == 0
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
