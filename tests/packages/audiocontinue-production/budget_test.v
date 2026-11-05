// SPDX-License-Identifier: GPL-2.0-or-later
module audiocontinue

fn budget2_fixture() Projection2 {
	return Projection2{
		current_allocated: u64(128) << 20
		current_apparent: u64(256) << 20
		preparation_reserve: u64(200) << 20
		scenario_count: 3
		boot_image_bytes: u64(64) << 20
		firmware_vars_bytes: u64(64) << 20
		rootfs_archive_bytes_per_scenario: u64(64) << 20
		wave_bytes_per_scenario: 46084096
		logs_bytes_per_scenario: u64(16) << 20
		receipt_reserve: u64(16) << 20
		cap: u64(2048) << 20
	}
}

fn budget2_refuses(b Projection2, run bool) {
	mut refused := false
	_ := assess_budget2(b, run) or { refused = true; u64(0) }
	production_require2((refused), 'production assertion')
}

fn test_budget2_preparation_and_complete_run_growth() {
	b := budget2_fixture()
	preparation := assess_budget2(b, false) or { panic(err) }
	production_require2((preparation == u64(216) << 20), 'production assertion')
	run := assess_budget2(b, true) or { panic(err) }
	expected := (u64(216) << 20) + 3 * ((u64(192) << 20) + u64(46084096) + (u64(16) << 20))
	production_require2((run == expected), 'production assertion')
}

fn test_budget2_checks_both_inclusive_cap_boundaries() {
	b := budget2_fixture()
	growth := u64(216) << 20
	exact := Projection2{...b, current_allocated: b.cap - growth, current_apparent: b.cap - growth}
	production_require2(((assess_budget2(exact, false) or { panic(err) }) == growth), 'production assertion')
	budget2_refuses(Projection2{...exact, current_allocated: exact.current_allocated + 1}, false)
	budget2_refuses(Projection2{...exact, current_apparent: exact.current_apparent + 1}, false)
	budget2_refuses(Projection2{...b, current_allocated: b.cap + 1}, false)
	budget2_refuses(Projection2{...b, current_apparent: b.cap + 1}, false)
}

fn test_budget2_retained_196137_kib_headroom_refuses_before_work() {
	b := budget2_fixture()
	remaining := u64(196137) * 1024
	near := Projection2{...b, current_allocated: b.cap - remaining, current_apparent: b.cap - remaining}
	budget2_refuses(near, false)
	budget2_refuses(near, true)
}

fn test_budget2_planning_and_receipt_floors_cannot_be_omitted() {
	b := budget2_fixture()
	for preparation in [u64(0), u64(1), (u64(200) << 20) - 1] {
		budget2_refuses(Projection2{...b, preparation_reserve: preparation}, false)
		budget2_refuses(Projection2{...b, preparation_reserve: preparation}, true)
	}
	budget2_refuses(Projection2{...b, receipt_reserve: (u64(16) << 20) - 1}, false)
	budget2_refuses(Projection2{...b, cap: b.cap + 1}, false)
}

fn test_budget2_run_requires_every_scenario_and_complete_media() {
	b := budget2_fixture()
	for count in [0, 1, 2, 4, -1] { budget2_refuses(Projection2{...b, scenario_count: count}, true) }
	budget2_refuses(Projection2{...b, boot_image_bytes: (u64(64) << 20) - 1}, true)
	budget2_refuses(Projection2{...b, firmware_vars_bytes: (u64(64) << 20) - 1}, true)
	budget2_refuses(Projection2{...b, rootfs_archive_bytes_per_scenario: (u64(64) << 20) - 1}, true)
	budget2_refuses(Projection2{...b, wave_bytes_per_scenario: 46084095}, true)
	budget2_refuses(Projection2{...b, logs_bytes_per_scenario: 0}, true)
	budget2_refuses(Projection2{...b, logs_bytes_per_scenario: (u64(16) << 20) - 1}, true)
	preparation_only := Projection2{...b, scenario_count: 0, boot_image_bytes: 0,
		firmware_vars_bytes: 0, rootfs_archive_bytes_per_scenario: 0,
		wave_bytes_per_scenario: 0, logs_bytes_per_scenario: 0}
	production_require2(((assess_budget2(preparation_only, false) or { panic(err) }) == u64(216) << 20), 'production assertion')
}

fn test_budget2_checked_arithmetic_refuses_extreme_reservations() {
	b := budget2_fixture()
	budget2_refuses(Projection2{...b, preparation_reserve: ~u64(0)}, false)
	budget2_refuses(Projection2{...b, receipt_reserve: ~u64(0)}, false)
	budget2_refuses(Projection2{...b, boot_image_bytes: ~u64(0)}, true)
	budget2_refuses(Projection2{...b, boot_image_bytes: u64(1) << 63}, true)
	budget2_refuses(Projection2{...b, rootfs_archive_bytes_per_scenario: ~u64(0)}, true)
}

fn budget2_boot_refuses(payload u64) {
	mut refused := false
	_ := boot_image_budget2(payload) or { refused = true; u64(0) }
	production_require2((refused), 'production assertion')
}

fn test_budget2_boot_image_uses_payload_headroom_and_power_of_two() {
	production_require2(((boot_image_budget2(0) or { panic(err) }) == u64(64) << 20), 'production assertion')
	production_require2(((boot_image_budget2((u64(25) << 20) + 1024) or { panic(err) }) == u64(64) << 20), 'production assertion')
	production_require2(((boot_image_budget2(u64(66) << 20) or { panic(err) }) == u64(128) << 20), 'production assertion')
	production_require2(((boot_image_budget2(u64(281) << 20) or { panic(err) }) == u64(512) << 20), 'production assertion')
	// Adjacent payload sizes straddle the minimum image's headroom boundary.
	production_require2(((boot_image_budget2(52195783) or { panic(err) }) == u64(64) << 20), 'production assertion')
	production_require2(((boot_image_budget2(52195784) or { panic(err) }) == u64(128) << 20), 'production assertion')
	production_require2(((boot_image_budget2(u64(14) << 30) or { panic(err) }) == u64(16) << 30), 'production assertion')
	budget2_boot_refuses(u64(15) << 30)
	budget2_boot_refuses(~u64(0))
}

fn test_proof_reserve2_covers_known_after_maps_and_final_receipt() {
	legacy := LegacyPlan2{inputs: {'file:test': {'/fixture': 'file|420|fixture'}}}
	donor := Donor2{roots: {'capture': '/capture', 'store': '/store'}}
	source := Source2{root: '/source', base_revision: '0123456789012345678901234567890123456789'}
	reserve := proof_reserve2(legacy, donor, source) or { panic(err) }
	production_require2((reserve > u64(40) << 20), 'production assertion')
	production_require2((reserve % 4096 == 0), 'production assertion')
}
