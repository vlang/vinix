// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Import an existing single-disk snapshot without resnapshotting the other
// desired mappings. Both readable inputs stay open through atomic publication.
fn enroll_bundle_disk(path &char, source &char) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 {
		C.perror(c'vinix-volume: open bundle')
		return 1
	}
	defer { C.close(fd) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut plan := unsafe { &Plan(C.alloca(sizeof(Plan))) }
	unsafe {
		*set = PlanSet{}
		*plan = Plan{}
	}
	if !read_bundle(fd, mut set, false) { return 1 }
	input := C.open(source, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if input < 0 {
		C.perror(c'vinix-volume: open enrollment plan')
		return 1
	}
	defer { C.close(input) }
	if !read_plan(input, mut plan, false) || !bundle_enroll_disk(mut set, plan)
		|| !publish_bundle(path, set) {
		return 1
	}
	return finish_bundle_report(C.printf(c'planned enrollment disk=%u mappings=%u\n',
		u32(set.count - 1), plan.count) >= 0)
}

fn forget_bundle_disk(path &char, disk int) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 {
		C.perror(c'vinix-volume: open bundle')
		return 1
	}
	defer { C.close(fd) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe {
		*set = PlanSet{}
	}
	if !read_bundle(fd, mut set, false) || !bundle_forget_disk(mut set, disk)
		|| !publish_bundle(path, set) {
		return 1
	}
	return finish_bundle_report(C.printf(c'planned disk removal disk=%u remaining=%u\n', u32(disk),
		u32(set.count)) >= 0)
}

fn bundle_enroll_disk(mut set PlanSet, plan &Plan) bool {
	if !bundle_set_valid(unsafe { &set }) {
		plan_error(c'invalid enrollment bundle')
		return false
	}
	// append_plan validates the complete candidate and global identity/slot
	// ownership before changing any count, bitmap or inactive destination row.
	return append_plan(mut set, plan)
}

@[direct_array_access]
fn bundle_forget_disk(mut set PlanSet, disk int) bool {
	if !bundle_set_valid(unsafe { &set }) || disk < 0 || disk >= set.count {
		plan_error(c'invalid bundle or absent disk')
		return false
	}
	if set.count == 1 || set.plans[disk].count != 0 {
		plan_error(c'only an empty disk can be removed, and one enrolled disk must remain')
		return false
	}
	for next := disk + 1; next < set.count; next++ {
		set.plans[next - 1] = set.plans[next]
	}
	set.count--
	set.plans[set.count] = Plan{}
	// Empty participants own no slots. All remaining keys, rows and bits survive.
	return true
}
