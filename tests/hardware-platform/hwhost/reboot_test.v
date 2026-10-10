// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A machine that is booted more than once in one scenario, and what the
// controller does to its disks and asks of them.
module hwhost

import os

fn scratch(name string) string {
	path := os.join_path(os.temp_dir(), 'hwhost-reboot-${os.getpid()}-${name}')
	os.rmdir_all(path) or {}
	os.mkdir_all(path) or { panic(err) }
	return path
}

fn rebooted() Scenario {
	return Scenario{
		name:        'twice'
		arches:      ['x86_64']
		qemu:        ['-smp', '4']
		qemu_x86_64: ['-m', '1024']
		required:    ['HWTEST START twice']
		reboots:     [Reboot{}, Reboot{
			qemu: ['-m', '768']
		}]
		disks:       [Disk{
			name:     'image.raw'
			size_mib: 1
		}]
	}
}

fn test_a_scenario_boots_once_more_for_each_reboot() {
	assert Scenario{}.boots() == 1
	assert rebooted().boots() == 3
}

fn test_a_later_boot_has_its_own_arguments_last() {
	scenario := rebooted()
	assert scenario.boot_arguments('x86_64', 0) == ['-smp', '4', '-m', '1024']
	assert scenario.boot_arguments('x86_64', 1) == ['-smp', '4', '-m', '1024']
	// QEMU takes the last -m it is given.
	assert scenario.boot_arguments('x86_64', 2) == ['-smp', '4', '-m', '1024', '-m', '768']
	assert scenario.boot_arguments('aarch64', 2) == ['-smp', '4', '-m', '768']
}

fn test_each_boot_has_a_serial_log_of_its_own() {
	assert serial_log_name(0) == 'serial.log'
	assert serial_log_name(1) == 'serial-2.log'
	assert serial_log_name(2) == 'serial-3.log'
	assert boot_separator(1).contains('boot 2')
}

fn test_every_boot_but_the_last_must_be_switched_off_by_the_guest() {
	assert intermediate_end_problem(0, 'guest-shutdown', 0, 'exit 0') == ''
	reset := intermediate_end_problem(0, 'guest-reset', 0, 'exit 0')
	assert reset.contains('boot 1') && reset.contains('guest-reset')
	// A machine the controller had to stop was not switched off.
	stopped := intermediate_end_problem(1, 'host-signal', 0, 'exit 0')
	assert stopped.contains('boot 2') && stopped.contains('host-signal')
	// Nor one QEMU gave up on.
	crashed := intermediate_end_problem(1, '', 1, 'exit 1')
	assert crashed.contains('QEMU failed') && crashed.contains('boot 2')
	silent := intermediate_end_problem(0, '', 0, 'exit 0')
	assert silent.contains('exit 0')
}

fn test_a_machine_booted_twice_has_to_end_by_itself() {
	mut scenario := Scenario{
		...rebooted()
		ending: .running
	}
	validate_scenarios([scenario]) or {
		assert err.msg().contains('end by itself')
		return
	}
	assert false
}

fn test_damage_is_done_to_a_disk_the_scenario_has() {
	scenario := Scenario{
		...rebooted()
		reboots: [
			Reboot{
				damage: [DiskDamage{
					disk:   'other.raw'
					length: 8
				}]
			},
		]
	}
	validate_scenarios([scenario]) or {
		assert err.msg().contains('damage')
		return
	}
	assert false
}

fn test_expected_bytes_are_text_or_zeros_on_a_disk_the_scenario_has() {
	for bytes in [DiskBytes{
		disk: 'image.raw'
	}, DiskBytes{
		disk:  'image.raw'
		text:  'VINIXHIB'
		zeros: 8
	}, DiskBytes{
		disk: 'other.raw'
		text: 'VINIXHIB'
	}] {
		scenario := Scenario{
			...rebooted()
			disk_bytes: [bytes]
		}
		mut refused := false
		validate_scenarios([scenario]) or { refused = err.msg().contains('bytes are expected') }
		assert refused
	}
	validate_scenarios([
		Scenario{
			...rebooted()
			disk_bytes: [DiskBytes{
				disk: 'image.raw'
				text: 'VINIXHIB'
			}, DiskBytes{
				disk:   'image.raw'
				offset: 24
				zeros:  8
			}]
		},
	])!
}

fn test_the_events_of_an_earlier_boot_are_counted_with_a_later_ones() {
	mut first := EventLog{}
	first.note('SHUTDOWN')
	first.note('SUSPEND')
	mut second := EventLog{}
	second.note('SHUTDOWN')
	second.note('DEVICE_DELETED')
	mut all := EventLog{}
	all.add(&first)
	all.add(&second)
	assert all.count('SHUTDOWN') == 2
	assert all.count('SUSPEND') == 1
	assert all.count('DEVICE_DELETED') == 1
	assert all.missing(['SHUTDOWN', 'SHUTDOWN', 'SUSPEND']) == []
	assert all.missing(['SUSPEND', 'SUSPEND']) == ['SUSPEND']
	// The logs added are left as they were.
	assert first.count('SHUTDOWN') == 1
	mut session := Session{
		events: first
	}
	seen := session.events_with(&second)
	assert seen.count('SHUTDOWN') == 2
	assert session.events.count('SHUTDOWN') == 1
	assert second.count('SHUTDOWN') == 1
}

fn test_damage_overwrites_the_bytes_it_names_and_no_others() {
	state := scratch('damage')
	defer {
		os.rmdir_all(state) or {}
	}
	disk := Disk{
		name:     'image.raw'
		size_mib: 1
		header:   'VINIXHIB and the rest of a header'
	}
	create_disk(disk, state)!
	apply_damage(DiskDamage{
		disk:   'image.raw'
		offset: 8
		length: 4
		fill:   0xa5
	}, state)!
	found := os.read_bytes(os.join_path(state, 'image.raw'))!
	assert found.len == 1 << 20
	assert found[..8].bytestr() == 'VINIXHIB'
	assert found[8..12] == [u8(0xa5), 0xa5, 0xa5, 0xa5]
	assert found[12..16].bytestr() == ' the'
	apply_damage(DiskDamage{
		disk:   'missing.raw'
		length: 1
	}, state) or {
		assert err.msg().contains('missing.raw')
		return
	}
	assert false
}

fn test_a_disk_that_was_to_be_left_alone_is_compared_byte_for_byte() {
	state := scratch('untouched')
	defer {
		os.rmdir_all(state) or {}
	}
	disk := Disk{
		name:      'disk.raw'
		size_mib:  1
		header:    'not blank'
		prefill:   [DiskPattern{
			offset: 4096
			length: 64
			seed:   0x41
		}]
		untouched: true
	}
	create_disk(disk, state)!
	contents := disk_contents(disk)
	assert contents.len == 1 << 20
	assert contents[..9].bytestr() == 'not blank'
	assert contents[4096] == 0x41 && contents[4097] == 0x48
	check_disk_untouched(disk, state)!
	// One byte, far from anything the controller wrote.
	apply_damage(DiskDamage{
		disk:   'disk.raw'
		offset: 700000
		length: 1
		fill:   1
	}, state)!
	check_disk_untouched(disk, state) or {
		assert err.msg().contains('byte 700000')
		// A disk nobody asked about is not looked at.
		check_disk_untouched(Disk{
			...disk
			untouched: false
		}, state)!
		return
	}
	assert false
}

fn test_bytes_expected_on_a_disk_at_the_end() {
	state := scratch('bytes')
	defer {
		os.rmdir_all(state) or {}
	}
	create_disk(Disk{
		name:     'image.raw'
		size_mib: 1
		header:   'VINIXHIB'
	}, state)!
	check_disk_bytes(DiskBytes{
		disk: 'image.raw'
		text: 'VINIXHIB'
	}, state)!
	check_disk_bytes(DiskBytes{
		disk:   'image.raw'
		offset: 24
		zeros:  8
	}, state)!
	check_disk_bytes(DiskBytes{
		disk: 'image.raw'
		text: 'VINIXHIX'
	}, state) or {
		assert err.msg().contains('byte 7')
		check_disk_bytes(DiskBytes{
			disk:  'image.raw'
			zeros: 8
		}, state) or {
			assert err.msg().contains('8 zero bytes')
			return
		}
	}
	assert false
}

fn test_what_the_suspend_to_disk_scenarios_ask_of_the_controller() {
	// One that goes back into its image names the device for it and boots
	// again; one that must find no way to has both disks compared with
	// what they were made as.
	hibernate := find_scenario(scenarios, 'hibernate') or { panic('no hibernate') }
	assert hibernate.cmdline.contains('vinix.hibernate=sd1')
	assert hibernate.boots() == 3
	unnamed := find_scenario(scenarios, 'hibernate-unnamed') or { panic('no hibernate-unnamed') }
	assert !unnamed.cmdline.contains('vinix.hibernate')
	assert unnamed.boots() == 1
	assert unnamed.disks.len == 2 && unnamed.disks.all(it.untouched)
	foreign := find_scenario(scenarios, 'hibernate-foreign') or { panic('no hibernate-foreign') }
	assert foreign.cmdline.contains('vinix.hibernate=sd1')
	assert foreign.disks.len == 2 && foreign.disks.all(it.untouched)
	// An image is damaged in the device it is on, with the machine off.
	for name in ['hibernate-damaged-header', 'hibernate-damaged-pages'] {
		damaged := find_scenario(scenarios, name) or { panic('no ${name}') }
		assert damaged.boots() == 2
		assert damaged.reboots[0].damage.len == 1 && damaged.reboots[0].damage[0].disk == 'image.raw'
	}
	// The device an image goes to is not kept once its scenario has passed.
	assert hibernate.disks.any(it.name == 'image.raw' && it.bulky)
}

fn test_a_boot_can_have_a_command_line_of_its_own() {
	scenario := Scenario{
		...rebooted()
		cmdline: 'vinix.hibernate=sd1'
		reboots: [Reboot{
			own_cmdline: true
		}, Reboot{}, Reboot{
			own_cmdline: true
			cmdline:     'vinix.iommu=1'
		}]
	}
	assert scenario.boot_cmdline(0) == 'vinix.hibernate=sd1'
	// None at all, which is not the same as the scenario's.
	assert scenario.boot_cmdline(1) == ''
	// For that boot alone.
	assert scenario.boot_cmdline(2) == 'vinix.hibernate=sd1'
	assert scenario.boot_cmdline(3) == 'vinix.iommu=1'
	waiting := find_scenario(scenarios, 'hibernate-waiting') or { panic('no hibernate-waiting') }
	assert waiting.boots() == 3
	assert waiting.boot_cmdline(0).contains('vinix.hibernate=sd1')
	assert waiting.boot_cmdline(1) == ''
	assert waiting.boot_cmdline(2).contains('vinix.hibernate=sd1')
	// A system is installed onto a blank disk of four gigabytes or more.
	root := find_scenario(scenarios, 'hibernate-root') or { panic('no hibernate-root') }
	assert root.disks.any(it.name == 'system.raw' && it.size_mib >= 4096 && it.header == '' && it.bulky)
}
