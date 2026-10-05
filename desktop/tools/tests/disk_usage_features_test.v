// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

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
