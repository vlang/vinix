// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct PoolContractionBatch {
mut:
	count int
	keys [64]DiskKey
	ends [64]u64
}

struct PoolContractionResults {
mut:
	count int
	rows [64]PoolRegion
	previous [64]u64
}

// Release only the unoccupied tail of existing allocation windows. Explicit
// mappings may cross a window boundary; preserve their occupied intersection.
@[direct_array_access]
fn bundle_pool_contract_batch(mut set PlanSet, pool u32, batch &PoolContractionBatch,
	mut results PoolContractionResults) bool {
	if pool >= 64 || batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	for disk in 0 .. set.count {
		for previous in 0 .. disk {
			if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &set.plans[previous].key }) {
				plan_error(c'contraction bundle has ambiguous disk identities'); return false
			}
		}
	}
	for i in 0 .. batch.count {
		if !forget_identity_valid(unsafe { &batch.keys[i] }) || batch.ends[i] == 0 { return false }
		for previous in 0 .. i {
			if enrollment_identity_matches(unsafe { &batch.keys[i] }, unsafe { &batch.keys[previous] }) {
				plan_error(c'contraction batch repeats a disk identity'); return false
			}
		}
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &PoolContractionResults(C.alloca(sizeof(PoolContractionResults))) }
	unsafe { *candidate = set; *outcome = PoolContractionResults{count: batch.count} }
	for i in 0 .. batch.count {
		mut disk := -1
		for at in 0 .. set.count {
			if enrollment_identity_matches(unsafe { &batch.keys[i] }, unsafe { &set.plans[at].key }) { disk = at; break }
		}
		if disk < 0 { plan_error(c'contraction disk identity is not enrolled'); return false }
		mut found := false
		for at in 0 .. set.regions {
			previous := set.windows[at]
			if previous.pool != pool || previous.disk != u32(disk) { continue }
			end := batch.ends[i]
			if end <= previous.window.start || end > previous.window.end || end % set.plans[disk].key.sector != 0 {
				plan_error(c'contraction must retain a nonempty sector-aligned window and cannot expand it'); return false
			}
			for row := u32(0); row < set.plans[disk].count; row++ {
				mapping := set.plans[disk].rows[row]; mapping_end := mapping.offset + mapping.length
				if mapping.offset >= previous.window.end || mapping_end <= previous.window.start { continue }
				occupied_end := if mapping_end < previous.window.end { mapping_end } else { previous.window.end }
				if end < occupied_end { plan_error(c'contraction would release occupied desired mapping bytes'); return false }
			}
			candidate.windows[at] = PoolRegion{pool: pool, disk: u32(disk), window: SpaceWindow{
				start: previous.window.start, end: end, alignment: previous.window.alignment}}
			outcome.previous[i] = previous.window.end; outcome.rows[i] = candidate.windows[at]; found = true; break
		}
		if !found { plan_error(c'contraction pool member is absent'); return false }
	}
	if !bundle_set_valid(candidate) { return false }
	set = unsafe { *candidate }; results = unsafe { *outcome }; return true
}

// All-keep retries still replace and flush the complete set. Keep the pinned
// directory writer lock until report flushing and descriptor cleanup finish.
@[direct_array_access]
fn contract_batch_pool_plan(path &char, pool u32, batch &PoolContractionBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &PoolContractionResults(C.alloca(sizeof(PoolContractionResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = PoolContractionResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_pool_contract_batch(mut set, pool, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-contraction') } } else { unsafe { &char(c'planned-contraction') } }
	mut ok := C.printf(c'pool=%u requests=%d operation=%s\n', pool, results.count, operation) >= 0
	for i in 0 .. results.count {
		row := results.rows[i]; mut identity := [41]char{}; disk_identity(unsafe { &batch.keys[i] }, &identity[0])
		action := if row.window.end == results.previous[i] { unsafe { &char(c'keep') } } else { unsafe { &char(c'contract') } }
		if C.printf(c'pool=%u request=%d disk=%u action=%s start=%lu previous_end=%lu end=%lu alignment=%lu identity=%s\n',
			pool, i, row.disk, action, row.window.start, results.previous[i], row.window.end, row.window.alignment, &identity[0]) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
