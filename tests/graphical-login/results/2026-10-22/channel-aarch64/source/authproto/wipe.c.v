// SPDX-License-Identifier: GPL-2.0-or-later
module authproto

#include <string.h>
$if macos {
	fn C.memset_s(voidptr, usize, int, usize) int
} $else {
	fn C.explicit_bzero(voidptr, usize)
}

// Use the platform's non-elidable erase before returning secret storage to
// its allocator. An ordinary zeroing loop can disappear before a free.
fn wipe_bytes(data voidptr, length int) {
	if length == 0 { return }
	$if macos { C.memset_s(data, usize(length), 0, usize(length)) }
	$else { C.explicit_bzero(data, usize(length)) }
}
