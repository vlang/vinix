// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct CapacityBatch {
mut:
	count int
	disks [64]u32
	devices [64]&char
	expected [64]u64
}

struct CapacityKeys {
mut:
	rows [64]DiskKey
}

struct CapacityBatchResults {
mut:
	count int
	previous [64]u64
	keys CapacityKeys
}

struct CapacityPins {
mut:
	count int
	descriptors [64]i32
	ids [64]u64
	keys CapacityKeys
}

// Reject the complete request list before opening any physical disk.
@[direct_array_access]
fn capacity_batch_valid(set &PlanSet, batch &CapacityBatch) bool {
	if batch.count < 1 || batch.count > 64 || !bundle_set_valid(set) { return false }
	mut seen := u64(0)
	for i in 0 .. batch.count {
		disk := batch.disks[i]
		if disk >= u32(set.count) || batch.expected[i] == 0
			|| batch.expected[i] < set.plans[disk].key.bytes
			|| batch.expected[i] % set.plans[disk].key.sector != 0 {
			plan_error(c'absent disk, shrinking or unaligned batch capacity'); return false
		}
		bit := u64(1) << disk
		if seen & bit != 0 { plan_error(c'capacity batch repeats a disk'); return false }
		seen |= bit
	}
	return true
}

// Preserve the original set and caller results until every observed identity
// and exact requested capacity has passed the existing adoption rules.
@[direct_array_access]
fn bundle_adopt_capacity_batch(mut set PlanSet, batch &CapacityBatch, keys &CapacityKeys,
	mut results CapacityBatchResults) bool {
	if !capacity_batch_valid(unsafe { &set }, batch) { return false }
	mut candidate := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut outcome := unsafe { &CapacityBatchResults(C.alloca(sizeof(CapacityBatchResults))) }
	unsafe { *candidate = set; *outcome = CapacityBatchResults{count: batch.count} }
	for i in 0 .. batch.count {
		disk := int(batch.disks[i])
		outcome.previous[i] = candidate.plans[disk].key.bytes
		if !bundle_adopt_capacity(mut candidate, disk, unsafe { &keys.rows[i] }, batch.expected[i]) { return false }
		outcome.keys.rows[i] = candidate.plans[disk].key
	}
	set = unsafe { *candidate }
	results = unsafe { *outcome }
	return true
}

// Pin all named devices read-only, then recheck every descriptor after the
// complete candidate is planned. An early disk can change while later disks
// are probed, so a per-request immediate recheck is insufficient.
@[direct_array_access]
fn capacity_batch_bundle_plan(path &char, batch &CapacityBatch, preview bool) i32 {
	mut edit := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut pins := unsafe { &CapacityPins(C.alloca(sizeof(CapacityPins))) }
	mut results := unsafe { &CapacityBatchResults(C.alloca(sizeof(CapacityBatchResults))) }
	mut after := unsafe { &DiskKey(C.alloca(sizeof(DiskKey))) }
	unsafe { *edit = PlanEdit{}; *set = PlanSet{}; *pins = CapacityPins{}; *results = CapacityBatchResults{}; *after = DiskKey{} }
	defer { close_plan_edit(mut edit) }
	defer { for i in 0 .. pins.count { C.close(pins.descriptors[i]) } }
	if !open_plan_edit(path, mut edit, !preview) || !read_bundle(edit.source, mut set, false)
		|| !capacity_batch_valid(set, batch) { return 1 }
	for i in 0 .. batch.count {
		if batch.devices[i] == unsafe { nil } || unsafe { batch.devices[i][0] == 0 } {
			return plan_error(c'capacity batch requires a device for every disk')
		}
	}
	for i in 0 .. batch.count {
		target := C.open(batch.devices[i], C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
		if target < 0 { C.perror(c'vinix-volume: open batch capacity disk'); return 1 }
		pins.descriptors[i] = target; pins.count++
		mut parent := Status{}
		if !probe_disk(target, mut pins.keys.rows[i], mut parent) { return 1 }
		pins.ids[i] = parent.disk_id
		for earlier in 0 .. i {
			if pins.ids[earlier] == parent.disk_id { return plan_error(c'capacity batch repeats a physical disk') }
		}
	}
	if !bundle_adopt_capacity_batch(mut set, batch, unsafe { &pins.keys }, mut results) { return 1 }
	for i in 0 .. batch.count {
		mut status := Status{}
		if !probe_disk(pins.descriptors[i], mut after, mut status)
			|| !key_matches(unsafe { &pins.keys.rows[i] }, after) || status.disk_id != pins.ids[i] {
			return plan_error(c'disk identity or geometry changed before batch capacity publication')
		}
	}
	// Equal-capacity retries still complete both flushes and atomic replacement.
	if !preview && !publish_edit_bundle(edit, set) { return 1 }
	operation := if preview { unsafe { &char(c'preview-capacity') } } else { unsafe { &char(c'planned-capacity') } }
	mut ok := C.printf(c'requests=%d operation=%s\n', results.count, operation) >= 0
	for i in 0 .. results.count {
		key := results.keys.rows[i]
		action := if key.bytes == results.previous[i] { unsafe { &char(c'keep') } } else { unsafe { &char(c'adopt') } }
		if C.printf(c'request=%d disk=%u action=%s previous_bytes=%lu bytes=%lu sector=%lu\n',
			i, batch.disks[i], action, results.previous[i], key.bytes, key.sector) < 0 { ok = false }
	}
	return finish_bundle_report(ok)
}
