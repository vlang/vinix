// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct MultiPoolGrowthBatch {
mut:
	count int
	pools [64]u32
	slots [64]u32
	lengths [64]u64
}

// Each existing row grows only in its own pool member. Keep the entire set
// private until every request succeeds, including interleaved repeated pools.
@[direct_array_access]
fn bundle_multi_pool_grow_batch(mut set PlanSet, batch &MultiPoolGrowthBatch,
	mut results PoolGrowthResults) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	mut slots := u64(0)
	for i in 0 .. batch.count {
		if batch.pools[i] >= 64 || batch.slots[i] >= 64 || batch.lengths[i] == 0 { return false }
		bit := u64(1) << batch.slots[i]
		if slots & bit != 0 { plan_error(c'multi-pool growth repeats a global mapping slot'); return false }
		slots |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &PoolGrowthResults(C.alloca(sizeof(PoolGrowthResults))) }
	mut one := unsafe { &PoolGrowthBatch(C.alloca(sizeof(PoolGrowthBatch))) }
	unsafe { *candidate = set; *outcome = PoolGrowthResults{count: batch.count}; *one = PoolGrowthBatch{count: 1} }
	for i in 0 .. batch.count {
		one.slots[0] = batch.slots[i]; one.lengths[0] = batch.lengths[i]
		mut chosen := PoolGrowthResults{}
		if !bundle_pool_grow_batch(mut candidate, batch.pools[i], one, mut chosen) { return false }
		outcome.disks[i] = chosen.disks[0]; outcome.rows[i] = chosen.rows[0]; outcome.previous[i] = chosen.previous[0]
	}
	set = unsafe { *candidate }; results = unsafe { *outcome }; return true
}

@[direct_array_access]
fn grow_multi_pool_batch_plan(path &char, batch &MultiPoolGrowthBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &PoolGrowthResults(C.alloca(sizeof(PoolGrowthResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = PoolGrowthResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_multi_pool_grow_batch(mut set, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-multi-growth') } } else { unsafe { &char(c'planned-multi-growth') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', results.count, operation) >= 0
	for i in 0 .. results.count {
		row := results.rows[i]
		action := if row.length == results.previous[i] { unsafe { &char(c'keep') } } else { unsafe { &char(c'grow') } }
		if C.printf(c'request=%d pool=%u disk=%u slot=%u action=%s offset=%lu previous_bytes=%lu bytes=%lu readonly=%lu\n',
			i, batch.pools[i], results.disks[i], row.slot, action, row.offset, results.previous[i], row.length, row.flags) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
