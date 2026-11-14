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
	system_path := capture.data + '/wine/drive_c/windows/system32'
	defer { unsafe { system_path.free() } }
	for index in 0 .. capture.review.bindings.len {
		if capture.review.bindings[index].operation != .create { continue }
		// Full inventory checks bracket the operation. Per-link admission
		// checks the held namespace and target, avoiding a full payload rehash
		// for every missing link. Other concurrent changes refuse at the final
		// full recheck; partial progress remains recoverable via fresh capture.
		capture.server.require_idle(&capture.guard, capture.data)!
		binding_directory_unchanged(capture.system_fd, system_path, true)!
		binding_directory_unchanged(capture.assets_fd, capture.builtins, false)!
		entry := capture.review.bindings[index]
		digest, _ := binding_asset_digest(capture.assets_fd, entry.name)!
		matches := digest == capture.digests[index]
		unsafe { digest.free() }
		if !matches { return error('Wine builtin addition target bytes changed') }
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
