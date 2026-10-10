// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

fn names_of(list []Scenario) []string {
	return list.map(it.name)
}

fn test_the_table_is_valid() {
	validate_scenarios(scenarios)!
}

// A table of its own, so that what these say about pending scenarios does not
// depend on which real ones happen to be pending today.
const sample = [
	Scenario{
		name:   'both'
		arches: ['aarch64', 'x86_64']
	},
	Scenario{
		name:   'pc'
		arches: ['x86_64']
	},
	Scenario{
		name:    'later'
		arches:  ['aarch64', 'x86_64']
		pending: 'not written yet'
	},
]

fn test_default_selection_is_what_applies_and_is_not_pending() {
	arm := select_scenarios(sample, 'aarch64', []string{})!
	assert names_of(arm.run) == ['both']
	assert names_of(arm.skipped) == ['later']
	x86 := select_scenarios(sample, 'x86_64', []string{})!
	assert names_of(x86.run) == ['both', 'pc']
	assert names_of(x86.skipped) == ['later']
}

fn test_a_named_scenario_runs_even_when_pending() {
	selection := select_scenarios(sample, 'aarch64', ['later'])!
	assert names_of(selection.run) == ['later']
	assert selection.skipped.len == 0
}

fn test_every_real_scenario_runs_somewhere() {
	arm := select_scenarios(scenarios, 'aarch64', []string{})!
	x86 := select_scenarios(scenarios, 'x86_64', []string{})!
	assert 'devices' in names_of(arm.run)
	assert 'suspend' in names_of(arm.run)
	assert 'ahci' !in names_of(arm.run)
	assert 'ahci' in names_of(x86.run)
	assert 'restart' in names_of(x86.run)
	// Suspend to RAM is a PC's: every flavour of it runs there by default,
	// and none on the other architecture.
	for name in ['suspend-deep', 'suspend-deep-xapic', 'suspend-deep-bridge', 'suspend-deep-iommu', 'suspend-deep-iommu-amd',
		'suspend-deep-arrival', 'suspend-deep-departure', 'suspend-deep-undrawable', 'suspend-deep-forced',
		'suspend-deep-headless'] {
		assert name in names_of(x86.run)
		assert name !in names_of(arm.run)
	}
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

fn test_an_action_that_waits_for_an_event_says_which_and_how_many() {
	good := Scenario{
		name:     'one'
		arches:   ['x86_64']
		required: ['HWTEST START one']
	}
	assert rejected([Scenario{
		...good
		actions: [Action{
			after:       'HWTEST STEP x'
			qmp:         '{"execute":"system_wakeup"}'
			event:       'SUSPEND'
			event_count: 1
		}]
	}]) == ''
	assert rejected([Scenario{
		...good
		actions: [Action{
			after: 'HWTEST STEP x'
			qmp:   '{"execute":"system_wakeup"}'
			event: 'SUSPEND'
		}]
	}]).contains('names it and says how many')
	shot := Action{
		after: 'HWTEST STEP y'
		qmp:   '{"execute":"screendump","arguments":{"filename":"{state}/a.ppm"}}'
	}
	assert rejected([Scenario{
		...good
		actions: [shot]
		screens: [Screen{
			file:    'a.ppm'
			pattern: 16
		}]
	}]) == ''
	assert rejected([Scenario{
		...good
		actions: [shot]
		screens: [Screen{
			file:    'a.ppm'
			dark:    true
			pattern: 16
		}]
	}]).contains('cannot be dark and show a pattern')
	assert rejected([Scenario{
		...good
		actions: [shot]
		screens: [Screen{
			file: 'a.ppm'
			like: 'b.ppm'
		}]
	}]).contains('not one of its pictures')
}

fn test_the_deep_sleep_scenarios_wake_the_machine_only_once_it_is_suspended() {
	deep := find_scenario(scenarios, 'suspend-deep') or { panic('no suspend-deep scenario') }
	mut wakes := 0
	for action in deep.actions {
		if action.qmp.contains('system_wakeup') {
			assert action.event == 'SUSPEND' && action.event_count > 0
			wakes++
		}
	}
	assert wakes == 1
	assert deep.events.filter(it == 'SUSPEND').len == 8
	assert deep.events.filter(it == 'WAKEUP').len == 8
	// What the guest reads once each was put there by the host.
	assert deep.disks[0].prefill.len == 4
}
