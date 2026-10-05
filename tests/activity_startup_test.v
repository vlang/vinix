// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn startup_index(process string) int {
	for index, app in available_apps { if app.process_name == process { return index } }
	return -1
}

fn test_activity_startup_defaults_and_stable_process_names() {
	files := startup_index('vinix-files')
	terminal := startup_index('vinix-terminal')
	assert files >= 0 && terminal >= 0
	production := activity_startup_defaults(false)
	development := activity_startup_defaults(true)
	assert production.enabled[files]
	assert !production.enabled[terminal]
	assert development.enabled[files] && development.enabled[terminal]
	mut parsed := activity_startup_parse('vinix-terminal\nunknown-app\nvinix-terminal\nvinix-files\n')
	defer { parsed.free() }
	assert parsed.enabled[files] && parsed.enabled[terminal]
	for index, _ in available_apps {
		if index != files && index != terminal {
			assert !parsed.enabled[index]
		}
	}
	encoded := parsed.encode()
	defer { unsafe { encoded.free() } }
	restored := activity_startup_parse(encoded)
	assert restored.enabled == parsed.enabled
}

fn test_activity_startup_timings_reject_corrupt_values_and_keep_zero_valid() {
	files := startup_index('vinix-files')
	terminal := startup_index('vinix-terminal')
	mut model := ActivityStartup{}
	defer { model.free() }
	activity_startup_timings_parse(mut model, 'vinix-files\t0\nvinix-terminal\t1055\nunknown\t7\nvinix-files\t-1\nvinix-terminal\tbroken\nvinix-files\t18446744073709551616\nvinix-terminal\t4 9\n')
	assert model.timing_known[files] && model.timing_ms[files] == 0
	assert model.timing_known[terminal] && model.timing_ms[terminal] == 1055
	assert !model.enabled[files] && !model.enabled[terminal]
	data := model.encode_timings()
	defer { unsafe { data.free() } }
	assert data.contains('vinix-files\t0\n')
	assert data.contains('vinix-terminal\t1055\n')
	mut restored := ActivityStartup{}
	defer { restored.free() }
	activity_startup_timings_parse(mut restored, data)
	assert restored.timing_ms == model.timing_ms
	assert restored.timing_known == model.timing_known
	model.refresh_timing_text()
	zero_text := tr_fill('activity.startup.launch_ms', '0')
	measured_text := tr_fill('activity.startup.launch_ms', '1055')
	defer { unsafe {
		zero_text.free()
		measured_text.free()
	}
	 }
	assert model.timing_text[files] == zero_text
	assert model.timing_text[terminal] == measured_text
}

fn test_activity_startup_atomic_roundtrip_and_toggle_use_model_home() {
	home := os.join_path(os.temp_dir(), 'vinix-activity-startup-tests')
	defer { unsafe { home.free() } }
	os.mkdir_all(home)!
	config_path := os.join_path(home, activity_startup_filename)
	timing_path := os.join_path(home, activity_startup_timings_filename)
	defer {
		os.rm(config_path) or {}
		os.rm(timing_path) or {}
		os.rmdir(home) or {}
		unsafe {
			config_path.free()
			timing_path.free()
		}
	}
	assert activity_write_record(home, activity_startup_filename, 'vinix-files\n')
	assert activity_write_record(home, activity_startup_timings_filename, 'vinix-files\t438\n')
	mut model := ActivityStartup{}
	defer { model.free() }
	model.load_in(home, false)
	files := startup_index('vinix-files')
	assert model.loaded && model.home == home
	assert model.enabled[files]
	assert model.timing_known[files] && model.timing_ms[files] == 438
	assert model.handle(model.actions[files])
	assert !model.enabled[files] && !model.failed
	reloaded := activity_startup_load(home, false)
	assert !reloaded.enabled[files]
	assert os.read_file(timing_path)! == 'vinix-files\t438\n'
	assert model.handle('activity.startup.toggle.-1')
	assert model.handle('activity.startup.toggle.999999999999999')
	assert !model.handle('unrelated')
	tree := model.build(900, 540)
	free_tree(tree)
	assert !activity_write_record(home, '../missing/no-file', 'new data')
}

fn test_activity_startup_does_not_load_symlinked_user_records() {
	home := os.join_path(os.temp_dir(), 'vinix-activity-startup-links')
	defer { unsafe { home.free() } }
	os.mkdir_all(home)!
	target := os.join_path(home, 'target')
	config := os.join_path(home, activity_startup_filename)
	timings := os.join_path(home, activity_startup_timings_filename)
	defer {
		os.rm(config) or {}
		os.rm(timings) or {}
		os.rm(target) or {}
		os.rmdir(home) or {}
		unsafe {
			target.free()
			config.free()
			timings.free()
		}
	}
	os.write_file(target, 'vinix-terminal\n')!
	os.symlink(target, config)!
	os.symlink(target, timings)!
	mut model := activity_startup_load(home, false)
	defer { model.free() }
	assert model.enabled[startup_index('vinix-files')]
	assert !model.enabled[startup_index('vinix-terminal')]
	activity_startup_timings_load(mut model, home)
	assert !model.timing_known[startup_index('vinix-terminal')]
}
