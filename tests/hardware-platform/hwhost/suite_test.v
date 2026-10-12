// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

import os

fn test_native_fixtures_refuse_the_wrong_target_before_installing() {
	state := os.join_path(os.vtmp_dir(), 'hwhost-native-target-${os.getpid()}')
	os.mkdir_all(state)!
	defer { os.rmdir_all(state) or {} }
	mut header := []u8{len: 64}
	for index, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1] { header[index] = byte }
	header[18] = 183
	source := os.join_path(state, 'native')
	os.write_file_array(source, header)!
	suite := Suite{ binaries: [RootBinary{ source: source, path: 'usr/bin/native' }] }
	for arch in ['x86_64', 'unknown'] {
		mut refused := false
		build_extras(Host{ arch: arch }, suite, os.join_path(state, arch)) or {
			refused = true
		}
		assert refused
		assert !os.exists(os.join_path(state, arch, 'root/usr/bin/native'))
	}
	root := build_extras(Host{ arch: 'aarch64' }, suite, os.join_path(state, 'arm'))!
	assert os.read_bytes(os.join_path(root, 'usr/bin/native'))! == header
	assert os.is_executable(os.join_path(root, 'usr/bin/native'))
	for invalid in [header[..19], []u8{len: 64}, [u8(0x7f), `E`, `L`, `F`, 1, 1]] {
		os.write_file_array(source, invalid)!
		mut refused := false
		build_extras(Host{ arch: 'aarch64' }, suite, os.join_path(state, 'invalid')) or {
			refused = true
		}
		assert refused
		assert !os.exists(os.join_path(state, 'invalid/root/usr/bin/native'))
	}
}

fn test_prepared_disk_images_are_copied_and_validated() {
	state := os.join_path(os.vtmp_dir(), 'hwhost-prepared-disk-${os.getpid()}')
	os.mkdir_all(state)!
	defer { os.rmdir_all(state) or {} }
	source := os.join_path(state, 'source.raw')
	os.write_file(source, '')!
	os.truncate(source, u64(1) << 20)!
	mut file := os.open_file(source, 'r+')!
	file.write_to(1024, 'prepared image'.bytes())!
	file.close()
	disk := Disk{ name: 'disk.raw', size_mib: 1, image: source, untouched: true }
	create_disk(disk, state)!
	check_disk_untouched(disk, state)!
	apply_damage(DiskDamage{ disk: 'disk.raw', offset: 1024, length: 1, fill: 0 }, state)!
	mut changed := false
	check_disk_untouched(disk, state) or { changed = true }
	assert changed
	for invalid in [Disk{ ...disk, size_mib: 2 }, Disk{ ...disk, header: 'header' },
		Disk{ ...disk, prefill: [DiskPattern{ length: 1 }] },
		Disk{ ...disk, image: state + '/missing' }] {
		mut refused := false
		create_disk(invalid, state) or { refused = true }
		assert refused
	}
}

fn test_power_cut_markers_must_be_required_and_kill_the_child() {
	valid := Scenario{
		name:     'crash'
		arches:   ['x86_64']
		required: ['HWTEST START crash', 'CUT NOW']
		reboots:  [Reboot{ power_cut_after: 'CUT NOW' }]
	}
	validate_scenarios([valid])!
	mut refused := false
	validate_scenarios([Scenario{ ...valid, reboots: [Reboot{ power_cut_after: 'unrequired' }] }]) or {
		refused = err.msg().contains('required serial marker')
	}
	assert refused
	log := os.join_path(os.vtmp_dir(), 'hwhost-power-cut-${os.getpid()}.log')
	defer { os.rm(log) or {} }
	mut child := start_child(['sleep', '60'], map[string]string{}, log)!
	defer { child.stop() }
	child.cut_power()!
	assert child.poll() && child.outcome() == 'killed by signal 9'
	mut ended_refused := false
	child.cut_power() or { ended_refused = true }
	assert ended_refused
}
