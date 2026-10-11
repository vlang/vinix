// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn C.ferror(voidptr) i32

fn finish_bundle_report(printed bool) i32 {
	if !printed || C.fflush(C.stdout) != 0 || C.ferror(C.stdout) != 0 {
		C.perror(c'vinix-volume: bundle output')
		return 1
	}
	return 0
}

// Both commands load the same bounded checksummed format. Offline inspection
// never opens devices; online checking completes shared preflight before rows.
fn inspect_bundle(path &char, online bool, grow bool) i32 {
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
	if !read_bundle(fd, mut set, false) { return 1 }
	if online { return check_plan_set(set, grow) }
	return finish_bundle_report(show_plan_set(set))
}

@[direct_array_access]
fn disk_identity(key &DiskKey, output &char) {
	if key.kind == 1 {
		C.snprintf(output, 41, c'mbr:%08x', u32(get_le(unsafe { &key.id[0] }, 0, 4)))
		return
	}
	C.snprintf(output, 41, c'gpt:')
	order := [3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15]!
	mut at := 4
	for i in 0 .. 16 {
		if i == 4 || i == 6 || i == 8 || i == 10 {
			unsafe {
				output[at] = char(`-`)
			}
			at++
		}
		C.snprintf(unsafe { output + at }, usize(41 - at), c'%02x', u32(key.id[order[i]]))
		at += 2
	}
}

@[direct_array_access]
fn show_plan_set(set &PlanSet) bool {
	mut count := u32(0)
	for disk in 0 .. set.count {
		plan := unsafe { &set.plans[disk] }
		mut identity := [41]char{}
		disk_identity(unsafe { &plan.key }, &identity[0])
		if C.printf(c'disk=%u bytes=%lu sector=%lu identity=%s\n', u32(disk), plan.key.bytes,
			plan.key.sector, &identity[0]) < 0 {
			return false
		}
		for i := u32(0); i < plan.count; i++ {
			row := plan.rows[i]
			if C.printf(c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu\n', u32(disk),
				row.slot, row.offset, row.length, row.flags) < 0 {
				return false
			}
		}
		count += plan.count
	}
	return C.printf(c'disks=%u mappings=%u\n', u32(set.count), count) >= 0
}

@[direct_array_access]
fn restore_action(state &RestoreState, row u32) u32 {
	return if state.grow[row] {
		2
	} else if state.present[row] {
		1
	} else {
		0
	}
}

@[direct_array_access]
fn show_restore_actions(set &PlanSet, state &SetRestore) bool {
	mut counts := [3]u32{}
	for disk in 0 .. set.count {
		plan := unsafe { &set.plans[disk] }
		current := unsafe { &state.states[disk] }
		for i := u32(0); i < plan.count; i++ {
			row := plan.rows[i]
			action := restore_action(current, i)
			name := if action == 2 {
				unsafe { &char(c'grow') }
			} else if action == 1 {
				unsafe { &char(c'keep') }
			} else {
				unsafe { &char(c'create') }
			}
			if C.printf(c'disk=%u slot=%u action=%s offset=%lu current_bytes=%lu planned_bytes=%lu readonly=%lu generation=%lu\n',
				u32(disk), row.slot, name, row.offset, current.previous_bytes[i], row.length,
				row.flags, current.generation[i]) < 0 {
				return false
			}
			counts[action]++
		}
	}
	return C.printf(c'checked disks=%u create=%u keep=%u grow=%u\n', u32(set.count), counts[0],
		counts[1], counts[2]) >= 0
}

fn check_plan_set(set &PlanSet, grow bool) i32 {
	mut state := unsafe { &SetRestore(C.alloca(sizeof(SetRestore))) }
	unsafe {
		*state = SetRestore{}
	}
	defer { close_plan_set(state) }
	if !prepare_plan_set(set, mut state, grow, false) { return 1 }
	return finish_bundle_report(show_restore_actions(set, state))
}
