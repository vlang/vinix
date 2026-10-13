// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_boot_encrypted_geometry_conflicts_preflight_without_changing_saved_state() {
	mut work := VolumeSealFiles{}
	work.disk = DiskKey{bytes: u64(-1) & ~u64(4095), sector: 4096, kind: 2}
	work.disk.id[0] = 1
	work.request.data = Request{slot: 63, offset: work.disk.bytes - 8192, length: 8192, flags: 1}
	mut set := PlanSet{}
	assert boot_volume_set_compatible(&set, &work)
	mut plan := Plan{key: work.disk, count: 1}
	plan.rows[0] = Request{slot: 1, offset: work.request.data.offset - 8192, length: 8192}
	assert append_plan(mut set, &plan)
	before := set
	assert boot_volume_set_compatible(&set, &work) && set == before
	for offset in [work.request.data.offset - 4096, work.request.data.offset, work.request.data.offset + 4096] {
		set = before; set.plans[0].rows[0].offset = offset
		set.plans[0].rows[0].length = if offset < work.request.data.offset { u64(8192) } else { u64(4096) }
		saved := set; assert !boot_volume_set_compatible(&set, &work) && set == saved
	}
	set = before; set.plans[0].rows[0].slot = 63; set.slots = u64(1) << 63
	assert !boot_volume_set_compatible(&set, &work)
	set.plans[0].key.id[0] = 2; assert !boot_volume_set_compatible(&set, &work)
	set = before; set.plans[0].key.id[0] = 2
	set.plans[0].rows[0].offset = work.request.data.offset
	assert boot_volume_set_compatible(&set, &work)
	for count in [-1, 65] { set = before; set.count = count; assert !boot_volume_set_compatible(&set, &work) }
	set = before; set.slots = 0; assert !boot_volume_set_compatible(&set, &work)
	set = before; work.request.data.length = u64(-1); assert !boot_volume_set_compatible(&set, &work)
}

fn test_boot_unlock_arity_rejects_before_any_configuration_access() {
	unsafe {
		args := [&char(c'vinix-volume'), &char(c'boot-unlock'), &char(c'/unused'), &char(nil)]!
		for count in [3, 4] { assert run(count, &args[0]) == 2 }
	}
}
