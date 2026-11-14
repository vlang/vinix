// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

fn C.fsync(int) int

// Low-level, single-owner operation. Caller authenticates the inventory and
// retains its generation lease. Each creation is exclusive; interruption may
// leave a subset installed. A fresh capture accepts matching links as keep
// rows and can finish the remainder. Never retarget or delete existing entries.
pub fn (mut capture IdleBindingReview) complete_additions() ! {
	capture.recheck()!
	if capture.review.bindings.any(it.operation == .replace) {
		return error('Wine builtin additions require all existing links to select the current runtime')
	}
	for index in 0 .. capture.review.bindings.len {
		if capture.review.bindings[index].operation != .create { continue }
		capture.recheck()!
		entry := capture.review.bindings[index]
		if C.symlinkat(entry.replacement.str, capture.system_fd, entry.name.str) != 0 {
			return error('cannot exclusively create Wine builtin addition; recapture before retrying')
		}
		capture.review.bindings[index] = BuiltinBinding{operation: .keep, name: entry.name,
			observed: entry.replacement.clone(), replacement: entry.replacement}
	}
	capture.recheck()!
	fd := C.openat(capture.system_fd, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open Wine builtin directory for synchronization; additions may be installed') }
	defer { C.close(fd) }
	if C.fsync(fd) != 0 { return error('cannot synchronize Wine builtin additions; recapture before retrying') }
	capture.recheck()!
}
