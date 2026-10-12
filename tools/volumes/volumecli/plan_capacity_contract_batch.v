// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct CapacityContractBatch {
mut:
	count int
	keys [64]DiskKey
	devices [64]&char
	expected [64]u64
}

struct CapacityContractResults {
mut:
	count int
	disks [64]u32
	previous [64]u64
	keys CapacityKeys
}

@[direct_array_access]
fn capacity_contract_disk(set &PlanSet, key &DiskKey) int {
	for disk in 0 .. set.count {
		if enrollment_identity_matches(key, unsafe { &set.plans[disk].key }) { return disk }
	}
	return -1
}

// Reject impossible contractions before physical probes. Pending desired rows
// and every pool, including unselected pools, must already fit the retained disk.
@[direct_array_access]
fn capacity_contract_batch_valid(set &PlanSet, batch &CapacityContractBatch) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(set) { return false }
	for disk in 0 .. set.count { for previous in 0 .. disk {
		if enrollment_identity_matches(unsafe { &set.plans[disk].key }, unsafe { &set.plans[previous].key }) {
			plan_error(c'capacity contraction bundle has ambiguous disk identities'); return false
		}
	} }
	for i in 0 .. batch.count {
		if !forget_identity_valid(unsafe { &batch.keys[i] }) { return false }
		for previous in 0 .. i {
			if enrollment_identity_matches(unsafe { &batch.keys[i] }, unsafe { &batch.keys[previous] }) {
				plan_error(c'capacity contraction repeats a disk identity'); return false
			}
		}
		disk := capacity_contract_disk(set, unsafe { &batch.keys[i] })
		if disk < 0 { plan_error(c'capacity contraction identity is not enrolled'); return false }
		plan := unsafe { &set.plans[disk] }; end := batch.expected[i]
		if end < plan.key.sector * 2 || end > plan.key.bytes || end % plan.key.sector != 0 {
			plan_error(c'capacity contraction requires a supported nonempty sector-aligned disk without expansion'); return false
		}
		for row := u32(0); row < plan.count; row++ {
			mapping := plan.rows[row]
			if mapping.offset > end || mapping.length > end - mapping.offset {
				plan_error(c'capacity contraction would exclude desired mapping bytes'); return false
			}
		}
		for at in 0 .. set.regions {
			if set.windows[at].disk == u32(disk) && set.windows[at].window.end > end {
				plan_error(c'contract pool eligibility before adopting a smaller disk'); return false
			}
		}
	}
	return true
}

@[direct_array_access]
fn bundle_contract_capacity_batch(mut set PlanSet, batch &CapacityContractBatch,
	keys &CapacityKeys, mut results CapacityContractResults) bool {
	if !capacity_contract_batch_valid(unsafe { &set }, batch) { return false }
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &CapacityContractResults(C.alloca(sizeof(CapacityContractResults))) }
	unsafe { *candidate = set; *outcome = CapacityContractResults{count: batch.count} }
	for i in 0 .. batch.count {
		disk := capacity_contract_disk(unsafe { &set }, unsafe { &batch.keys[i] }); key := keys.rows[i]
		if !key_valid(unsafe { &key }) || key.bytes != batch.expected[i]
			|| key.sector != set.plans[disk].key.sector || !capacity_identifier_matches(unsafe { &key }, unsafe { &set.plans[disk].key }) {
			plan_error(c'capacity contraction requires the same observed identifier/sectors and exact expected size'); return false
		}
		outcome.disks[i] = u32(disk); outcome.previous[i] = set.plans[disk].key.bytes
		candidate.plans[disk].key.bytes = key.bytes; outcome.keys.rows[i] = candidate.plans[disk].key
	}
	if !bundle_set_valid(candidate) { return false }
	set = unsafe { *candidate }; results = unsafe { *outcome }; return true
}

// Pin every named physical device read-only, then recheck all descriptors after
// complete planning. Neither preview nor publication changes disk or live views.
@[direct_array_access]
fn contract_capacity_batch_plan(path &char, batch &CapacityContractBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut pins := unsafe { &CapacityPins(C.alloca(sizeof(CapacityPins))) }
	mut results := unsafe { &CapacityContractResults(C.alloca(sizeof(CapacityContractResults))) }
	mut after := unsafe { &DiskKey(C.alloca(sizeof(DiskKey))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *pins = CapacityPins{}; *results = CapacityContractResults{}; *after = DiskKey{} }
	defer { close_plan_edit(mut edit) }
	defer { for i in 0 .. pins.count { C.close(pins.descriptors[i]) } }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !capacity_contract_batch_valid(set, batch) { return 1 }
	for i in 0 .. batch.count {
		if batch.devices[i] == unsafe { nil } || unsafe { batch.devices[i][0] == 0 } {
			return plan_error(c'capacity contraction requires a device for every identity')
		}
	}
	for i in 0 .. batch.count {
		target := C.open(batch.devices[i], C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
		if target < 0 { C.perror(c'vinix-volume: open capacity contraction disk'); return 1 }
		pins.descriptors[i] = target; pins.count++
		mut parent := Status{}
		if !probe_disk(target, mut pins.keys.rows[i], mut parent) { return 1 }
		pins.ids[i] = parent.disk_id
		for earlier in 0 .. i { if pins.ids[earlier] == parent.disk_id { return plan_error(c'capacity contraction repeats a physical disk') } }
	}
	if !bundle_contract_capacity_batch(mut set, batch, unsafe { &pins.keys }, mut results) { return 1 }
	for i in 0 .. batch.count {
		mut status := Status{}
		if !probe_disk(pins.descriptors[i], mut after, mut status)
			|| !key_matches(unsafe { &pins.keys.rows[i] }, after) || status.disk_id != pins.ids[i] {
			return plan_error(c'disk identity or geometry changed before capacity contraction publication')
		}
	}
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-disk-contraction') } } else { unsafe { &char(c'planned-disk-contraction') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', results.count, operation) >= 0
	for i in 0 .. results.count {
		key := results.keys.rows[i]; mut identity := [41]char{}; disk_identity(unsafe { &batch.keys[i] }, &identity[0])
		action := if key.bytes == results.previous[i] { unsafe { &char(c'keep') } } else { unsafe { &char(c'contract') } }
		if C.printf(c'request=%d disk=%u identity=%s action=%s previous_bytes=%lu bytes=%lu sector=%lu\n',
			i, results.disks[i], &identity[0], action, results.previous[i], key.bytes, key.sector) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
