// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct MappingGrowthBatch {
mut:
	count int
	keys [64]DiskKey // Stable identity selectors; saved geometry is authoritative.
	slots [64]u32
	lengths [64]u64
}

struct MappingGrowthResults {
mut:
	count int
	disks [64]u32
	rows [64]Request
	previous [64]u64
}

// Grow existing desired extents in place without constraining them to a pool.
// A private complete candidate prevents a later failure from keeping a prefix.
@[direct_array_access]
fn bundle_grow_batch(mut set PlanSet, batch &MappingGrowthBatch,
	mut results MappingGrowthResults) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	for disk in 0 .. set.count {
		for previous in 0 .. disk {
			if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &set.plans[previous].key }) {
				plan_error(c'growth bundle has ambiguous disk identities'); return false
			}
		}
	}
	mut seen := u64(0)
	for i in 0 .. batch.count {
		if !forget_identity_valid(unsafe { &batch.keys[i] }) || batch.slots[i] >= 64 || batch.lengths[i] == 0 {
			plan_error(c'invalid mapping growth request'); return false
		}
		bit := u64(1) << batch.slots[i]
		if seen & bit != 0 { plan_error(c'growth batch repeats a mapping slot'); return false }
		seen |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &MappingGrowthResults(C.alloca(sizeof(MappingGrowthResults))) }
	unsafe { *candidate = set; *outcome = MappingGrowthResults{count: batch.count} }
	for i in 0 .. batch.count {
		mut found := false
		for disk in 0 .. set.count {
			for at := u32(0); at < set.plans[disk].count; at++ {
				row := set.plans[disk].rows[at]
				if row.slot != batch.slots[i] { continue }
				if !enrollment_identity_matches(unsafe { &batch.keys[i] }, unsafe { &set.plans[disk].key }) {
					plan_error(c'growth slot belongs to a different disk identity'); return false
				}
				if !bundle_grow_row(mut candidate, row.slot, batch.lengths[i]) { return false }
				outcome.disks[i] = u32(disk); outcome.previous[i] = row.length
				outcome.rows[i] = row; outcome.rows[i].length = batch.lengths[i]; found = true
			}
		}
		if !found { plan_error(c'planned growth mapping slot is absent'); return false }
	}
	set = unsafe { *candidate }; results = unsafe { *outcome }
	return true
}

// Equal-size retries still publish and complete both durability barriers.
// Keep the pinned directory writer lock through report flushing and cleanup.
@[direct_array_access]
fn grow_batch_bundle_plan(path &char, batch &MappingGrowthBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &MappingGrowthResults(C.alloca(sizeof(MappingGrowthResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = MappingGrowthResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_grow_batch(mut set, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-explicit-growth') } } else { unsafe { &char(c'planned-explicit-growth') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', results.count, operation) >= 0
	for i in 0 .. results.count {
		row := results.rows[i]; mut identity := [41]char{}
		disk_identity(unsafe { &batch.keys[i] }, &identity[0])
		action := if row.length == results.previous[i] { unsafe { &char(c'keep') } } else { unsafe { &char(c'grow') } }
		if C.printf(c'request=%d disk=%u slot=%u action=%s offset=%lu previous_bytes=%lu bytes=%lu readonly=%lu identity=%s\n',
			i, results.disks[i], row.slot, action, row.offset, results.previous[i], row.length, row.flags, &identity[0]) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
