// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

fn names_of(list []Scenario) []string {
	return list.map(it.name)
}

fn test_the_table_is_valid() {
	validate_scenarios(scenarios)!
}

fn test_default_selection_is_what_applies_and_is_not_pending() {
	arm := select_scenarios(scenarios, 'aarch64', []string{})!
	assert names_of(arm.run) == ['devices']
	assert names_of(arm.skipped) == ['qmp-powerdown']
	x86 := select_scenarios(scenarios, 'x86_64', []string{})!
	assert names_of(x86.run) == ['devices', 'ahci']
	assert names_of(x86.skipped) == ['qmp-powerdown']
}

fn test_a_named_scenario_runs_even_when_pending() {
	selection := select_scenarios(scenarios, 'aarch64', ['qmp-powerdown'])!
	assert names_of(selection.run) == ['qmp-powerdown']
	assert selection.skipped.len == 0
}

fn test_named_scenarios_keep_their_order_and_run_once() {
	selection := select_scenarios(scenarios, 'x86_64', ['ahci', 'devices', 'ahci'])!
	assert names_of(selection.run) == ['ahci', 'devices']
}

fn test_a_name_that_cannot_run_is_an_error() {
	select_scenarios(scenarios, 'aarch64', ['ahci']) or {
		assert err.msg().contains('does not run on aarch64')
		select_scenarios(scenarios, 'x86_64', ['nonesuch']) or {
			assert err.msg().contains('unknown scenario nonesuch')
			select_scenarios(scenarios, 'riscv64', []string{}) or {
				assert err.msg().contains('unknown architecture')
				return
			}
			assert false, 'an unknown architecture was accepted'
			return
		}
		assert false, 'an unknown scenario was accepted'
		return
	}
	assert false, 'ahci was selected on aarch64'
}

fn test_qemu_arguments_are_per_architecture() {
	devices := find_scenario(scenarios, 'devices') or { panic('no devices scenario') }
	assert devices.qemu_arguments('x86_64') == ['-nic', 'user,model=e1000']
	assert devices.qemu_arguments('aarch64') == ['-device', 'e1000,netdev=hwn0', '-netdev',
		'user,id=hwn0']
	both := Scenario{
		qemu:        ['-a']
		qemu_x86_64: ['-b']
	}
	assert both.qemu_arguments('x86_64') == ['-a', '-b']
	assert both.qemu_arguments('aarch64') == ['-a']
}

fn test_every_scenario_forbids_the_common_markers() {
	scenario := Scenario{
		forbidden: ['ahci: timeout']
	}
	assert scenario.forbidden_markers() == ['KERNEL PANIC', 'FATAL EXCEPTION', 'HWTEST FAIL',
		'ahci: timeout']
}

fn rejected(table []Scenario) string {
	validate_scenarios(table) or { return err.msg() }
	return ''
}

fn test_a_bad_table_is_reported_before_anything_boots() {
	good := Scenario{
		name:     'one'
		arches:   ['x86_64']
		required: ['HWTEST START one']
	}
	assert rejected([good]) == ''
	assert rejected([good, good]).contains('listed twice')
	assert rejected([Scenario{
		...good
		name: 'has space'
	}]).contains('letters, digits and dashes')
	assert rejected([Scenario{
		...good
		arches: ['mips']
	}]).contains('unknown architecture mips')
	assert rejected([Scenario{
		...good
		arches: []string{}
	}]).contains('no architecture')
	assert rejected([Scenario{
		...good
		required: ['HWTEST PASS one']
	}]).contains('HWTEST START')
	assert rejected([Scenario{
		...good
		required: ['HWTEST START one', 'HWTEST FAIL one']
	}]).contains('forbidden')
	assert rejected([Scenario{
		...good
		actions: [Action{
			after: 'HWTEST STEP x'
			qmp:   '{"execute":'
		}]
	}]).contains('not JSON')
	assert rejected([Scenario{
		...good
		patterns: [DiskPattern{
			disk: 'disk.raw'
		}]
	}]).contains('not one of its disks')
}

fn test_state_is_substituted() {
	assert substitute('if=ide,format=raw,file={state}/disk.raw', '/tmp/s')! == 'if=ide,format=raw,file=/tmp/s/disk.raw'
	assert substitute('{state}/a:{state}/b', '/s')! == '/s/a:/s/b'
	assert substitute('-nic', '/s')! == '-nic'
	assert substitute_all(['-drive', 'file={state}/d'], '/s')! == ['-drive', 'file=/s/d']
	// QMP text is JSON, whose braces are not placeholders.
	command := '{"execute":"blockdev-add","arguments":{"driver":"file","filename":"{state}/d"}}'
	assert substitute(command, '/s')! == '{"execute":"blockdev-add","arguments":{"driver":"file","filename":"/s/d"}}'
}

fn test_an_unknown_placeholder_is_an_error() {
	substitute('file={sate}/disk.raw', '/s') or {
		assert err.msg().contains('{sate}')
		substitute_all(['-drive', 'file={kernel}'], '/s') or {
			assert err.msg().contains('{kernel}')
			return
		}
		assert false, '{kernel} was accepted'
		return
	}
	assert false, '{sate} was accepted'
}

fn test_a_state_path_that_would_need_quoting_is_refused() {
	check_state_path('/tmp/vinix-hwtest/x86_64/ahci')!
	check_state_path('/tmp/with space/and-dash_1.2')!
	for bad in ['/tmp/a,b', '/tmp/a"b', '/tmp/a\\b', '/tmp/{state}', '/tmp/a\nb'] {
		check_state_path(bad) or { continue }
		assert false, 'accepted ${bad}'
	}
}
