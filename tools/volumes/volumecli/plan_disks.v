// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Import an existing single-disk snapshot without resnapshotting the other
// desired mappings. Both readable inputs stay open through atomic publication.
fn enroll_bundle_disk(path &char, source &char) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	unsafe { *edit = PlanEdit{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, true) { return 1 }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut plan := unsafe { &Plan(C.alloca(sizeof(Plan))) }
	unsafe {
		*set = PlanSet{}
		*plan = Plan{}
	}
	if !read_bundle(edit.source, mut set, false) { return 1 }
	input := C.open(source, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if input < 0 {
		C.perror(c'vinix-volume: open enrollment plan')
		return 1
	}
	defer { C.close(input) }
	if !read_plan(input, mut plan, false) || !bundle_enroll_disk(mut set, plan)
		|| !publish_edit_bundle(edit, set) {
		return 1
	}
	return finish_bundle_report(C.printf(c'planned enrollment disk=%u mappings=%u\n',
		u32(set.count - 1), plan.count) >= 0)
}

fn forget_bundle_disk(path &char, disk int) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	unsafe { *edit = PlanEdit{} }
	defer { close_plan_edit(mut edit) }
	if !open_plan_edit(path, mut edit, true) { return 1 }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe {
		*set = PlanSet{}
	}
	if !read_bundle(edit.source, mut set, false) || !bundle_forget_disk(mut set, disk)
		|| !publish_edit_bundle(edit, set) {
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
	for i in 0 .. set.regions {
		if set.windows[i].disk == u32(disk) {
			plan_error(c'remove allocation pool membership before forgetting this disk')
			return false
		}
	}
	for next := disk + 1; next < set.count; next++ {
		set.plans[next - 1] = set.plans[next]
	}
	set.count--
	set.plans[set.count] = Plan{}
	for i in 0 .. set.regions {
		if set.windows[i].disk > u32(disk) { set.windows[i].disk-- }
	}
	// Empty participants own no slots. All remaining keys, rows and bits survive.
	return true
}
