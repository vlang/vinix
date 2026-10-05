// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

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

fn activity_startup_catalog_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if found := activity_startup_catalog_element(child, id) { return found }
	}
	return none
}

fn test_activity_startup_catalog_capacity_covers_every_installed_application() {
	last := available_apps.len - 1
	process := available_apps[last].process_name
	startup := '${process}\n'
	timing := '${process}\t678\n'
	defer { unsafe { startup.free() timing.free() } }
	mut model := activity_startup_parse(startup)
	defer { model.free() }
	assert model.enabled.len >= available_apps.len
	assert model.actions.len == model.enabled.len
	assert model.timing_ms.len == model.enabled.len
	assert model.timing_known.len == model.enabled.len
	assert model.timing_text.len == model.enabled.len
	assert model.enabled[last]
	for index in 0 .. last { assert !model.enabled[index] }
	activity_startup_timings_parse(mut model, timing)
	assert model.timing_known[last] && model.timing_ms[last] == 678
	model.refresh_timing_text()
	assert model.timing_text[last].len > 0
	encoded := model.encode()
	encoded_timings := model.encode_timings()
	defer { unsafe { encoded.free() encoded_timings.free() } }
	assert encoded == startup
	assert encoded_timings == timing
}

fn test_activity_startup_last_catalog_application_can_toggle_reload_and_render() {
	pid := os.getpid().str()
	base := os.temp_dir()
	home := '${base}/vinix-startup-catalog-${pid}'
	unsafe { pid.free() base.free() }
	os.mkdir(home)!
	defer { os.rmdir_all(home) or {} unsafe { home.free() } }
	last := available_apps.len - 1
	process := available_apps[last].process_name
	startup := '${process}\n'
	timing := '${process}\t456\n'
	defer { unsafe { startup.free() timing.free() } }
	assert activity_write_record(home, activity_startup_filename, startup)
	assert activity_write_record(home, activity_startup_timings_filename, timing)
	mut model := ActivityStartup{}
	defer { model.free() }
	model.load_in(home, false)
	assert model.enabled[last]
	assert model.timing_known[last] && model.timing_ms[last] == 456
	assert model.actions[last].len > 0
	for width in [240, 900]! {
		model.scroll = last
		begin_frame_elements()
		tree := model.build(width, 150)
		button := activity_startup_catalog_element(tree, model.actions[last]) or { panic('last catalog action missing') }
		assert button.frame.width > 0 && button.frame.height > 0
		assert button.text == tr('activity.startup.enabled')
		free_tree(tree)
	}
	assert model.handle(model.actions[last])
	assert !model.enabled[last] && !model.failed
	mut disabled := activity_startup_load(home, false)
	defer { disabled.free() }
	assert !disabled.enabled[last]
	assert model.handle(model.actions[last])
	assert model.enabled[last] && !model.failed
	mut restored := activity_startup_load(home, false)
	defer { restored.free() }
	assert restored.enabled[last]
	activity_startup_timings_load(mut restored, home)
	assert restored.timing_known[last] && restored.timing_ms[last] == 456
	assert model.handle('activity.startup.toggle.999999999999999999999999')
	assert model.enabled[last]
}
