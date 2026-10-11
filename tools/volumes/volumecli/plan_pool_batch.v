// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct PoolBatch {
mut:
	count int
	rows [64]Request
}

struct PoolPlacements {
mut:
	count int
	rows [64]Request
	disks [64]u32
	keep u64
}

// Work on a private candidate: a later failure changes neither the desired
// set nor the caller's placements. Matching rows make publication retryable.
@[direct_array_access]
fn bundle_pool_batch(mut set PlanSet, pool u32, batch &PoolBatch,
	mut placements PoolPlacements) bool {
	if pool >= 64 || batch.count < 1 || batch.count > 64
		|| !bundle_set_valid(unsafe { &set }) { return false }
	mut slots := u64(0)
	for i in 0 .. batch.count {
		row := batch.rows[i]
		if row.version != 1 || row.slot >= 64 || row.offset != 0
			|| row.length == 0 || row.flags > 1 {
			plan_error(c'invalid pool batch request')
			return false
		}
		bit := u64(1) << row.slot
		if slots & bit != 0 {
			plan_error(c'pool batch repeats a mapping slot')
			return false
		}
		slots |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *candidate = set }
	mut result := PoolPlacements{count: batch.count}
	for i in 0 .. batch.count {
		request := batch.rows[i]
		mut found := false
		for p in 0 .. candidate.count {
			for at := u32(0); at < candidate.plans[p].count; at++ {
				row := candidate.plans[p].rows[at]
				if row.slot != request.slot { continue }
				mut member := false
				for r in 0 .. candidate.regions {
					region := candidate.windows[r]
					if region.pool == pool && region.disk == u32(p)
						&& row.offset >= region.window.start && row.offset < region.window.end
						&& row.length <= region.window.end - row.offset { member = true }
				}
				if !member || row.length != request.length || row.flags != request.flags {
					plan_error(c'owned batch slot must match length, mode and selected pool bounds')
					return false
				}
				result.rows[i] = row
				result.disks[i] = u32(p)
				result.keep |= u64(1) << i
				found = true
			}
		}
		if found { continue }
		if !bundle_pool_allocate(mut candidate, pool, unsafe { &batch.rows[i] },
			unsafe { &result.disks[i] }, mut result.rows[i]) { return false }
	}
	set = unsafe { *candidate }
	placements = result
	return true
}

// Preview follows exactly the same placement and retry rules, without a
// publisher or device open. Reports start only after the whole batch fits.
@[direct_array_access]
fn batch_pool_plan(path &char, pool u32, batch &PoolBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	unsafe { *edit = PlanEdit{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) { return 1 }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	mut placements := PoolPlacements{}
	if !read_bundle(edit.source, mut set, false)
		|| !bundle_pool_batch(mut set, pool, batch, mut placements) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview') } } else { unsafe { &char(c'planned') } }
	mut ok := C.printf(c'pool=%u requests=%d operation=%s\n', pool, placements.count, operation) >= 0
	for i in 0 .. placements.count {
		row := placements.rows[i]
		action := if placements.keep & (u64(1) << i) != 0 { unsafe { &char(c'keep') } } else { unsafe { &char(c'allocate') } }
		if C.printf(c'pool=%u request=%d disk=%u slot=%u action=%s offset=%lu bytes=%lu readonly=%lu\n',
			pool, i, placements.disks[i], row.slot, action, row.offset, row.length, row.flags) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
