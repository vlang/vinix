// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_automatic_data_commands_reject_bad_arity_and_empty_paths_before_io() {
	unsafe {
		for verb in [&char(c'hash-bundle-auto'), &char(c'scrub-data-auto'), &char(c'verify-data-auto')]! {
			mut args := [&char(c'vinix-volume'), verb, &char(c'/unused'), &char(c'/unused'), &char(nil)]!
			count := if C.strcmp(verb, c'verify-data-auto') == 0 { 3 } else { 4 }
			for wrong in [2, 3, 4, 5] { if wrong != count { assert run(wrong, &args[0]) == 2 } }
			for at in 2 .. count { args[at] = &char(c''); assert run(count, &args[0]) == 2; args[at] = &char(c'/unused') }
		}
	}
}

fn test_automatic_data_participant_validation_requires_complete_unique_bounded_geometry() {
	mut set := PlanSet{}
	assert !data_devices_valid(unsafe { &set }, unsafe { nil })
	for disk in 0 .. 64 {
		mut plan := Plan{count: 1, key: DiskKey{bytes: 262144, sector: 512, kind: 1}}
		put_le(&plan.key.id[0], 0, 4, u64(disk + 1)); plan.rows[0] = Request{slot: u32(disk), offset: 8192, length: 4096}
		assert append_plan(mut set, unsafe { &plan }) && data_devices_valid(unsafe { &set }, unsafe { nil })
	}
	mut invalid := set; invalid.count = 65; assert !data_devices_valid(unsafe { &invalid }, unsafe { nil })
	invalid = set; invalid.plans[63].key = invalid.plans[0].key; assert !data_devices_valid(unsafe { &invalid }, unsafe { nil })
	invalid = set; invalid.plans[63].rows[0].length = u64(0x8000000000000000); assert !data_devices_valid(unsafe { &invalid }, unsafe { nil })
	invalid = set; invalid.plans[63].rows[0].offset++; assert !data_devices_valid(unsafe { &invalid }, unsafe { nil })
	mut manual := DataDevices{}; assert !data_devices_valid(unsafe { &set }, unsafe { &manual })
}
