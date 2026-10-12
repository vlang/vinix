// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct DiskForgetBatch {
mut:
	count int
	keys [64]DiskKey
}

struct DiskForgetResults {
mut:
	count int
	removed u64
	disks [64]u32
	retained [64]u32 // Original disk index -> new index; absent is u32(-1).
}

@[direct_array_access]
fn forget_identity_valid(key &DiskKey) bool {
	if key.kind != 1 && key.kind != 2 { return false }
	mut nonzero := false
	for i in 0 .. 16 {
		if key.id[i] != 0 { nonzero = true }
		if key.kind == 1 && i >= 4 && key.id[i] != 0 { return false }
	}
	return nonzero
}

fn identity_hex(byte u8) int {
	if byte >= `0` && byte <= `9` { return int(byte - `0`) }
	if byte >= `a` && byte <= `f` { return int(byte - `a`) + 10 }
	if byte >= `A` && byte <= `F` { return int(byte - `A`) + 10 }
	return -1
}

// Accept exactly the MBR/GPT identity spelling emitted by show-bundle.
// Parse into private storage so malformed input never changes the caller.
@[direct_array_access]
fn parse_disk_identity(text &char, mut key DiskKey) bool {
	unsafe {
		mut length := 0
		for length <= 40 && text[length] != 0 { length++ }
		if length != 12 && length != 40 { return false }
		if text[3] != char(`:`) { return false }
		mut candidate := DiskKey{}
		if length == 12 && text[0] == char(`m`) && text[1] == char(`b`) && text[2] == char(`r`) {
			candidate.kind = 1
			for i in 0 .. 4 {
				high := identity_hex(u8(text[4 + i * 2])); low := identity_hex(u8(text[5 + i * 2]))
				if high < 0 || low < 0 { return false }
				candidate.id[3 - i] = u8(high * 16 + low)
			}
		} else if length == 40 && text[0] == char(`g`) && text[1] == char(`p`) && text[2] == char(`t`) {
			candidate.kind = 2
			order := [3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15]!
			mut at := 4
			for i in 0 .. 16 {
				if i == 4 || i == 6 || i == 8 || i == 10 {
					if text[at] != char(`-`) { return false }; at++
				}
				high := identity_hex(u8(text[at])); low := identity_hex(u8(text[at + 1]))
				if high < 0 || low < 0 { return false }
				candidate.id[order[i]] = u8(high * 16 + low); at += 2
			}
		} else { return false }
		if !forget_identity_valid(&candidate) { return false }
		key = candidate
	}
	return true
}

// Resolve every identity against the original set before compacting anything.
// Absent identities are safe retries even after unrelated disk indices shift.
@[direct_array_access]
fn bundle_forget_batch(mut set PlanSet, batch &DiskForgetBatch, mut results DiskForgetResults) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	for disk in 0 .. set.count {
		for previous in 0 .. disk {
			if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &set.plans[previous].key }) {
				plan_error(c'forget bundle has ambiguous disk identities'); return false
			}
		}
	}
	mut outcome := unsafe { &DiskForgetResults(C.alloca(sizeof(DiskForgetResults))) }
	unsafe { *outcome = DiskForgetResults{count: batch.count} }
	mut removed := u64(0); mut removed_count := 0
	for i in 0 .. 64 { outcome.retained[i] = u32(-1); outcome.disks[i] = u32(-1) }
	for i in 0 .. batch.count {
		key := unsafe { &batch.keys[i] }
		if !forget_identity_valid(key) { plan_error(c'invalid forget disk identity'); return false }
		for previous in 0 .. i {
			if enrollment_identity_matches(key, unsafe { &batch.keys[previous] }) {
				plan_error(c'forget batch repeats a disk identity'); return false
			}
		}
		for disk in 0 .. set.count {
			if !enrollment_identity_matches(key, unsafe { &set.plans[disk].key }) { continue }
			if set.plans[disk].count != 0 { plan_error(c'only an empty disk can be forgotten'); return false }
			for at in 0 .. set.regions {
				if set.windows[at].disk == u32(disk) { plan_error(c'remove pool membership before forgetting this disk'); return false }
			}
			removed |= u64(1) << disk; removed_count++
			outcome.removed |= u64(1) << i; outcome.disks[i] = u32(disk)
			break
		}
	}
	if removed_count == set.count { plan_error(c'one enrolled disk must remain'); return false }
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *candidate = set }
	mut retained := 0
	for disk in 0 .. set.count {
		if removed & (u64(1) << disk) != 0 { continue }
		candidate.plans[retained] = set.plans[disk]; outcome.retained[disk] = u32(retained); retained++
	}
	for disk in retained .. set.count { candidate.plans[disk] = Plan{} }
	candidate.count = retained
	for at in 0 .. set.regions { candidate.windows[at].disk = outcome.retained[set.windows[at].disk] }
	set = unsafe { *candidate }; results = unsafe { *outcome }
	return true
}

@[direct_array_access]
fn forget_batch_bundle_plan(path &char, batch &DiskForgetBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut results := unsafe { &DiskForgetResults(C.alloca(sizeof(DiskForgetResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *results = DiskForgetResults{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !bundle_forget_batch(mut set, batch, mut results) { return 1 }
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-forget') } } else { unsafe { &char(c'planned-forget') } }
	mut ok := C.printf(c'requests=%d remaining=%d operation=%s\n', batch.count, set.count, operation) >= 0
	for i in 0 .. batch.count {
		mut identity := [41]char{}; disk_identity(unsafe { &batch.keys[i] }, &identity[0])
		if results.removed & (u64(1) << i) == 0 {
			if C.printf(c'request=%d action=keep identity=%s\n', i, &identity[0]) < 0 { ok = false }
		} else if C.printf(c'request=%d disk=%u action=forget identity=%s\n', i, results.disks[i], &identity[0]) < 0 { ok = false }
	}
	for previous in 0 .. 64 {
		disk := results.retained[previous]
		if disk == u32(-1) { continue }
		mut identity := [41]char{}; disk_identity(unsafe { &set.plans[disk].key }, &identity[0])
		if C.printf(c'previous_disk=%d disk=%u action=retain identity=%s\n', previous, disk, &identity[0]) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
