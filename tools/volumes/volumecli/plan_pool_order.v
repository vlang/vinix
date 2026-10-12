// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct PoolOrder {
mut:
	count int
	disks [64]u32
}

struct PoolOrderResults {
mut:
	count int
	previous [64]u32
}

// Require a complete permutation of the selected pool. Only its occupied
// table positions change; unrelated pools and every mapping remain untouched.
@[direct_array_access]
fn bundle_pool_order(mut set PlanSet, pool u32, order &PoolOrder,
	mut results PoolOrderResults) bool {
	if pool >= 64 || order.count < 1 || order.count > 64
		|| !bundle_set_valid(unsafe { &set }) { return false }
	mut positions := [64]int{}
	mut members := 0
	mut expected := u64(0)
	for at in 0 .. set.regions {
		row := set.windows[at]
		if row.pool != pool { continue }
		positions[members] = at; members++
		expected |= u64(1) << row.disk
	}
	if members != order.count { plan_error(c'priority order must list every member of an existing pool'); return false }
	mut seen := u64(0)
	for i in 0 .. order.count {
		disk := order.disks[i]
		if disk >= u32(set.count) { plan_error(c'priority order has an absent disk'); return false }
		bit := u64(1) << disk
		if seen & bit != 0 || expected & bit == 0 { plan_error(c'priority order repeats a disk or selects another pool'); return false }
		seen |= bit
	}
	if seen != expected { return false }
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &PoolOrderResults(C.alloca(sizeof(PoolOrderResults))) }
	unsafe { *candidate = set; *outcome = PoolOrderResults{count: order.count} }
	for i in 0 .. order.count {
		for previous in 0 .. members {
			row := set.windows[positions[previous]]
			if row.disk != order.disks[i] { continue }
			candidate.windows[positions[i]] = row
			outcome.previous[i] = u32(previous)
			break
		}
	}
	set = unsafe { *candidate }
	results = unsafe { *outcome }
	return true
}

@[direct_array_access]
fn order_pool_plan(path &char, pool u32, order &PoolOrder, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &PoolOrderResults(C.alloca(sizeof(PoolOrderResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = PoolOrderResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_pool_order(mut set, pool, order, mut results) { return 1 }
	// All-keep retries still complete both durability flushes and replacement.
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-priority') } } else { unsafe { &char(c'planned-priority') } }
	mut ok := C.printf(c'pool=%u members=%d operation=%s\n', pool, results.count, operation) >= 0
	for i in 0 .. results.count {
		action := if results.previous[i] == u32(i) { unsafe { &char(c'keep') } } else { unsafe { &char(c'move') } }
		if C.printf(c'pool=%u priority=%d disk=%u previous_priority=%u action=%s\n',
			pool, i, order.disks[i], results.previous[i], action) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
