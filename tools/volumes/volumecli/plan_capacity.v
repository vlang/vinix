// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Compare the persistent identifier without relaxing normal restore's exact
// geometry check. Capacity adoption is an explicit, separately verified step.
@[direct_array_access]
fn capacity_identifier_matches(a &DiskKey, b &DiskKey) bool {
	if a.kind != b.kind { return false }
	for i in 0 .. 16 { if a.id[i] != b.id[i] { return false } }
	return true
}

// Preserve desired rows, including unapplied edits, rather than resnapshotting
// live mappings. Failed adoption leaves every field of the set unchanged.
@[direct_array_access]
fn bundle_adopt_capacity(mut set PlanSet, disk int, key &DiskKey, expected u64) bool {
	if !bundle_set_valid(unsafe { &set }) || disk < 0 || disk >= set.count || !key_valid(key) {
		plan_error(c'invalid bundle, disk index or observed disk geometry')
		return false
	}
	previous := set.plans[disk].key.bytes
	if key.bytes != expected || key.bytes < previous || key.sector != set.plans[disk].key.sector
		|| !capacity_identifier_matches(key, unsafe { &set.plans[disk].key }) {
		plan_error(c'capacity adoption requires the same disk identifier and sector size, no shrink, and the exact expected size')
		return false
	}
	for i in 0 .. set.count {
		if i != disk && capacity_identifier_matches(key, unsafe { &set.plans[i].key }) {
			plan_error(c'capacity adoption has an ambiguous enrolled disk identifier')
			return false
		}
	}
	set.plans[disk].key.bytes = key.bytes
	if !bundle_set_valid(unsafe { &set }) {
		set.plans[disk].key.bytes = previous
		plan_error(c'capacity adoption would invalidate the complete bundle')
		return false
	}
	return true
}

// The named physical disk is opened read-only once and retained through
// publication. Probe it twice to reject identity/geometry changes during work.
@[direct_array_access]
fn capacity_bundle_plan(path &char, disk int, device &char, expected u64) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	unsafe { *edit = PlanEdit{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, true) { return 1 }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut key := unsafe { &DiskKey(C.alloca(sizeof(DiskKey))) }
	mut after := unsafe { &DiskKey(C.alloca(sizeof(DiskKey))) }
	unsafe {
		*set = PlanSet{}
		*key = DiskKey{}
		*after = DiskKey{}
	}
	if !read_bundle(edit.source, mut set, false) { return 1 }
	if disk < 0 || disk >= set.count || expected < set.plans[disk].key.bytes
		|| expected % set.plans[disk].key.sector != 0 {
		return plan_error(c'absent disk, shrinking or unaligned expected capacity')
	}
	previous := set.plans[disk].key.bytes
	target := C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if target < 0 {
		C.perror(c'vinix-volume: open capacity disk')
		return 1
	}
	defer { C.close(target) }
	mut parent := Status{}
	if !probe_disk(target, mut key, mut parent)
		|| !bundle_adopt_capacity(mut set, disk, key, expected) {
		return 1
	}
	mut status := Status{}
	if !probe_disk(target, mut after, mut status) || !key_matches(key, after)
		|| status.disk_id != parent.disk_id {
		return plan_error(c'disk identity or geometry changed before capacity publication')
	}
	// Republish even an unchanged size: retrying after a prior directory-flush
	// failure must complete the durability protocol before reporting success.
	if !publish_edit_bundle(edit, set) { return 1 }
	return finish_bundle_report(C.printf(c'planned capacity disk=%u previous_bytes=%lu bytes=%lu changed=%u\n',
		u32(disk), previous, expected, u32(previous != expected)) >= 0)
}
