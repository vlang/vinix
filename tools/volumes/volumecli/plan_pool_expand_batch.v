// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct PoolExpansionBatch {
mut:
	count int
	disks [64]u32
	ends [64]u64
}

struct PoolExpansionResults {
mut:
	count int
	rows [64]PoolRegion
	previous [64]u64
}

// Retain the whole original set and caller output until every existing member
// can expand. Capacity adoption and desired mapping growth remain separate.
@[direct_array_access]
fn bundle_pool_expand_batch(mut set PlanSet, pool u32, batch &PoolExpansionBatch,
	mut results PoolExpansionResults) bool {
	if pool >= 64 || batch.count < 1 || batch.count > 64
		|| !bundle_set_valid(unsafe { &set }) { return false }
	mut disks := u64(0)
	for i in 0 .. batch.count {
		if batch.disks[i] >= 64 || batch.ends[i] == 0 { return false }
		bit := u64(1) << batch.disks[i]
		if disks & bit != 0 { plan_error(c'pool expansion batch repeats a disk'); return false }
		disks |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &PoolExpansionResults(C.alloca(sizeof(PoolExpansionResults))) }
	unsafe { *candidate = set; *outcome = PoolExpansionResults{count: batch.count} }
	for i in 0 .. batch.count {
		mut found := false
		for at in 0 .. candidate.regions {
			row := candidate.windows[at]
			if row.pool != pool || row.disk != batch.disks[i] { continue }
			outcome.previous[i] = row.window.end
			if !bundle_pool_expand(mut candidate, pool, row.disk, batch.ends[i]) { return false }
			outcome.rows[i] = candidate.windows[at]
			found = true
		}
		if !found { plan_error(c'pool expansion batch member is absent'); return false }
	}
	set = unsafe { *candidate }
	results = unsafe { *outcome }
	return true
}

// Equal-end retries complete the full durability protocol. Preview uses the
// same planner without a writer lock, temporary file or device probe.
@[direct_array_access]
fn expand_batch_pool_plan(path &char, pool u32, batch &PoolExpansionBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &PoolExpansionResults(C.alloca(sizeof(PoolExpansionResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = PoolExpansionResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_pool_expand_batch(mut set, pool, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-expansion') } } else { unsafe { &char(c'planned-expansion') } }
	mut ok := C.printf(c'pool=%u requests=%d operation=%s\n', pool, results.count, operation) >= 0
	for i in 0 .. results.count {
		row := results.rows[i]
		action := if row.window.end == results.previous[i] { unsafe { &char(c'keep') } } else { unsafe { &char(c'expand') } }
		if C.printf(c'pool=%u request=%d disk=%u action=%s start=%lu previous_end=%lu end=%lu alignment=%lu\n',
			pool, i, row.disk, action, row.window.start, results.previous[i], row.window.end, row.window.alignment) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
