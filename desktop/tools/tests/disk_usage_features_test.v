// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn disk_usage_capacity_test_has_text(tree ui2.Element, text string) bool {
	if tree.text == text { return true }
	for child in tree.children {
		if disk_usage_capacity_test_has_text(child, text) { return true }
	}
	return false
}

fn test_disk_usage_capacity_validates_reserved_space_unknown_and_overflow() {
	capacity := disk_usage_capacity(4096, 100, 40, 30)
	assert capacity.valid
	assert capacity.total == 409600
	assert capacity.used == 245760
	assert capacity.free == 163840
	assert capacity.available == 122880
	full := disk_usage_capacity(4096, 100, 0, 0)
	assert full.valid && full.used == full.total
	for invalid in [disk_usage_capacity(0, 100, 40, 30),
		disk_usage_capacity(4096, 0, 0, 0),
		disk_usage_capacity(4096, 100, 101, 30),
		disk_usage_capacity(4096, 100, 40, 41),
		disk_usage_capacity(4096, ~u64(0), 0, 0)]! {
		assert !invalid.valid
		assert invalid.total == 0 && invalid.used == 0 && invalid.free == 0 && invalid.available == 0
	}
}

fn test_disk_usage_capacity_scan_refresh_views_and_report_remain_distinct() {
	root := os.join_path(os.temp_dir(), 'vinix-disk-usage-capacity-${os.getpid()}')
	file := join_path(root, 'five-bytes.txt')
	os.mkdir_all(root)!
	os.write_file(file, '12345')!
	defer { os.rmdir_all(root) or {} unsafe { root.free(); file.free() } }
	mut app := DiskUsageApp{}
	defer { app.close_app() }
	app.scan(root)
	for _ in 0 .. 1000 { if !app.poll() { break } }
	assert app.scanner.total_bytes == 5
	assert app.scanner.capacity.valid
	assert app.scanner.capacity.total >= app.scanner.capacity.used
	assert app.scanner.capacity.free >= app.scanner.capacity.available
	app.handle(disk_usage_action_capacity)!
	assert app.capacity_view
	app.scanner.capacity = disk_usage_capacity(1, 1000, 400, 300)
	bytes := app.scanner.report_csv()
	text := disk_usage_buffer_text(bytes)
	assert text.contains('filesystem_total,"' + root + '",1000\n')
	assert text.contains('filesystem_used,"' + root + '",600\n')
	assert text.contains('filesystem_free,"' + root + '",400\n')
	assert text.contains('filesystem_available,"' + root + '",300\n')
	assert text.contains('root,"' + root + '",5\n')
	unsafe { bytes.free() }
	app.handle(disk_usage_action_rescan)!
	assert app.capacity_view && app.scanner.capacity.valid
	assert app.scanner.capacity.total != 1000
	app.scan('/vinix-disk-usage-capacity-missing')
	assert !app.scanner.capacity.valid
	missing := app.scanner.report_csv()
	assert disk_usage_buffer_text(missing).contains('filesystem_capacity_unavailable,"/vinix-disk-usage-capacity-missing",0\n')
	assert !disk_usage_buffer_text(missing).contains('filesystem_total,')
	unsafe { missing.free() }
	app.handle(disk_usage_action_inventory)!
	assert !app.capacity_view
}

fn test_disk_usage_capacity_localized_cards_compact_layout_and_unknown_state() {
	previous := desktop_language
	defer { set_desktop_language(previous) }
	mut app := DiskUsageApp{capacity_view: true}
	app.scanner.capacity = disk_usage_capacity(1, 1000, 400, 300)
	defer { app.close_app() }
	for language in [DesktopLanguage.en, .es, .ru]! {
		set_desktop_language(language)
		for size in [ui2.rect(0, 0, 880, 546), ui2.rect(0, 0, 400, 250)]! {
			begin_frame_elements()
			tree := app.build(size)!
			for key in ['disk_usage.capacity.total', 'disk_usage.capacity.used',
				'disk_usage.capacity.free', 'disk_usage.capacity.available']! {
				assert disk_usage_capacity_test_has_text(tree, tr(key))
			}
			for value in [u64(1000), 600, 400, 300]! {
				formatted := disk_usage_size_text(value)
				assert disk_usage_capacity_test_has_text(tree, formatted)
				unsafe { formatted.free() }
			}
			for child in tree.children {
				assert child.frame.x >= 0 && child.frame.y >= 0
				assert child.frame.x + child.frame.width <= size.width
				assert child.frame.y + child.frame.height <= size.height
			}
			free_tree(tree)
		}
	}
	app.scanner.capacity = DiskUsageCapacity{}
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 400, 250))!
	assert disk_usage_capacity_test_has_text(tree, tr('disk_usage.capacity.unavailable'))
	zero := disk_usage_size_text(0)
	assert !disk_usage_capacity_test_has_text(tree, zero)
	unsafe { zero.free() }
	free_tree(tree)
	begin_frame_elements()
	tiny := app.build(ui2.rect(0, 0, 180, 96))!
	assert disk_usage_capacity_test_has_text(tiny, tr('disk_usage.capacity.resize'))
	free_tree(tiny)
}

fn test_disk_usage_exports_quoted_raw_byte_report_without_overwriting() {
	root := os.join_path(os.temp_dir(), 'vinix-disk-usage-report-features')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	file := os.join_path(root, 'a,"b\nc.bin')
	os.write_file(file, '12345')!
	mut app := DiskUsageApp{}
	defer { app.close_app() }
	app.scan(root)
	for _ in 0 .. 1000 {
		if !app.poll() { break }
	}
	assert app.scanner.phase == .complete
	assert app.scanner.total_bytes == 5
	report := os.join_path(root, 'report.csv')
	app.focus = .report
	app.paste_input(report)
	app.export_report()
	assert app.report_status == 'disk_usage.report.saved'
	csv := os.read_file(report)!
	assert csv.starts_with('kind,path,bytes\n')
	assert csv.contains('phase,"complete",0\n')
	assert csv.contains('file_count,"",1\n')
	assert csv.contains('a,""b\nc.bin",5\n')
	app.export_report()
	assert app.report_status == 'disk_usage.report.exists'
	assert os.read_file(report)! == csv
	assert !disk_usage_write_report(report, [u8(`x`)])
	assert os.read_file(report)! == csv
}

fn test_disk_usage_custom_scan_path_input_and_utf8_backspace() {
	root := os.join_path(os.temp_dir(), 'vinix-disk-usage-path-features')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	mut app := DiskUsageApp{}
	defer { app.close_app() }
	app.scan('/')
	app.key_input('\x0c')
	app.paste_input(root)
	app.key_input('Ж\x7f\x1b[3~\r')
	assert app.scanner.root == root
	assert app.scanner.phase == .scanning
	assert app.focus == .none_
	app.scanner.cancel()
	app.report_path.clear()
	app.focus = .report
	app.paste_input(os.join_path(root, 'partial.csv'))
	app.key_input('\n')
	assert app.report_status == 'disk_usage.report.saved'
	csv := os.read_file(os.join_path(root, 'partial.csv'))!
	assert csv.contains('phase,"cancelled",0\n')
}

fn test_disk_usage_default_report_uses_registered_user_home() {
	previous := desktop_user_home
	defer { desktop_user_home = previous }
	desktop_user_home = '/home/report-owner'
	registered := disk_usage_default_report_path()
	assert registered == '/home/report-owner/disk-usage.csv'
	unsafe { registered.free() }
	desktop_user_home = ''
	fallback := disk_usage_default_report_path()
	expected := join_path(desktop_home, disk_usage_report_filename)
	assert fallback == expected
	unsafe {
		fallback.free()
		expected.free()
	}
}
