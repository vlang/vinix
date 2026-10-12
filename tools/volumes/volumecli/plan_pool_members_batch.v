// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct PoolMembersBatch {
mut:
	count int
	rows [64]PoolRegion
}

struct PoolMembersResults {
mut:
	count int
	changed u64
}

// Existing additions must match exactly. They retain their original priority;
// new members append in request order. Absent removals are durable retries.
// A later failure changes neither the caller's set nor its action results.
@[direct_array_access]
fn bundle_pool_members_batch(mut set PlanSet, pool u32, batch &PoolMembersBatch,
	remove bool, mut results PoolMembersResults) bool {
	if pool >= 64 || batch.count < 1 || batch.count > 64
		|| !bundle_set_valid(unsafe { &set }) { return false }
	mut seen := u64(0)
	for i in 0 .. batch.count {
		row := batch.rows[i]
		if row.pool != pool || row.disk >= u32(set.count)
			|| (!remove && !space_window_valid(row.window)) {
			plan_error(c'invalid pool membership batch request'); return false
		}
		bit := u64(1) << row.disk
		if seen & bit != 0 { plan_error(c'pool membership batch repeats a disk'); return false }
		seen |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &PoolMembersResults(C.alloca(sizeof(PoolMembersResults))) }
	unsafe { *candidate = set; *outcome = PoolMembersResults{count: batch.count} }
	for i in 0 .. batch.count {
		row := batch.rows[i]
		mut found := false
		for at in 0 .. candidate.regions {
			member := candidate.windows[at]
			if member.pool != pool || member.disk != row.disk { continue }
			found = true
			if !remove && member.window != row.window {
				plan_error(c'existing batch member must match its saved bounds and alignment'); return false
			}
			break
		}
		if remove {
			if !found { continue }
			if !bundle_pool_remove(mut candidate, pool, row.disk) { return false }
		} else {
			if found { continue }
			if !bundle_pool_add(mut candidate, unsafe { &batch.rows[i] }) { return false }
		}
		outcome.changed |= u64(1) << i
	}
	set = unsafe { *candidate }
	results = unsafe { *outcome }
	return true
}

// Previews have no writer lock or temporary. Publication, including all-keep
// retries, holds the editor lock through the complete durability/report path.
@[direct_array_access]
fn members_batch_pool_plan(path &char, pool u32, batch &PoolMembersBatch,
	remove bool, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &PoolMembersResults(C.alloca(sizeof(PoolMembersResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = PoolMembersResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_pool_members_batch(mut set, pool, batch, remove, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if remove {
		if preview { unsafe { &char(c'preview-membership-remove') } } else { unsafe { &char(c'planned-membership-remove') } }
	} else {
		if preview { unsafe { &char(c'preview-membership-add') } } else { unsafe { &char(c'planned-membership-add') } }
	}
	mut ok := C.printf(c'pool=%u requests=%d operation=%s\n', pool, results.count, operation) >= 0
	for i in 0 .. results.count {
		row := batch.rows[i]
		action := if results.changed & (u64(1) << i) == 0 { unsafe { &char(c'keep') } }
			else if remove { unsafe { &char(c'remove') } } else { unsafe { &char(c'add') } }
		if remove {
			if C.printf(c'pool=%u request=%d disk=%u action=%s\n', pool, i, row.disk, action) < 0 { ok = false }
		} else if C.printf(c'pool=%u request=%d disk=%u action=%s start=%lu end=%lu alignment=%lu\n',
			pool, i, row.disk, action, row.window.start, row.window.end, row.window.alignment) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
