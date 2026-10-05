// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module command

// Attachment records are shared by render and compute commands. Preserve both
// Mesa's byte size and G13's derived cache-line size so backend validation and
// firmware encoding consume the same immutable userspace snapshot.

import drm.ioctl
import usercopy

pub const max_attachments = u32(16)

pub struct Attachment {
pub:
	address     u64
	size_bytes  u64
	cache_lines u32
	order       u16
}

pub fn stage_attachments(pointer u64, count u32) (int, [16]Attachment) {
	mut staged := [16]Attachment{}
	if count == 0 {
		return 0, staged
	}
	if count > max_attachments || pointer == 0 {
		return -22, staged
	}
	bytes := u64(count) * sizeof(ioctl.DrmAsahiAttachment)
	if bytes - 1 > ~pointer {
		return -14, staged
	}
	for index := u32(0); index < count; index++ {
		mut attachment := ioctl.DrmAsahiAttachment{}
		if !usercopy.copy_from_user(voidptr(&attachment), pointer + u64(index) * sizeof(ioctl.DrmAsahiAttachment), sizeof(ioctl.DrmAsahiAttachment)) {
			return -14, staged
		}
		if attachment.flags != 0 || attachment.order < 1 || attachment.order > 6
			|| attachment.pointer == 0 || attachment.size == 0 {
			return -22, staged
		}
		cache_lines := (attachment.size >> 7) + if attachment.size & u64(127) != 0 {
			u64(1)
		} else {
			u64(0)
		}
		if cache_lines > u64(~u32(0)) {
			return -22, staged
		}
		staged[index] = Attachment{
			address: attachment.pointer
			size_bytes: attachment.size
			cache_lines: u32(cache_lines)
			order: u16(attachment.order)
		}
	}
	return 0, staged
}
