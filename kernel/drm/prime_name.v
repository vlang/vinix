// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.gem
import errno
import resource
import usercopy

const prime_link_prefix = '/dmabuf:'
pub const prime_link_capacity = 8 + gem.dma_buf_name_capacity

struct PrimeName {
	bytes [gem.dma_buf_name_capacity]u8
	length int // includes the terminator when set
}

fn snapshot_prime_name(object &gem.GemObject) PrimeName {
	if object == unsafe { nil } { return PrimeName{} }
	mut target := unsafe { object }
	target.lock.acquire()
	name := PrimeName{bytes: target.prime_name, length: int(target.prime_name_len)}
	target.lock.release()
	return name
}

// The caller holds a description reference and supplies prime_link_capacity
// bytes of storage. The returned length excludes the terminating NUL.
pub fn prime_link_target(mut res resource.Resource, out &u8) ?u64 {
	if mut res is GemPrimeResource {
		name := snapshot_prime_name(res.obj)
		prefix_size := u64(prime_link_prefix.len)
		name_size := if name.length > 0 { u64(name.length - 1) } else { u64(0) }
		unsafe {
			C.memcpy(out, prime_link_prefix.str, prefix_size)
			C.memcpy(out + prefix_size, &name.bytes[0], name_size)
		}
		return prefix_size + name_size
	}
	return none
}

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
