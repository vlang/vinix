// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Only the saved configuration changes. Devices are opened by a later check
// or restore, and omitted entries never request live removal during replay.
fn edit_bundle_plan(path &char, disk int, row &Request, remove bool) i32 {
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
	// Keep the descriptor alive through publication, as capacity planning does.
	if !read_bundle(fd, mut set, false) { return 1 }
	changed := if remove {
		bundle_remove_row(mut set, row.slot)
	} else {
		bundle_add_row(mut set, disk, row)
	}
	if !changed || !publish_bundle(path, set) { return 1 }
	if remove {
		return finish_bundle_report(C.printf(c'planned removal slot=%u\n', row.slot) >= 0)
	}
	return finish_bundle_report(C.printf(c'planned addition disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu\n',
		u32(disk), row.slot, row.offset, row.length, row.flags) >= 0)
}

@[direct_array_access]
fn bundle_add_row(mut set PlanSet, disk int, row &Request) bool {
	if !bundle_set_valid(unsafe { &set }) || disk < 0 || disk >= set.count || row.slot >= 64
		|| set.plans[disk].count >= 64 {
		plan_error(c'invalid planned addition or absent disk')
		return false
	}
	at := set.plans[disk].count
	previous := set.plans[disk].rows[at]
	set.plans[disk].rows[at] = unsafe { *row }
	set.plans[disk].count++
	if !bundle_set_valid(unsafe { &set }) {
		set.plans[disk].count--
		set.plans[disk].rows[at] = previous
		plan_error(c'planned addition has invalid geometry, overlapping extents or a duplicate slot')
		return false
	}
	set.slots |= u64(1) << row.slot
	return true
}

@[direct_array_access]
fn bundle_remove_row(mut set PlanSet, slot u32) bool {
	if slot >= 64 || !bundle_set_valid(unsafe { &set }) {
		plan_error(c'invalid bundle or mapping slot')
		return false
	}
	for disk in 0 .. set.count {
		for at := u32(0); at < set.plans[disk].count; at++ {
			if set.plans[disk].rows[at].slot != slot { continue
			 }
			// Removing a row from a validated set preserves geometry and identity.
			for next := at + 1; next < set.plans[disk].count; next++ {
				set.plans[disk].rows[next - 1] = set.plans[disk].rows[next]
			}
			set.plans[disk].count--
			set.plans[disk].rows[set.plans[disk].count] = Request{}
			set.slots &= ~(u64(1) << slot)
			return true
		}
	}
	plan_error(c'planned mapping slot is absent')
	return false
}
