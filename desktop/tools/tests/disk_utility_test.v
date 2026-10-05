// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn disk_utility_test_tree_has(tree ui2.Element, text string) bool {
	if tree.text == text { return true }
	for child in tree.children { if disk_utility_test_tree_has(child, text) { return true } }
	return false
}

fn disk_utility_test_tree_has_row_button(tree ui2.Element, action string) bool {
	if tree.action_id == action && tree.kind == .button { return true }
	for child in tree.children { if disk_utility_test_tree_has_row_button(child, action) { return true } }
	return false
}

fn test_disk_utility_capacity_rejects_unpublished_and_inconsistent_values() {
	assert disk_utility_capacity(0, 1, 0, 0) == none
	assert disk_utility_capacity(4096, 0, 0, 0) == none
	assert disk_utility_capacity(4096, 20, 21, 0) == none
	assert disk_utility_capacity(4096, 20, 10, 11) == none
	assert disk_utility_capacity(u64(-1), 2, 1, 1) == none
	values := disk_utility_capacity(4096, 100, 40, 30) or { panic('valid capacity rejected') }
	assert values == [u64(409600), 245760, 122880]!
	full := disk_utility_capacity(4096, 100, 0, 0) or { panic('valid full capacity rejected') }
	assert full == [u64(409600), 409600, 0]!
}

fn test_disk_utility_mount_escape_validation_and_incomplete_rows() {
	decoded := disk_utility_mount_field('/mnt/space\\040tab\\011line\\012slash\\134') or { panic('valid escape rejected') }
	assert decoded == '/mnt/space tab\tline\nslash\\'
	unsafe { decoded.free() }
	for invalid in ['/mnt\\000bad', '/mnt\\999bad', '/mnt\\04', '/mnt\x00bad']! {
		assert disk_utility_mount_field(invalid) == none
	}
	mut app := DiskUtilityApp{}
	app.prepare_snapshot()
	defer { app.close_app() }
	app.parse_mounts('tmpfs /safe tmpfs rw 0 0\n/dev/bad /mnt\\000bad ext2 rw 0 0\n/dev/partial /partial ext2 rw', true)
	assert app.mounts.len == 1
	assert app.mounts[0].target == '/safe'
	assert app.limited
}

fn test_disk_utility_refresh_reads_real_mount_sources_and_replaces_snapshot() {
	root := os.join_path(os.temp_dir(), 'vinix-disk-utility-fixture-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	volume := disk_utility_join_path(root, 'volume space')
	report := disk_utility_join_path(root, 'mounts')
	regular := disk_utility_join_path(root, 'sda')
	defer { unsafe { volume.free(); report.free(); regular.free() } }
	os.mkdir(volume)!
	os.write_file(regular, 'A regular file must not be a block device.')!
	escaped := volume.replace(' ', '\\040')
	data := '/dev/test0 ${escaped} ext2 rw,nosuid 0 0\n/dev/missing /missing-vinix-volume ext2 ro 0 0\n'
	os.write_file(report, data)!
	unsafe { escaped.free(); data.free() }
	mut app := DiskUtilityApp{}
	defer { app.close_app() }
	app.refresh_sources(DiskUtilitySources{devices: root, mounts: report})
	assert app.initialized
	assert app.devices.len == 0
	assert !app.devices_unavailable
	assert app.mounts.len == 2
	assert app.mounts[0].source == '/dev/test0'
	assert app.mounts[0].target == volume
	assert app.mounts[0].filesystem == 'ext2'
	assert app.mounts[0].options == 'rw,nosuid'
	assert app.mounts[0].capacity_valid
	assert app.mounts[0].capacity[0] > 0
	assert !app.mounts[1].capacity_valid
	app.refresh_sources(DiskUtilitySources{devices: '/missing-vinix-devices', mounts: '/missing-vinix-mounts'})
	assert app.devices.len == 0 && app.mounts.len == 0
	assert app.devices_unavailable && app.mounts_unavailable
}

fn test_disk_utility_block_metadata_and_bounded_inventory_selection() {
	mut app := DiskUtilityApp{}
	app.prepare_snapshot()
	app.initialized = true
	defer { app.close_app() }
	app.device_metadata('/dev/regular', u32(C.S_IFREG), 100)
	app.device_metadata('/dev/symlink', u32(C.S_IFLNK), 100)
	app.device_metadata('/dev/character', u32(C.S_IFCHR), 100)
	assert app.devices.len == 0
	app.device_metadata('/dev/nvme0n1', u32(C.S_IFBLK), 1073741824)
	app.device_metadata('/dev/nvme0n1p0', u32(C.S_IFBLK), 536870912)
	app.device_metadata('/dev/unknown-size', u32(C.S_IFBLK), -1)
	assert app.devices.len == 3
	assert app.devices[0].bytes == 1073741824
	assert app.devices[1].bytes == 536870912
	assert app.devices[2].bytes == 0
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 780, 560))!
	assert disk_utility_test_tree_has_row_button(tree, 'disk_utility.row.1')
	free_tree(tree)
	for _ in 0 .. 300 { app.device_metadata('/dev/bounded', u32(C.S_IFBLK), 512) }
	assert app.devices.len == disk_utility_row_limit
	assert app.limited
	app.visible_rows = 5
	app.handle('disk_utility.next')!
	assert app.page[0] == 5
	app.handle('disk_utility.row.2')!
	assert app.selected[0] == 7
	app.key_input('\x1b[F')
	assert app.selected[0] == disk_utility_row_limit - 1
	assert app.page[0] == disk_utility_row_limit - 5
	app.key_input('\x1b[H')
	assert app.selected[0] == 0 && app.page[0] == 0
	repeated := 'x'.repeat(513)
	long := '/dev/' + repeated
	app.clear_snapshot()
	app.device_metadata(long, u32(C.S_IFBLK), 512)
	assert app.devices.len == 0 && app.limited
	unsafe { long.free(); repeated.free() }
}

fn test_disk_utility_native_interfaces_export_exact_shortened_utf8_path() {
	root := os.join_path(os.temp_dir(), 'vinix-disk-utility-native-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := disk_utility_join_path(root, 'report-Ж.txt')
	long := path + '.long'
	defer { unsafe { path.free(); long.free() } }
	mut desktop := Desktop{}
	mut app := open_disk_utility(mut desktop)!
	defer { if mut app is ClosingApp { app.close_app() } }
	app.handle('disk_utility.path')!
	if mut app is PastingApp { mut paster := PastingApp(app); paster.paste_input(long) }
	if mut app is KeyboardApp { mut keyboard := KeyboardApp(app); for _ in 0 .. 5 { keyboard.key_input('\x7f') } }
	app.handle('disk_utility.export')!
	assert os.exists(path)
	assert !os.exists(long)
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 780, 560))!
	assert disk_utility_test_tree_has(tree, path)
	free_tree(tree)
	if mut app is DiskUtilityApp {
		assert app.report_status == 'disk_utility.report.saved'
		app.export_report()
		assert app.report_status == 'disk_utility.report.exists'
	}
	data := os.read_file(path)!
	assert data.len > 0
	unsafe { data.free() }
}

fn test_disk_utility_native_path_edits_and_close_reinitialize() {
	mut app := DiskUtilityApp{}
	app.initialize()
	defer { app.close_app() }
	app.key_input('\x0c')
	app.paste_input('/tmp/report-Ж.txt\n\t')
	assert disk_usage_buffer_text(app.report_path) == '/tmp/report-Ж.txt'
	app.key_input('\x15')
	app.paste_input('relative-report.txt')
	app.export_report()
	assert app.report_status == 'disk_utility.report.invalid'
	app.key_input('\x0c')
	long := 'x'.repeat(520)
	app.paste_input(long)
	unsafe { long.free() }
	assert app.report_path.len == disk_utility_path_limit
	app.close_app()
	app.close_app()
	app.initialize()
	assert app.report_path.len > 0
}
