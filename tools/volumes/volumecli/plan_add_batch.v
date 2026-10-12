// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct MappingAdditionBatch {
mut:
	count int
	keys [64]DiskKey // Identity selectors; saved geometry remains authoritative.
	rows [64]Request
}

struct MappingAdditionResults {
mut:
	count int
	keep u64
	disks [64]u32
}

// Resolve stable identities before adding explicit extents to a private set.
// Existing slots are retries only when disk identity and every row field match.
@[direct_array_access]
fn bundle_add_batch(mut set PlanSet, batch &MappingAdditionBatch,
	mut results MappingAdditionResults) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	for disk in 0 .. set.count {
		for previous in 0 .. disk {
			if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &set.plans[previous].key }) {
				plan_error(c'addition bundle has ambiguous disk identities'); return false
			}
		}
	}
	mut seen := u64(0)
	for i in 0 .. batch.count {
		row := batch.rows[i]
		if !forget_identity_valid(unsafe { &batch.keys[i] }) || row.version != 1 || row.slot >= 64
			|| row.length == 0 || row.flags > 1 {
			plan_error(c'invalid mapping addition request'); return false
		}
		bit := u64(1) << row.slot
		if seen & bit != 0 { plan_error(c'addition batch repeats a mapping slot'); return false }
		seen |= bit
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &MappingAdditionResults(C.alloca(sizeof(MappingAdditionResults))) }
	unsafe { *candidate = set; *outcome = MappingAdditionResults{count: batch.count} }
	for i in 0 .. batch.count {
		mut target := -1
		for disk in 0 .. set.count {
			if enrollment_identity_matches(unsafe { &batch.keys[i] }, unsafe { &set.plans[disk].key }) { target = disk; break }
		}
		if target < 0 { plan_error(c'addition disk identity is not enrolled'); return false }
		outcome.disks[i] = u32(target)
		mut found := false
		for disk in 0 .. set.count {
			for at := u32(0); at < set.plans[disk].count; at++ {
				row := set.plans[disk].rows[at]
				if row.slot != batch.rows[i].slot { continue }
				if disk != target || row != batch.rows[i] {
					plan_error(c'owned addition slot must match disk identity and every saved row field'); return false
				}
				found = true; outcome.keep |= u64(1) << i
			}
		}
		if !found && !bundle_add_row(mut candidate, target, unsafe { &batch.rows[i] }) { return false }
	}
	set = unsafe { *candidate }; results = unsafe { *outcome }
	return true
}

// Offline explicit placement does not allocate through or edit pool metadata.
// Publication and all-keep retries retain the directory lock through flushing.
@[direct_array_access]
fn add_batch_bundle_plan(path &char, batch &MappingAdditionBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &MappingAdditionResults(C.alloca(sizeof(MappingAdditionResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = MappingAdditionResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_add_batch(mut set, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-addition') } } else { unsafe { &char(c'planned-addition') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', batch.count, operation) >= 0
	for i in 0 .. batch.count {
		row := batch.rows[i]; mut identity := [41]char{}
		disk_identity(unsafe { &batch.keys[i] }, &identity[0])
		action := if results.keep & (u64(1) << i) != 0 { unsafe { &char(c'keep') } } else { unsafe { &char(c'add') } }
		if C.printf(c'request=%d disk=%u slot=%u action=%s offset=%lu bytes=%lu readonly=%lu identity=%s\n',
			i, results.disks[i], row.slot, action, row.offset, row.length, row.flags, &identity[0]) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
