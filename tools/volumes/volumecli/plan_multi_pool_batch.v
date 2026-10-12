// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct MultiPoolBatch {
mut:
	count int
	pools [64]u32
	rows [64]Request
}

// Keep the complete transaction private. Each request follows its own pool's
// saved member priority, and earlier placements occupy space for later requests.
@[direct_array_access]
fn bundle_multi_pool_batch(mut set PlanSet, batch &MultiPoolBatch, mut placements PoolPlacements) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	mut slots := u64(0)
	for i in 0 .. batch.count {
		row := batch.rows[i]
		if batch.pools[i] >= 64 || row.version != 1 || row.slot >= 64 || row.offset != 0 || row.length == 0 || row.flags > 1 {
			plan_error(c'invalid multi-pool allocation request'); return false
		}
		bit := u64(1) << row.slot
		if slots & bit != 0 { plan_error(c'multi-pool allocation repeats a global mapping slot'); return false }
		slots |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut result := unsafe { &PoolPlacements(C.alloca(sizeof(PoolPlacements))) }
	mut one := unsafe { &PoolBatch(C.alloca(sizeof(PoolBatch))) }
	unsafe { *candidate = set; *result = PoolPlacements{count: batch.count}; *one = PoolBatch{count: 1} }
	for i in 0 .. batch.count {
		// Reuse the established single-pool placement/keep rules against the
		// private complete state. A failed subrequest cannot escape this scope.
		one.rows[0] = batch.rows[i]
		mut chosen := PoolPlacements{}
		if !bundle_pool_batch(mut candidate, batch.pools[i], one, mut chosen) { return false }
		result.rows[i] = chosen.rows[0]; result.disks[i] = chosen.disks[0]
		if chosen.keep != 0 { result.keep |= u64(1) << i }
	}
	set = unsafe { *candidate }; placements = unsafe { *result }; return true
}

@[direct_array_access]
fn multi_pool_batch_plan(path &char, batch &MultiPoolBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut result := unsafe { &PoolPlacements(C.alloca(sizeof(PoolPlacements))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *result = PoolPlacements{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_multi_pool_batch(mut set, batch, mut result) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-multi-pool') } } else { unsafe { &char(c'planned-multi-pool') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', result.count, operation) >= 0
	for i in 0 .. result.count {
		row := result.rows[i]
		action := if result.keep & (u64(1) << i) != 0 { unsafe { &char(c'keep') } } else { unsafe { &char(c'allocate') } }
		if C.printf(c'request=%d pool=%u disk=%u slot=%u action=%s offset=%lu bytes=%lu readonly=%lu\n',
			i, batch.pools[i], result.disks[i], row.slot, action, row.offset, row.length, row.flags) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
