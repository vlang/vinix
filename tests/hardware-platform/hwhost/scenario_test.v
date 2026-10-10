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
	// So is suspend to disk.
	for name in ['hibernate', 'hibernate-xapic', 'hibernate-iommu', 'hibernate-iommu-amd', 'hibernate-cycles',
		'hibernate-damaged-header', 'hibernate-damaged-pages', 'hibernate-memory', 'hibernate-unnamed',
		'hibernate-foreign'] {
		assert name in names_of(x86.run)
		assert name !in names_of(arm.run)
	}
}

// The Apple SMC scenarios need a kernel with a simulated SMC in it: none is
// in a default run, each can be named, and none runs on a PC.
fn test_the_apple_smc_scenarios_are_run_only_when_named() {
	names := ['apple-smc-selftest', 'apple-smc-selftest-bare', 'apple-smc-selftest-options',
		'apple-smc-selftest-legacy']
	arm := select_scenarios(scenarios, 'aarch64', []string{})!
	for name in names {
		assert name !in names_of(arm.run)
		assert name in names_of(arm.skipped)
		scenario := find_scenario(scenarios, name) or { panic('no ${name} scenario') }
		assert scenario.define == 'applesmc_selftest'
		assert scenario.arches == ['aarch64']
	}
	named := select_scenarios(scenarios, 'aarch64', names)!
	assert names_of(named.run) == names
	select_scenarios(scenarios, 'x86_64', ['apple-smc-selftest']) or {
		assert err.msg().contains('does not run on x86_64')
		return
	}
	assert false, 'apple-smc-selftest was selected on x86_64'
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

fn test_an_action_can_hold_qemu_to_its_answer() {
	look := Action{
		after:      'HWTEST STEP look'
		qmp:        '{"execute":"human-monitor-command","arguments":{"command-line":"info mtree -f"}}'
		answer_has: 'e1000e-mmio'
	}
	assert answer_fault(look, '{"return": "  00000000fea00000-00000000fea1ffff (prio 1, i/o): e1000e-mmio\\r\\n"}') == ''
	assert answer_fault(look, '{"return": "  00000000fea00000-00000000fea1ffff (prio 1, i/o): vga.mmio\\r\\n"}').contains('does not hold "e1000e-mmio"')
	gone := Action{
		...look
		answer_has:   ''
		answer_lacks: 'e1000e-mmio'
	}
	assert answer_fault(gone, '{"return": "vga.mmio"}') == ''
	assert answer_fault(gone, '{"return": "e1000e-mmio"}').contains('holds "e1000e-mmio"')
	// An action that asks nothing of the answer takes any.
	assert answer_fault(Action{ after: 'x', qmp: '{"execute":"stop"}' }, '{"return": {}}') == ''
}

fn test_the_d3_scenarios_look_at_the_card_in_the_middle_of_each_sleep() {
	d3 := find_scenario(scenarios, 'pci-d3') or { panic('no pci-d3 scenario') }
	asleep := d3.actions.filter(it.answer_lacks != '')
	awake := d3.actions.filter(it.answer_has != '')
	assert asleep.len == 2 && awake.len == 3
	for action in asleep {
		assert action.delay_ms == d3_look_after_ms && action.answer_lacks == d3_card_memory
	}
	// The same machine told not to: the card must still be there.
	off := find_scenario(scenarios, 'pci-d3-off') or { panic('no pci-d3-off scenario') }
	assert off.cmdline.contains('vinix.pci_d3=off')
	assert off.actions.len == 1 && off.actions[0].answer_has == d3_card_memory
}

fn test_the_wake_scenarios_read_the_enable_register_while_the_machine_is_suspended() {
	wake := find_scenario(scenarios, 'suspend-deep-wake') or { panic('no suspend-deep-wake scenario') }
	looks := wake.actions.filter(it.event == 'SUSPEND')
	assert looks.len == 2
	assert looks[0].event_count == 1 && looks[0].answer_has == wake_both
	assert looks[1].event_count == 2 && looks[1].answer_has == wake_button_only
	// Lid and button on, both off, the button alone on and off.
	assert wake.writings.len == 1 && wake.writings[0].text == 'LS33lsS33s'
	off := find_scenario(scenarios, 'suspend-deep-wake-off') or {
		panic('no suspend-deep-wake-off scenario')
	}
	assert off.cmdline.contains('vinix.acpi_wake=off')
	assert off.actions.len == 1 && off.actions[0].answer_has == wake_none
	assert off.writings.len == 1 && off.writings[0].text == ''
}

fn test_a_writing_that_nothing_writes_is_refused() {
	assert rejected([
		Scenario{
			name:     'one'
			arches:   ['x86_64']
			required: ['HWTEST START one']
			writings: [Writing{
				file: 'said.txt'
				text: 'a'
			}]
		},
	]).contains('nothing writes said.txt')
	assert rejected([
		Scenario{
			name:     'one'
			arches:   ['x86_64']
			qemu:     ['-chardev', 'file,id=c,path={state}/said.txt']
			required: ['HWTEST START one']
			writings: [Writing{
				file: 'said.txt'
				text: 'a'
			}]
		},
	]) == ''
}
