// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct PoolGrowthBatch {
mut:
	count int
	slots [64]u32
	lengths [64]u64
}

struct PoolGrowthResults {
mut:
	count int
	disks [64]u32
	rows [64]Request
	previous [64]u64
}

// Publish the private candidate only after every requested existing mapping
// fits its own member. No shrink or relocation can make another request fit.
@[direct_array_access]
fn bundle_pool_grow_batch(mut set PlanSet, pool u32, batch &PoolGrowthBatch,
	mut results PoolGrowthResults) bool {
	if pool >= 64 || batch.count < 1 || batch.count > 64
		|| !bundle_set_valid(unsafe { &set }) { return false }
	mut slots := u64(0)
	for i in 0 .. batch.count {
		if batch.slots[i] >= 64 || batch.lengths[i] == 0 { return false }
		bit := u64(1) << batch.slots[i]
		if slots & bit != 0 { plan_error(c'pool growth batch repeats a mapping slot'); return false }
		slots |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *candidate = set }
	mut outcome := unsafe { &PoolGrowthResults(C.alloca(sizeof(PoolGrowthResults))) }
	unsafe { *outcome = PoolGrowthResults{count: batch.count} }
	for i in 0 .. batch.count {
		mut found := false
		for p in 0 .. candidate.count {
			for at := u32(0); at < candidate.plans[p].count; at++ {
				row := candidate.plans[p].rows[at]
				if row.slot != batch.slots[i] { continue }
				outcome.previous[i] = row.length
				if !bundle_pool_grow(mut candidate, pool, row.slot, batch.lengths[i],
					unsafe { &outcome.disks[i] }) { return false }
				outcome.rows[i] = candidate.plans[p].rows[at]
				found = true
			}
		}
		if !found { plan_error(c'pool growth batch mapping slot is absent'); return false }
	}
	set = unsafe { *candidate }
	results = unsafe { *outcome }
	return true
}

// Equal-size batches still complete publication, including after a failed
// directory flush. The preview uses the same planner without a writer lock.
@[direct_array_access]
fn grow_batch_pool_plan(path &char, pool u32, batch &PoolGrowthBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &PoolGrowthResults(C.alloca(sizeof(PoolGrowthResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = PoolGrowthResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_pool_grow_batch(mut set, pool, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-growth') } } else { unsafe { &char(c'planned-growth') } }
	mut ok := C.printf(c'pool=%u requests=%d operation=%s\n', pool, results.count, operation) >= 0
	for i in 0 .. results.count {
		row := results.rows[i]
		action := if row.length == results.previous[i] { unsafe { &char(c'keep') } } else { unsafe { &char(c'grow') } }
		if C.printf(c'pool=%u request=%d disk=%u slot=%u action=%s offset=%lu previous_bytes=%lu bytes=%lu readonly=%lu\n',
			pool, i, results.disks[i], row.slot, action, row.offset, results.previous[i], row.length, row.flags) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
