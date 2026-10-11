// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn C.fcntl(i32, i32, ...voidptr) i32
fn C.strlen(&char) usize

struct PlanSet {
mut:
	count int
	slots u64
	plans [64]Plan
}

struct SetRestore {
mut:
	opened int
	fds [64]i32
	states [64]RestoreState
}

// One plan per disk and one owner per global mapper slot. Check the whole
// addition before publishing it into the in-memory set.
@[direct_array_access]
fn append_plan(mut set PlanSet, plan &Plan) bool {
	if set.count < 0 || set.count >= 64 || !plan_valid(plan) {
		plan_error(c'invalid or excessive plan set'); return false
	}
	for i := 0; i < set.count; i++ {
		if key_matches(unsafe { &set.plans[i].key }, unsafe { &plan.key }) {
			plan_error(c'multiple plans identify the same disk'); return false
		}
	}
	mut slots := set.slots
	for i := u32(0); i < plan.count; i++ {
		bit := u64(1) << plan.rows[i].slot
		if slots & bit != 0 { plan_error(c'plan set has duplicate mapping slots'); return false }
		slots |= bit
	}
	set.plans[set.count] = unsafe { *plan }
	set.count++
	set.slots = slots
	return true
}

fn plan_filename(name &char) bool {
	length := C.strlen(name)
	return length > 5 && unsafe { name[0] != char(`.`) && C.strcmp(&name[length - 5], c'.vmap') == 0 }
}

fn trusted_directory(fd i32, message &char) bool {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || info.st_uid != 0 || info.st_mode & 0o022 != 0 {
		plan_error(message); return false
	}
	return true
}

fn load_relative_plan(directory i32, name &char, mut set PlanSet, trusted bool, optional bool) bool {
	fd := C.openat(directory, name, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 {
		if optional && unsafe { C.errno == C.ENOENT } { return true }
		C.perror(c'vinix-volume: open plan in set'); return false
	}
	defer { C.close(fd) }
	mut plan := unsafe { &Plan(C.alloca(sizeof(Plan))) }
	unsafe { *plan = Plan{} }
	if !read_plan(fd, mut plan, trusted) || !append_plan(mut set, plan) {
		C.printf(c'vinix-volume: rejected plan %s\n', name); return false
	}
	return true
}

// The caller retains directory. fdopendir owns only the close-on-exec duplicate.
// Sort bounded filenames before loading, independent of readdir's order.
@[direct_array_access]
fn load_plan_directory(directory i32, mut set PlanSet, trusted bool) bool {
	copy := C.fcntl(directory, C.F_DUPFD_CLOEXEC, 0)
	if copy < 0 { C.perror(c'vinix-volume: duplicate plan directory'); return false }
	stream := C.fdopendir(copy)
	if stream == unsafe { nil } { C.close(copy); C.perror(c'vinix-volume: enumerate plans'); return false }
	defer { C.closedir(stream) }
	mut names := [64][256]char{}
	mut count := 0
	mut entries := 0
	for {
		unsafe { C.errno = 0 }
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if unsafe { C.errno != 0 } { C.perror(c'vinix-volume: plan enumeration'); return false }
			break
		}
		name := unsafe { &entry.d_name[0] }
		if C.strcmp(name, c'.') == 0 || C.strcmp(name, c'..') == 0 { continue }
		entries++
		if entries > 4096 { plan_error(c'plan directory exceeds enumeration limit'); return false }
		if !plan_filename(name) { continue }
		if count >= 64 - set.count { plan_error(c'plan set exceeds 64 disks'); return false }
		mut at := count
		for at > 0 && C.strcmp(name, &names[at - 1][0]) < 0 {
			names[at] = names[at - 1]
			at--
		}
		C.snprintf(&names[at][0], 256, c'%s', name)
		count++
	}
	if count > 0 && trusted && !trusted_directory(directory, c'boot plans directory must be owned by root and not writable by group or others') { return false }
	for i := 0; i < count; i++ {
		if !load_relative_plan(directory, &names[i][0], mut set, trusted, false) { return false }
	}
	return true
}

fn load_boot_plans(directory i32, mut set PlanSet) bool {
	if !load_relative_plan(directory, c'volumes.vmap', mut set, true, true) { return false }
	if !load_relative_bundle(directory, c'volumes.vset', mut set, true, true) { return false }
	plans := C.openat(directory, c'volumes.d', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if plans < 0 {
		if unsafe { C.errno == C.ENOENT } { return true }
		C.perror(c'vinix-volume: boot plans directory'); return false
	}
	defer { C.close(plans) }
	return load_plan_directory(plans, mut set, true)
}

@[direct_array_access]
fn restore_plan_set(set &PlanSet) i32 {
	return restore_plan_set_mode(set, false)
}

@[direct_array_access]
fn restore_plan_set_mode(set &PlanSet, grow bool) i32 {
	if set.count == 0 { return 0 }
	mut state := unsafe { &SetRestore(C.alloca(sizeof(SetRestore))) }
	unsafe { *state = SetRestore{} }
	defer { close_plan_set(state) }
	if !prepare_plan_set(set, mut state, grow, true) { return 1 }
	for i := 0; i < set.count; i++ {
		if apply_restore(state.fds[i], unsafe { &set.plans[i] }, unsafe { &state.states[i] }) != 0 { return 1 }
	}
	return 0
}

// The caller owns every descriptor published in state, even on failure.
// Checking uses readable disks; application retains its ordinary writable opens.
@[direct_array_access]
fn prepare_plan_set(set &PlanSet, mut state SetRestore, grow bool, writable bool) bool {
	if set.count < 0 || set.count > 64 || (set.count > 0 && !bundle_set_valid(set)) {
		plan_error(c'invalid plan set'); return false
	}
	for i := 0; i < set.count; i++ {
		plan := unsafe { &set.plans[i] }
		mut name := [256]char{}
		fd := discover_disk(plan, c'/dev', writable && plan_writable(plan), &name[0])
		if fd < 0 { return false }
		state.fds[i] = fd
		state.opened++
		C.printf(c'vinix-volume: matched /dev/%s\n', &name[0])
		if !prepare_restore_mode(fd, plan, mut state.states[i], grow) { return false }
		for j := 0; j < i; j++ {
			if state.states[i].parent.disk_id == state.states[j].parent.disk_id {
				plan_error(c'multiple plans resolved to the same physical disk'); return false
			}
		}
	}
	// Recheck every retained disk after the last plan's preflight. No path is
	// reopened and no create is issued until this pass succeeds for the set.
	for i := 0; i < set.count; i++ {
		if !verify_restore_disk(state.fds[i], unsafe { &set.plans[i] }, unsafe { &state.states[i].parent }) { return false }
	}
	return true
}

@[direct_array_access]
fn close_plan_set(state &SetRestore) {
	for i := 0; i < state.opened; i++ { C.close(state.fds[i]) }
}

fn restore_set_directory(path &char) i32 {
	directory := C.open(path, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if directory < 0 { C.perror(c'vinix-volume: open plan set'); return 1 }
	defer { C.close(directory) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	if !load_plan_directory(directory, mut set, false) { return 1 }
	return restore_plan_set(set)
}
