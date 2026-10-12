// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct DiskEnrollmentBatch {
mut:
	count int
	plans [64]Plan
}

struct DiskEnrollmentResults {
mut:
	count int
	added u64
	disks [64]u32
}

@[direct_array_access]
fn enrollment_identity_matches(a &DiskKey, b &DiskKey) bool {
	if a.kind != b.kind { return false }
	for i in 0 .. 16 { if a.id[i] != b.id[i] { return false } }
	return true
}

@[direct_array_access]
fn enrollment_plan_matches(a &Plan, b &Plan) bool {
	if !key_matches(unsafe { &a.key }, unsafe { &b.key }) || a.count != b.count { return false }
	for i := u32(0); i < a.count; i++ { if a.rows[i] != b.rows[i] { return false } }
	return true
}

// Existing identities are retries only when all saved geometry/rows match.
// New disks append in request order; later failures leave all caller fields intact.
@[direct_array_access]
fn bundle_enroll_batch(mut set PlanSet, batch &DiskEnrollmentBatch,
	mut results DiskEnrollmentResults) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(unsafe { &set }) { return false }
	for disk in 0 .. set.count {
		for previous in 0 .. disk {
			if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &set.plans[previous].key }) {
				plan_error(c'enrollment bundle has ambiguous disk identities'); return false
			}
		}
	}
	for i in 0 .. batch.count {
		if !plan_valid(unsafe { &batch.plans[i] }) { plan_error(c'invalid enrollment batch plan'); return false }
		for previous in 0 .. i {
			if enrollment_identity_matches(unsafe { &batch.plans[i].key }, unsafe { &batch.plans[previous].key }) {
				plan_error(c'enrollment batch repeats a disk identity'); return false
			}
		}
	}
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &DiskEnrollmentResults(C.alloca(sizeof(DiskEnrollmentResults))) }
	unsafe { *candidate = set; *outcome = DiskEnrollmentResults{count: batch.count} }
	for i in 0 .. batch.count {
		plan := unsafe { &batch.plans[i] }
		mut existing := -1
		for disk in 0 .. set.count {
			if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &plan.key }) { existing = disk; break }
		}
		if existing >= 0 {
			if !enrollment_plan_matches(unsafe { &set.plans[existing] }, plan) {
				plan_error(c'enrolled identity must match all saved geometry and mapping rows'); return false
			}
			outcome.disks[i] = u32(existing)
		} else {
			outcome.disks[i] = u32(candidate.count)
			if !append_plan(mut candidate, plan) { return false }
			outcome.added |= u64(1) << i
		}
	}
	set = unsafe { *candidate }; results = unsafe { *outcome }
	return true
}

// Recheck the retained source inode, never its replaceable path. This detects
// source edits observed before the final read; administration still serializes edits.
@[direct_array_access]
fn enrollment_source_unchanged(fd i32, plan &Plan) bool {
	mut expected := [2112]u8{}; mut current := [2112]u8{}
	size := encode_plan(plan, &expected[0])
	mut info := C.stat{}
	if size == 0 || C.fstat(fd, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size != size { return false }
	mut done := i64(0)
	for done < size {
		count := C.pread(fd, unsafe { &current[done] }, usize(i64(size) - done), done)
		if count < 0 && unsafe { C.errno == C.EINTR } { continue }
		if count <= 0 { return false }; done += count
	}
	for i in 0 .. size { if current[i] != expected[i] { return false } }
	mut extra := u8(0)
	for {
		count := C.pread(fd, &extra, 1, i64(size))
		if count < 0 && unsafe { C.errno == C.EINTR } { continue }
		return count == 0
	}
	return false
}

@[direct_array_access]
fn enroll_batch_bundle_plan(path &char, count int, sources &&char, preview bool) i32 {
	if count < 1 || count > 64 { return usage() }
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut batch := unsafe { &DiskEnrollmentBatch(C.alloca(sizeof(DiskEnrollmentBatch))) }
	mut results := unsafe { &DiskEnrollmentResults(C.alloca(sizeof(DiskEnrollmentResults))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *batch = DiskEnrollmentBatch{count: count}; *results = DiskEnrollmentResults{} }
	defer { close_plan_edit(mut edit) }
	mut fds := [64]i32{}; mut opened := 0
	defer { for i in 0 .. opened { C.close(fds[i]) } }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false) { return 1 }
	for i in 0 .. count {
		fd := C.open(unsafe { sources[i] }, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
		if fd < 0 { C.perror(c'vinix-volume: open enrollment batch plan'); return 1 }
		fds[i] = fd; opened++
		if !read_plan(fd, mut batch.plans[i], false) { return 1 }
	}
	if !bundle_enroll_batch(mut set, batch, mut results) { return 1 }
	for i in 0 .. count {
		if !enrollment_source_unchanged(fds[i], unsafe { &batch.plans[i] }) {
			plan_error(c'enrollment source changed or could not be rechecked'); return 1
		}
	}
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-enrollment') } } else { unsafe { &char(c'planned-enrollment') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', count, operation) >= 0
	for i in 0 .. count {
		plan := unsafe { &batch.plans[i] }
		mut identity := [41]char{}; disk_identity(unsafe { &plan.key }, &identity[0])
		action := if results.added & (u64(1) << i) != 0 { unsafe { &char(c'add') } } else { unsafe { &char(c'keep') } }
		if C.printf(c'request=%d disk=%u action=%s mappings=%u bytes=%lu sector=%lu identity=%s\n',
			i, results.disks[i], action, plan.count, plan.key.bytes, plan.key.sector, &identity[0]) < 0 { ok = false }
		for at := u32(0); at < plan.count; at++ {
			row := plan.rows[at]
			if C.printf(c'request=%d disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu\n',
				i, results.disks[i], row.slot, row.offset, row.length, row.flags) < 0 { ok = false }
		}
	}
	return finish_bundle_report(ok)
}
