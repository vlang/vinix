// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct MappingRemovalBatch {
mut:
	count int
	slots [64]u32
}

struct MappingRemovalResults {
mut:
	count int
	removed u64
	disks [64]u32
	rows [64]Request
}

// Remove desired rows only. Missing slots are idempotent retries; duplicate
// requests are errors. No caller state or results change on a later failure.
@[direct_array_access]
fn bundle_remove_batch(mut set PlanSet, batch &MappingRemovalBatch,
	mut results MappingRemovalResults) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	mut seen := u64(0)
	for i in 0 .. batch.count {
		slot := batch.slots[i]
		if slot >= 64 { plan_error(c'invalid mapping removal slot'); return false }
		bit := u64(1) << slot
		if seen & bit != 0 { plan_error(c'mapping removal batch repeats a slot'); return false }
		seen |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &MappingRemovalResults(C.alloca(sizeof(MappingRemovalResults))) }
	unsafe { *candidate = set; *outcome = MappingRemovalResults{count: batch.count} }
	for i in 0 .. batch.count {
		slot := batch.slots[i]
		for disk in 0 .. set.count {
			for at := u32(0); at < set.plans[disk].count; at++ {
				row := set.plans[disk].rows[at]
				if row.slot != slot { continue }
				outcome.disks[i] = u32(disk); outcome.rows[i] = row
				outcome.removed |= u64(1) << i
			}
		}
		if outcome.removed & (u64(1) << i) != 0 && !bundle_remove_row(mut candidate, slot) { return false }
	}
	set = unsafe { *candidate }
	results = unsafe { *outcome }
	return true
}

// Keep the pinned directory lock through publication and report flushing.
// Every publication, including an all-absent retry, completes both fsyncs.
@[direct_array_access]
fn remove_batch_bundle_plan(path &char, batch &MappingRemovalBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &MappingRemovalResults(C.alloca(sizeof(MappingRemovalResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = MappingRemovalResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_remove_batch(mut set, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-removal') } } else { unsafe { &char(c'planned-removal') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', results.count, operation) >= 0
	for i in 0 .. results.count {
		if results.removed & (u64(1) << i) == 0 {
			if C.printf(c'request=%d slot=%u action=keep\n', i, batch.slots[i]) < 0 { ok = false }
		} else {
			row := results.rows[i]
			if C.printf(c'request=%d disk=%u slot=%u action=remove offset=%lu bytes=%lu readonly=%lu\n',
				i, results.disks[i], row.slot, row.offset, row.length, row.flags) < 0 { ok = false }
		}
	}
	return finish_bundle_report(ok)
}
