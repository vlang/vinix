@[has_globals]
module net

import errno

const hostname_len = 64

__global (
	hostname [hostname_len]char
)

pub fn syscall_gethostname(_ voidptr, name charptr, len u64) (u64, u64) {
	real_len := unsafe { C.strlen(&hostname[0]) }

	if len < real_len {
		return errno.err, errno.enametoolong
	}

	unsafe { C.memcpy(name, &hostname[0], real_len + 1) }
	return 0, 0
}

pub fn syscall_sethostname(_ voidptr, name charptr, len u64) (u64, u64) {
	if len > hostname_len - 1 {
		return errno.err, errno.einval
	}

	unsafe { C.memcpy(&hostname[0], name, len) }
	hostname[len] = char(`\0`)

	return 0, 0
}
