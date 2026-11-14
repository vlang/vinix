// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

fn C.renameat(int, &char, int, &char) int

const builtin_stage_name = '.vinix-builtin-next'

fn builtin_stage(parent int) !string {
	mut buffer := [4097]u8{}
	n := C.readlinkat(parent, builtin_stage_name.str, &char(&buffer[0]), 4096)
	if n < 0 && C.errno == C.ENOENT { return '' }
	if n < 1 || n >= 4096 { return error('Wine migration stage must be a bounded symlink; preserve it for inspection') }
	return unsafe { tos(&buffer[0], int(n)) }.clone()
}

fn sync_binding_directory(parent int) ! {
	fd := C.openat(parent, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot capture Wine migration directory for synchronization') }
	defer { C.close(fd) }
	if C.fsync(fd) != 0 { return error('cannot synchronize Wine migration; recapture before retrying') }
}

// Requires authenticated inputs, a retained generation lease and exclusive
// cooperation of prefix writers. The launch guard does not exclude arbitrary
// same-account filesystem writes. Atomic rename replaces only a freshly checked
// old link under that cooperation assumption. A crash leaves old/new links and
// possibly a signed-target stage; fresh capture resumes, never rolling back or
// deleting unknown data. This is not an atomic multi-link transaction.
pub fn (mut capture IdleBindingReview) migrate_bindings() ! {
	capture.recheck()!
	staged := builtin_stage(capture.guard.directory)!
	defer { unsafe { staged.free() } }
	if staged != '' && !capture.review.bindings.any(it.operation == .replace && it.replacement == staged) {
		return error('Wine migration stage does not match a pending binding; preserve it for inspection')
	}
	mut pending := []int{cap: capture.review.bindings.len}
	defer { unsafe { pending.free() } }
	for index, entry in capture.review.bindings {
		if entry.operation == .replace && entry.replacement == staged { pending << index }
	}
	for index, entry in capture.review.bindings {
		if entry.operation == .replace && entry.replacement != staged { pending << index }
	}
	for index in pending {
		capture.recheck_migration_binding(index)!
		entry := capture.review.bindings[index]
		if C.symlinkat(entry.replacement.str, capture.guard.directory, builtin_stage_name.str) != 0 && C.errno != C.EEXIST {
			return error('cannot exclusively stage Wine builtin migration')
		}
		actual_stage := builtin_stage(capture.guard.directory)!
		defer { unsafe { actual_stage.free() } }
		if actual_stage != entry.replacement { return error('Wine migration stage target differs; preserve it for inspection') }
		sync_binding_directory(capture.guard.directory)!
		capture.recheck_migration_binding(index)!
		final_stage := builtin_stage(capture.guard.directory)!
		defer { unsafe { final_stage.free() } }
		if final_stage != entry.replacement { return error('Wine migration stage changed before rename; preserve it for inspection') }
		if C.renameat(capture.guard.directory, builtin_stage_name.str, capture.system_fd, entry.name.str) != 0 {
			return error('cannot replace staged Wine builtin link; recapture before retrying')
		}
		unsafe { entry.observed.free() }
		capture.review.bindings[index] = BuiltinBinding{operation: .keep, name: entry.name,
			observed: entry.replacement.clone(), replacement: entry.replacement}
		if !capture.review.bindings.any(it.operation == .replace) { capture.review.prior_generation = 0 }
		sync_binding_directory(capture.system_fd)!
		sync_binding_directory(capture.guard.directory)!
	}
	capture.complete_additions()!
	sync_binding_directory(capture.guard.directory)!
}
