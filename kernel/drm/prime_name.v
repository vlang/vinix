// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.gem
import errno
import usercopy

fn set_prime_name(object &gem.GemObject, address u64) int {
	if object == unsafe { nil } { return -int(errno.einval) }
	if address == 0 { return -int(errno.efault) }
	mut name := [gem.dma_buf_name_capacity]u8{}
	mut copied := 0
	// Check for NUL before touching the next userspace page.
	for copied < name.len {
		if u64(copied) > ~address { return -int(errno.efault) }
		current := address + u64(copied)
		page_remaining := int(page_size - (current & (page_size - 1)))
		remaining := name.len - copied
		chunk := if page_remaining < remaining { page_remaining } else { remaining }
		if !usercopy.copy_from_user(unsafe { &name[copied] }, current, u64(chunk)) {
			return -int(errno.efault)
		}
		for index in copied .. copied + chunk {
			if name[index] == 0 {
				mut target := unsafe { object }
				target.lock.acquire()
				target.prime_name = name
				target.prime_name_len = u8(index + 1)
				target.lock.release()
				return 0
			}
		}
		copied += chunk
	}
	return -int(errno.einval)
}
