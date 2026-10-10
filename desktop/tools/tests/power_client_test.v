// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

// What the kernel does with a word it takes: the file reads back with the
// chosen one in brackets, or as the profile itself.
fn mock_power_kernel(mut tree MockTree, path string, text string) {
	word := text.trim_right('\n')
	if path == power_lid_action_path {
		tree.put(path, if word == 'ignore' { 'suspend [ignore]\n' } else { '[suspend] ignore\n' })
	} else if path == power_profile_policy_path {
		tree.put(path, if word == 'manual' { 'auto [manual]\n' } else { '[auto] manual\n' })
	} else if path == power_profile_path {
		tree.put(path, word + '\n')
	}
}

// A laptop with a frequency driver: it sleeps, has a lid and takes a profile.
fn mock_power() MockTree {
	mut tree := MockTree{
		on_write: mock_power_kernel
	}
	tree.put(power_state_path, 'freeze mem\n')
	tree.put(power_suspend_success_path, '3\n')
	tree.put(power_lid_state_path, 'open\n')
	tree.put(power_lid_action_path, '[suspend] ignore\n')
	tree.put(power_profile_policy_path, '[auto] manual\n')
	tree.put(power_profile_path, 'balanced\n')
	return tree
}

// A virtual machine: no lid, and no frequency driver, so the profile file is
// read-only and a write to it is refused.
fn mock_power_vm() MockTree {
	mut tree := mock_power()
	tree.put(power_lid_state_path, 'unknown\n')
	tree.node(power_profile_path).writable = false
	tree.node(power_profile_path).write_error = .permission
	return tree
}

fn test_power_parsers_accept_only_what_the_kernel_writes() {
	assert power_words_contain('freeze mem\n'.bytes(), 'mem')
	assert power_words_contain('freeze mem\n'.bytes(), 'freeze')
	assert power_words_contain('mem\n'.bytes(), 'mem')
	assert power_words_contain('freeze mem disk\n'.bytes(), 'mem')
	assert !power_words_contain('freeze\n'.bytes(), 'mem')
	assert !power_words_contain('freeze memory\n'.bytes(), 'mem')
	for bad in ['', '\n', 'mem', 'freeze mem', ' mem\n', 'mem \n', 'freeze  mem\n', 'freeze\tmem\n',
		'freeze mem\r\n', 'freeze mem\n\n', 'Freeze mem\n', 'freeze,mem\n', '[mem]\n', 'mem\x00\n'] {
		assert !power_words_contain(bad.bytes(), 'mem'), 'took «${bad}» for a list with mem'
	}

	assert parse_power_choice('[suspend] ignore\n'.bytes(), 'suspend', 'ignore') == 0
	assert parse_power_choice('suspend [ignore]\n'.bytes(), 'suspend', 'ignore') == 1
	assert parse_power_choice('[auto] manual\n'.bytes(), 'auto', 'manual') == 0
	assert parse_power_choice('auto [manual]\n'.bytes(), 'auto', 'manual') == 1
	for bad in ['', '\n', 'suspend ignore\n', '[suspend] [ignore]\n', '[suspend] ignore',
		'[suspend]  ignore\n', ' [suspend] ignore\n', '[suspend] ignore \n', '[ignore] suspend\n',
		'ignore [suspend]\n', '[Suspend] ignore\n', '[suspend] ignore\r\n', 'suspend\n',
		'[suspend]\n', '[suspend] ignore\n[suspend] ignore\n', '[suspend ignore]\n',
		'[auto] manual\n'] {
		assert parse_power_choice(bad.bytes(), 'suspend', 'ignore') == -1, 'took «${bad}» for a choice'
	}

	assert parse_power_profile('performance\n'.bytes())? == .performance
	assert parse_power_profile('balanced\n'.bytes())? == .balanced
	assert parse_power_profile('power_saver\n'.bytes())? == .power_saver
	for bad in ['', '\n', 'balanced', 'Balanced\n', 'balanced \n', 'auto\n', 'automatic\n',
		'powersave\n', 'power-saver\n', 'balanced\nbalanced\n', '[balanced]\n'] {
		if _ := parse_power_profile(bad.bytes()) {
			assert false, 'took «${bad}» for a profile'
		}
	}
}

fn test_power_controls_on_a_laptop_a_vm_and_an_older_kernel() {
	mut laptop := mock_power()
	assert read_power_controls_with(mut laptop) == PowerControls{
		sleep:            true
		lid:              true
		lid_action:       .suspend
		profile_known:    true
		profile:          .automatic
		profile_settable: true
	}
	// Five files, each opened, read once and closed; nothing written.
	assert laptop.opens == 5 && laptop.closes == 5 && laptop.reads == 5 && laptop.live < 0
	assert laptop.writes == 0 && laptop.node(power_suspend_success_path).reads == 0

	laptop.put(power_lid_state_path, 'closed\n')
	laptop.put(power_lid_action_path, 'suspend [ignore]\n')
	laptop.put(power_profile_policy_path, 'auto [manual]\n')
	laptop.put(power_profile_path, 'power_saver\n')
	mut controls := read_power_controls_with(mut laptop)
	assert controls.lid && controls.lid_action == .ignore
	assert controls.profile_known && controls.profile == .power_saver && controls.profile_settable
	// While the kernel follows the power source, whichever profile that has
	// picked is the kernel's business: the choice shown is Automatic.
	laptop.put(power_profile_policy_path, '[auto] manual\n')
	assert read_power_controls_with(mut laptop).profile == .automatic

	mut vm := mock_power_vm()
	controls = read_power_controls_with(mut vm)
	assert controls == PowerControls{
		sleep:         true
		profile_known: true
		profile:       .automatic
	}
	// The lid's action is not read for a lid that is not there.
	assert vm.node(power_lid_action_path).reads == 0 && vm.writes == 0

	// A kernel with none of the files: nothing is offered and nothing fails.
	mut older := MockTree{}
	assert read_power_controls_with(mut older) == PowerControls{}
	assert older.live < 0 && older.closes == 0 && older.writes == 0

	// One that cannot suspend to idle or to memory.
	mut awake := mock_power()
	awake.put(power_state_path, 'disk\n')
	assert !read_power_controls_with(mut awake).sleep
}

fn test_power_controls_reject_malformed_oversized_and_failing_files() {
	oversized := 'a'.repeat(power_text_capacity) + '\n'
	for bad in ['', 'mem', 'freeze  mem\n', 'MEM\n', oversized] {
		mut tree := mock_power()
		tree.put(power_state_path, bad)
		controls := read_power_controls_with(mut tree)
		assert !controls.sleep && controls.lid && controls.profile_known, bad
	}
	for bad in ['', 'open', 'Open\n', 'ajar\n', 'open closed\n', oversized] {
		mut tree := mock_power()
		tree.put(power_lid_state_path, bad)
		controls := read_power_controls_with(mut tree)
		assert !controls.lid && controls.sleep && controls.profile_known, bad
	}
	for bad in ['', 'suspend\n', 'suspend ignore\n', '[sleep] ignore\n', oversized] {
		mut tree := mock_power()
		tree.put(power_lid_action_path, bad)
		assert !read_power_controls_with(mut tree).lid, bad
	}
	for bad in ['', 'auto\n', 'auto manual\n', '[automatic] manual\n', oversized] {
		mut tree := mock_power()
		tree.put(power_profile_policy_path, bad)
		controls := read_power_controls_with(mut tree)
		assert !controls.profile_known && !controls.profile_settable && controls.lid, bad
		// The profile is not read under a policy nobody can make out.
		assert tree.node(power_profile_path).reads == 0
	}
	for bad in ['', 'balanced', 'fast\n', '[balanced]\n', oversized] {
		mut tree := mock_power()
		tree.put(power_profile_path, bad)
		controls := read_power_controls_with(mut tree)
		assert !controls.profile_known && !controls.profile_settable, bad
	}
	for path in [power_state_path, power_lid_state_path, power_lid_action_path,
		power_profile_policy_path, power_profile_path] {
		for failure in [DeviceError.unavailable, .permission, .io] {
			mut tree := mock_power()
			tree.node(path).open_error = failure
			mut controls := read_power_controls_with(mut tree)
			assert tree.live < 0 && tree.writes == 0
			assert controls.sleep == (path != power_state_path)
			assert controls.lid == (path !in [power_lid_state_path, power_lid_action_path])
			assert controls.profile_known == (path !in [power_profile_policy_path, power_profile_path])
			tree = mock_power()
			tree.node(path).read_error = failure
			controls = read_power_controls_with(mut tree)
			assert tree.live < 0 && tree.opens == tree.closes
			assert controls.sleep == (path != power_state_path)
			tree = mock_power()
			tree.node(path).close_error = .io
			controls = read_power_controls_with(mut tree)
			assert tree.live < 0
			assert controls.sleep == (path != power_state_path)
			assert controls.profile_known == (path !in [power_profile_policy_path, power_profile_path])
		}
	}
	// Interrupted opens and reads are retried, and not without end.
	mut tree := mock_power()
	tree.interrupted_opens = 3
	tree.interrupted_reads = 3
	assert read_power_controls_with(mut tree).profile_known
	tree = mock_power()
	tree.interrupted_opens = 1000
	assert read_power_controls_with(mut tree) == PowerControls{}
	assert tree.opens == 3 * 16 && tree.closes == 0
	tree = mock_power()
	tree.interrupted_reads = 1000
	assert read_power_controls_with(mut tree) == PowerControls{}
	assert tree.reads == 3 * power_retries && tree.opens == tree.closes
}

fn test_lid_action_is_one_whole_word() {
	mut tree := mock_power()
	assert set_lid_action_with(mut tree, .ignore) == .ok
	assert tree.log == ['${power_lid_action_path}=ignore\n']
	assert tree.opens == 1 && tree.closes == 1 && tree.writes == 1 && tree.live < 0
	assert read_power_controls_with(mut tree).lid_action == .ignore
	assert set_lid_action_with(mut tree, .suspend) == .ok
	assert tree.log.len == 2 && tree.log[1] == '${power_lid_action_path}=suspend\n'
	assert read_power_controls_with(mut tree).lid_action == .suspend

	for failure in [DeviceError.unavailable, .permission, .io] {
		tree = mock_power()
		tree.node(power_lid_action_path).open_error = failure
		assert set_lid_action_with(mut tree, .ignore) == power_io_result(failure)
		assert tree.writes == 0 && tree.closes == 0 && tree.live < 0
		tree = mock_power()
		tree.node(power_lid_action_path).write_error = failure
		assert set_lid_action_with(mut tree, .ignore) == power_io_result(failure)
		assert tree.writes == 1 && tree.closes == 1 && tree.live < 0 && tree.log.len == 0
	}
	// A short write is an error; its rest is not sent as another word.
	tree = mock_power()
	tree.short_write = true
	assert set_lid_action_with(mut tree, .ignore) == .io
	assert tree.writes == 1 && tree.closes == 1
	tree = mock_power()
	tree.interrupted_opens = 3
	tree.interrupted_writes = 3
	assert set_lid_action_with(mut tree, .ignore) == .ok
	assert tree.opens == 4 && tree.writes == 4 && tree.log.len == 1
	tree = mock_power()
	tree.interrupted_writes = 1000
	assert set_lid_action_with(mut tree, .ignore) == .io
	assert tree.writes == power_retries && tree.closes == 1 && tree.log.len == 0
	tree = mock_power()
	tree.interrupted_opens = 1000
	assert set_lid_action_with(mut tree, .ignore) == .io
	assert tree.opens == 16 && tree.writes == 0
	// A kernel without the file.
	mut older := MockTree{}
	assert set_lid_action_with(mut older, .ignore) == .unavailable
	assert write_power_word_with(mut tree, power_lid_action_path, '') == .invalid
	assert write_power_word_with(mut tree, power_lid_action_path, 'x'.repeat(power_text_capacity)) == .invalid
}

fn test_power_profile_writes_the_policy_then_the_profile() {
	// Automatic is the policy alone.
	mut tree := mock_power()
	tree.put(power_profile_policy_path, 'auto [manual]\n')
	assert set_power_profile_with(mut tree, .automatic) == .ok
	assert tree.log == ['${power_profile_policy_path}=auto\n']
	assert read_power_controls_with(mut tree).profile == .automatic

	for profile in [PowerProfile.performance, .balanced, .power_saver] {
		tree = mock_power()
		assert set_power_profile_with(mut tree, profile) == .ok
		assert tree.log == ['${power_profile_policy_path}=manual\n', '${power_profile_path}=${profile.code()}\n']
		controls := read_power_controls_with(mut tree)
		assert controls.profile == profile && controls.profile_settable
		assert tree.live < 0 && tree.opens == tree.closes
	}

	// A kernel that takes no profile says so in the file's mode: nothing is
	// written, and its policy is not turned to manual for nothing.
	mut vm := mock_power_vm()
	assert set_power_profile_with(mut vm, .performance) == .permission
	assert vm.writes == 0 && vm.log.len == 0
	assert read_power_controls_with(mut vm).profile == .automatic
	// Automatic is still the kernel's to take.
	assert set_power_profile_with(mut vm, .automatic) == .ok
	assert vm.log == ['${power_profile_policy_path}=auto\n']

	// The mode said yes and the write was refused all the same: the policy
	// that was there is put back.
	for failure in [DeviceError.permission, .io, .unavailable] {
		tree = mock_power()
		tree.node(power_profile_path).write_error = failure
		assert set_power_profile_with(mut tree, .performance) == power_io_result(failure)
		assert tree.log == ['${power_profile_policy_path}=manual\n', '${power_profile_policy_path}=auto\n']
		assert read_power_controls_with(mut tree).profile == .automatic
		// It was manual before, so it stays manual with the profile it had.
		tree = mock_power()
		tree.put(power_profile_policy_path, 'auto [manual]\n')
		tree.node(power_profile_path).write_error = failure
		assert set_power_profile_with(mut tree, .performance) == power_io_result(failure)
		assert tree.log == ['${power_profile_policy_path}=manual\n']
		assert read_power_controls_with(mut tree).profile == .balanced
	}
	// The policy itself refused: the profile is not written after it.
	tree = mock_power()
	tree.node(power_profile_policy_path).write_error = .permission
	assert set_power_profile_with(mut tree, .balanced) == .permission
	assert tree.log.len == 0 && tree.node(power_profile_path).written.len == 0
	// No profile files at all.
	mut older := MockTree{}
	assert set_power_profile_with(mut older, .balanced) == .unavailable
	assert set_power_profile_with(mut older, .automatic) == .unavailable
	assert older.writes == 0
}

fn test_saved_power_settings_are_put_back_only_where_they_differ() {
	// A fresh kernel and untouched settings agree: nothing is written.
	mut tree := mock_power()
	apply_power_settings_with(mut tree, &Settings{})
	assert tree.writes == 0 && tree.live < 0

	saved := Settings{
		lid_action:    .ignore
		power_profile: .power_saver
	}
	apply_power_settings_with(mut tree, &saved)
	assert tree.log == ['${power_lid_action_path}=ignore\n', '${power_profile_policy_path}=manual\n',
		'${power_profile_path}=power_saver\n']
	controls := read_power_controls_with(mut tree)
	assert controls.lid_action == .ignore && controls.profile == .power_saver
	// Applied again, as a restarted desktop does, it finds nothing to do.
	apply_power_settings_with(mut tree, &saved)
	assert tree.log.len == 3

	// A kernel left on a manual profile, and settings that say Automatic.
	apply_power_settings_with(mut tree, &Settings{
		lid_action: .ignore
	})
	assert tree.log.len == 4 && tree.log[3] == '${power_profile_policy_path}=auto\n'

	// A virtual machine has no lid and takes no profile: nothing is written,
	// whatever was saved on the machine the settings came from.
	mut vm := mock_power_vm()
	apply_power_settings_with(mut vm, &saved)
	assert vm.writes == 0 && vm.live < 0
	mut older := MockTree{}
	apply_power_settings_with(mut older, &saved)
	assert older.writes == 0 && older.live < 0
}

fn test_suspend_successes_are_a_count_or_nothing() {
	mut tree := mock_power()
	assert read_suspend_successes_with(mut tree)? == 3
	tree.put(power_suspend_success_path, '4\n')
	assert read_suspend_successes_with(mut tree)? == 4
	for bad in ['', '4', 'four\n', '-1\n', '4 \n'] {
		tree.put(power_suspend_success_path, bad)
		if _ := read_suspend_successes_with(mut tree) {
			assert false, 'took «${bad}» for a count'
		}
	}
	mut older := MockTree{}
	if _ := read_suspend_successes_with(mut older) {
		assert false, 'counted sleeps on a kernel that has no count'
	}
	assert tree.live < 0 && tree.writes == 0
}
