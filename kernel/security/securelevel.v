// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module security

import errno
import proc

// OpenBSD's securelevel(7), kern.securelevel here at
// /proc/sys/kernel/securelevel:
//
// -1  permanently insecure: as 0, and init will not raise it.
//  0  insecure: no more than the usual permissions apply.
//  1  secure: a set immutable or append-only bit cannot be cleared, even by
//     root, so a sealed file stays sealed as long as the machine is multi-user.
//  2  highly secure: as 1 for now. OpenBSD also stops writes to a mounted
//     disk here; Vinix does not raise a disk that way yet.
//
// It can always be raised. Once it is above 0, only init, pid 1, can lower
// it, as OpenBSD's init does on its way to single-user mode. At 0 or -1 it
// can be set to -1. Root with CAP_SYS_ADMIN sets it, as it does the hostname,
// so that a container's root cannot.
//
// One aligned word, read and written whole on both architectures.
__global (
	current_securelevel i32
)

pub const lowest_securelevel = -1
pub const highest_securelevel = 2

pub fn securelevel() int {
	return int(current_securelevel)
}

// sysctl kern.securelevel=`level`, by the calling process.
pub fn set_securelevel(level int) ? {
	if level < lowest_securelevel || level > highest_securelevel {
		errno.set(errno.einval)
		return none
	}
	if !permitted(system_securelevel_set) {
		errno.set(errno.eperm)
		return none
	}
	current := securelevel()
	if current > 0 && level < current && proc.current_thread().process.pid != 1 {
		errno.set(errno.eperm)
		return none
	}
	current_securelevel = i32(level)
}
