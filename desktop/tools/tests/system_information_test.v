// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn system_information_search_test_seed(mut app SystemInformationApp) {
	app.initialized = true
	app.sections[0].add('system_information.cpu', 'Test CPU'.clone(), false)
	app.sections[0].add('system_information.memory_total', '16384 kB'.clone(), false)
	app.sections[1].add('', 'drivers: virtio_gpu'.clone(), false)
	app.sections[1].add_row(SystemInformationLine{key: 'system_information.network_report', unavailable: true})
	app.sections[2].add('', 'tmpfs /home/alex'.clone(), false)
	app.sections[3].add('', 'café-package 1.0'.clone(), false)
	app.sections[3].add('', 'Пакет 2.0'.clone(), false)
	app.refilter_search(false)
}

fn system_information_search_test_find(tree ui2.Element, id string) ?ui2.Element {
	if tree.id == id { return tree }
	for child in tree.children {
		if found := system_information_search_test_find(child, id) { return found }
	}
	return none
}

fn test_system_information_search_fragmented_navigation_and_pending_input_boundaries() {
	mut polling := false
	for factory in available_apps {
		if factory.process_name == 'vinix-system-information' { polling = factory.polling && factory.poll_interval_ms == 100 }
	}
	assert polling
	mut app := SystemInformationApp{}
	defer { app.close_app() }
	app.initialized = true
	for _ in 0 .. 40 { app.sections[3].add('', 'wanted'.clone(), false) }
	app.key_input('\x06wanted')
	app.key_input('\x1b')
	assert !app.expire_escape(app.escape_ms + 99)
	app.key_input('[B')
	assert app.search_text() == 'wanted' && app.scroll[3] == 1 && app.search_focus
	app.key_input('\x1b[')
	app.key_input('6~')
	assert app.scroll[3] == 1 + app.visible_rows && app.search_text() == 'wanted'
	app.key_input('\x1bO')
	app.key_input('A')
	assert app.scroll[3] == app.visible_rows
	app.key_input('\x1b[123456789012345678901234~')
	assert app.search_text() == 'wanted' && app.escape_len == 0
	app.key_input('\xd0\x01\x96')
	assert app.search_text() == 'wanted' && app.search_selected && app.pending_len == 0
	app.key_input('\xd0')
	oversized := 'x'.repeat(129)
	app.paste_input(oversized)
	unsafe { oversized.free() }
	assert app.pending_len == 0 && app.search_text() == 'wanted'
	app.key_input('\x1b')
	assert app.expire_escape(app.escape_ms + 100)
	assert app.search_len == 0 && !app.search_focus
}

fn test_system_information_search_matches_translated_names_values_and_sections_without_changing_report() {
	previous := desktop_language
	set_desktop_language(.en)
	defer { set_desktop_language(previous) }
	mut app := SystemInformationApp{}
	defer { app.close_app() }
	system_information_search_test_seed(mut app)
	app.key_input('\x06')
	app.paste_input('CPU test')
	assert app.search_text() == 'CPU test'
	assert app.filtered_count(0) == 1
	assert app.search_indices[0][0] == 0
	assert app.filtered_count(1) == 0
	app.key_input('\x06')
	app.paste_input('virtio')
	assert app.tab == 1 && app.filtered_count(1) == 1
	app.key_input('\x06')
	app.paste_input('unavailable network')
	assert app.filtered_count(1) == 1 && app.search_indices[1][0] == 1
	app.key_input('\x06')
	app.paste_input('CAFE')
	assert app.tab == 3 && app.filtered_count(3) == 1
	app.key_input('\x06')
	app.paste_input('пАКЕТ')
	assert app.filtered_count(3) == 1 && app.search_indices[3][0] == 1
	app.key_input('\x06')
	app.paste_input('installed packages')
	assert app.filtered_count(3) == 2 && app.filtered_count(0) == 0
	data := app.report()
	text := disk_usage_buffer_text(data)
	assert text.contains('Test CPU') && text.contains('tmpfs /home/alex') && text.contains('café-package')
	unsafe { data.free() }
	app.handle('system_information.search.clear')!
	assert app.filtered_count(0) == 2 && app.filtered_count(3) == 2
}

fn test_system_information_search_utf8_keyboard_paste_bounds_focus_and_language_changes() {
	previous := desktop_language
	set_desktop_language(.en)
	defer { set_desktop_language(previous) }
	mut app := SystemInformationApp{}
	defer { app.close_app() }
	system_information_search_test_seed(mut app)
	app.key_input('\x06\xd0')
	assert app.search_len == 0
	app.key_input('\x96')
	assert app.search_text() == 'Ж'
	app.key_input('\x7f')
	assert app.search_len == 0
	app.paste_input('CPU\nTest\t\x01')
	assert app.search_text() == 'CPU Test '
	assert app.filtered_count(0) == 1
	app.key_input('\x01')
	oversized := 'x'.repeat(129)
	app.paste_input(oversized)
	unsafe { oversized.free() }
	assert app.search_text() == 'CPU Test ' && app.search_selected
	app.paste_input('memory')
	assert app.search_text() == 'memory' && app.filtered_count(0) == 1
	set_desktop_language(.ru)
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 780, 540))!)
	assert app.filtered_count(0) == 0
	app.key_input('\x06')
	app.paste_input('памяти')
	assert app.filtered_count(0) == 1
	app.key_input('\x0c')
	assert app.path_focus && !app.search_focus
	app.paste_input('/tmp/report.txt')
	assert disk_usage_buffer_text(app.report_path) == '/tmp/report.txt'
	app.key_input('\x06\x1b')
	app.expire_escape(~u64(0))
	assert app.search_len == 0 && !app.search_focus
	app.paste_input('ignored')
	assert app.search_len == 0
	app.key_input('\x06')
	bound := 'a'.repeat(127)
	app.paste_input(bound)
	unsafe { bound.free() }
	app.key_input('\xd0\x96')
	assert app.search_len == 127 && app.pending_len == 0
	app.key_input('\x01\x7f')
	assert app.search_len == 0
}

fn test_system_information_search_paging_empty_ui_snapshot_refresh_and_small_window() {
	previous := desktop_language
	set_desktop_language(.en)
	defer { set_desktop_language(previous) }
	mut app := SystemInformationApp{}
	defer { app.close_app() }
	app.initialized = true
	for index in 0 .. 80 {
		app.sections[3].add('', if index % 2 == 0 { 'wanted'.clone() } else { 'other'.clone() }, false)
	}
	app.key_input('\x06')
	app.paste_input('wanted')
	assert app.tab == 3 && app.filtered_count(3) == 40
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 780, 540))!)
	app.key_input('\x1b[F')
	assert app.scroll[3] == 40 - app.visible_rows
	app.handle('system_information.previous')!
	assert app.scroll[3] == 40 - 2 * app.visible_rows
	app.pointer_event(.scroll, .left, 2, 200, 130, 780, 540)
	assert app.scroll[3] == 40 - 2 * app.visible_rows - 6
	app.sections[3].clear()
	app.sections[3].add('', 'wanted replacement'.clone(), false)
	app.refilter_search(false)
	assert app.filtered_count(3) == 1 && app.scroll[3] == 0
	app.key_input('\x06')
	app.paste_input('no such value')
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 400, 250))!
	assert system_information_test_tree_has_text(tree, tr('system_information.search.empty'))
	assert system_information_test_tree_has_text(tree, 'no such value')
	assert app.visible_rows == 1
	packages := system_information_search_test_find(tree, 'system_information.tab.3') or { panic('missing packages tab') }
	assert packages.frame.y + packages.frame.height <= 173
	previous_button := system_information_search_test_find(tree, 'system_information.previous') or { panic('missing previous button') }
	next := system_information_search_test_find(tree, 'system_information.next') or { panic('missing next button') }
	assert previous_button.frame.x + previous_button.frame.width < next.frame.x
	count := system_information_search_test_find(tree, frame_owned_text_id) or { panic('missing match count') }
	assert count.frame.width >= 90 && count.text == '0 rows'
	label := system_information_search_test_find(tree, 'system_information.search.label') or { panic('missing search label') }
	field := system_information_search_test_find(tree, 'system_information.search') or { panic('missing search field') }
	assert label.text == 'Search' && label.frame.x + label.frame.width < field.frame.x
	assert field.frame.width >= 80 && field.frame.x + field.frame.width < 312
	free_tree(tree)
	app.close_app()
	assert app.search_len == 0 && app.search_counts[3] == 0
}

fn system_information_test_sources(root string) SystemInformationSources {
	return SystemInformationSources{
		version: join_path(root, 'version'), cpu: join_path(root, 'cpuinfo'), memory: join_path(root, 'meminfo'),
		uptime: join_path(root, 'uptime'), cpu_online: join_path(root, 'online'), node_online: join_path(root, 'nodes'),
		device_tree: join_path(root, 'devices'), gpu: join_path(root, 'gpu'), network: join_path(root, 'network'),
		mounts: join_path(root, 'mounts'), packages: join_path(root, 'installed'), custom_directory: root.clone()
	}
}

fn system_information_test_release_sources(s SystemInformationSources) {
	unsafe {
		s.version.free(); s.cpu.free(); s.memory.free(); s.uptime.free(); s.cpu_online.free(); s.node_online.free()
		s.device_tree.free(); s.gpu.free(); s.network.free(); s.mounts.free(); s.packages.free(); s.custom_directory.free()
	}
}

fn system_information_test_write_sources(s SystemInformationSources) ! {
	os.write_file(s.version, 'Linux version test-vinix\n')!
	os.write_file(s.cpu, 'processor: 0\nmodel name: Test CPU\nCPU architecture: 8\nFeatures: fp asimd\n')!
	os.write_file(s.memory, 'MemTotal: 16384 kB\nMemAvailable: 8192 kB\nCached: 1024 kB\n')!
	os.write_file(s.uptime, '123.45 111.00\n')!
	os.write_file(s.cpu_online, '0-3\n')!
	os.write_file(s.node_online, '0\n')!
	os.write_file(s.gpu, 'devices: 1\ndrivers: virtio_gpu\nsubmissions: 2\n')!
	os.write_file(s.network, 'lo: 1 2 3 4\n')!
	os.write_file(s.mounts, 'tmpfs / tmpfs rw 0 0\n/dev/missing /does-not-exist ext2 ro 0 0\n')!
	os.write_file(s.packages, 'P:alpha\nV:1.2-r3\nF:usr/bin\nR:alpha\n\nP:beta\nV:2.0\n\nP:no-version\n')!
	custom := join_path(s.custom_directory, 'minecraft.files')
	os.write_file(custom, '/opt/minecraft/client.jar\n')!
	unsafe { custom.free() }
}

fn system_information_test_has(section SystemInformationSection, key string, text string) bool {
	for row in section.rows { if row.key == key && row.text == text { return true } }
	return false
}

fn system_information_test_tree_has_text(tree ui2.Element, text string) bool {
	if tree.text == text { return true }
	for child in tree.children { if system_information_test_tree_has_text(child, text) { return true } }
	return false
}

fn test_system_information_factory_preserves_destination_through_native_interfaces() {
	previous := desktop_language
	set_desktop_language(.en)
	defer { set_desktop_language(previous) }
	root := os.join_path(os.temp_dir(), 'vinix-system-information-native-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := system_information_join_path(root, 'report-Ж.txt')
	defer { unsafe { path.free() } }
	mut desktop := Desktop{}
	mut app := open_system_information(mut desktop)!
	defer {
		if mut app is ClosingApp { app.close_app() }
	}
	if mut app is SystemInformationApp {
		assert disk_usage_buffer_text(app.report_path).ends_with('/system-information.txt')
		app.initialize()
		assert disk_usage_buffer_text(app.report_path).ends_with('/system-information.txt')
	}
	app.handle('system_information.path')!
	mut pasted := false
	if mut app is PastingApp {
		mut paster := PastingApp(app)
		paster.paste_input(path)
		pasted = true
	}
	assert pasted
	app.handle('system_information.export')!
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 780, 516))!
	assert system_information_test_tree_has_text(tree, path)
	assert system_information_test_tree_has_text(tree, 'Report saved')
	free_tree(tree)
	contents := os.read_file(path)!
	assert contents.contains('System Information') && contents.contains('Installed packages')
	unsafe { contents.free() }
}

fn test_system_information_refresh_collects_actual_sources_and_replaces_snapshot() {
	root := os.join_path(os.temp_dir(), 'vinix-system-information-fixture-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	sources := system_information_test_sources(root)
	defer { system_information_test_release_sources(sources) }
	system_information_test_write_sources(sources)!
	manifest_directory := system_information_join_path(root, 'voffice.files')
	os.mkdir(manifest_directory)!
	unsafe { manifest_directory.free() }
	mut app := SystemInformationApp{}
	defer { app.close_app() }
	app.refresh_sources(sources)
	assert system_information_test_has(app.sections[0], 'system_information.kernel', 'Linux version test-vinix')
	assert system_information_test_has(app.sections[0], 'system_information.cpu', 'Test CPU')
	assert system_information_test_has(app.sections[0], 'system_information.memory_total', '16384 kB')
	assert system_information_test_has(app.sections[0], 'system_information.uptime', '123.45')
	assert system_information_test_has(app.sections[1], '', 'drivers: virtio_gpu')
	assert system_information_test_has(app.sections[3], '', 'alpha 1.2-r3')
	assert system_information_test_has(app.sections[3], '', 'beta 2.0')
	assert system_information_test_has(app.sections[3], 'system_information.package_version_unavailable', 'no-version')
	assert system_information_test_has(app.sections[3], 'system_information.custom_package', 'minecraft')
	assert !system_information_test_has(app.sections[3], 'system_information.custom_package', 'voffice')
	assert system_information_test_has(app.sections[2], 'system_information.capacity_unavailable', '')
	os.write_file(sources.packages, 'P:updated\nV:3\n')!
	os.rm(sources.gpu)!
	app.scroll[3] = 500
	app.refresh_sources(sources)
	assert !system_information_test_has(app.sections[3], '', 'alpha 1.2-r3')
	assert system_information_test_has(app.sections[3], '', 'updated 3')
	assert system_information_test_has(app.sections[1], 'system_information.unavailable', '')
	assert app.scroll[3] == 0
}

fn test_system_information_exports_all_sections_and_refuses_existing_files_and_links() {
	root := os.join_path(os.temp_dir(), 'vinix-system-information-export-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	sources := system_information_test_sources(root)
	defer { system_information_test_release_sources(sources) }
	system_information_test_write_sources(sources)!
	mut app := SystemInformationApp{}
	defer { app.close_app() }
	app.refresh_sources(sources)
	report := join_path(root, 'report.txt')
	defer { unsafe { report.free() } }
	app.key_input('\x0c')
	longer := '${report}.old'
	app.paste_input(longer)
	unsafe { longer.free() }
	app.key_input('\x7f\x7f\x7f\x7f\r')
	assert disk_usage_buffer_text(app.report_path) == report
	assert app.report_status == 'system_information.report.saved'
	contents := os.read_file(report)!
	defer { unsafe { contents.free() } }
	assert contents.contains('Test CPU') && contents.contains('drivers: virtio_gpu')
	assert contents.contains('alpha 1.2-r3') && contents.contains('/does-not-exist')
	app.export_report()
	assert app.report_status == 'system_information.report.exists'
	unchanged := os.read_file(report)!
	assert unchanged == contents
	unsafe { unchanged.free() }
	link := join_path(root, 'link.txt')
	defer { unsafe { link.free() } }
	os.symlink(report, link)!
	app.key_input('\x0c')
	app.paste_input(link)
	app.export_report()
	assert app.report_status == 'system_information.report.exists'
	app.key_input('\x0c')
	app.paste_input('relative.txt')
	app.export_report()
	assert app.report_status == 'system_information.report.invalid'
}

fn test_system_information_bounds_package_snapshots_and_supports_scroll_and_safe_path_input() {
	root := os.join_path(os.temp_dir(), 'vinix-system-information-bounds-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	sources := system_information_test_sources(root)
	defer { system_information_test_release_sources(sources) }
	system_information_test_write_sources(sources)!
	mut database := []u8{cap: 80000}
	unsafe { database.flags |= .noslices }
	// Long ownership lines are ignored, and the first package's metadata
	// crosses the collector's 32768-byte read boundary.
	disk_usage_append(mut database, 'F:')
	for _ in 0 .. 32760 { database << `x` }
	database << `\n`
	for index in 0 .. 700 {
		name := index.str()
		disk_usage_append(mut database, 'P:package-')
		disk_usage_append(mut database, name)
		disk_usage_append(mut database, '\nV:1\nF:usr/bin\nR:file\n\n')
		unsafe { name.free() }
	}
	os.write_file(sources.packages, unsafe { tos(database.data, database.len) })!
	unsafe { database.free() }
	mut app := SystemInformationApp{}
	defer { app.close_app() }
	app.refresh_sources(sources)
	assert app.sections[3].limited
	assert app.sections[3].rows.len == system_information_row_limit
	assert system_information_test_has(app.sections[3], '', 'package-0 1')
	app.handle('system_information.tab.3')!
	app.key_input('\x1b[6~')
	assert app.scroll[3] == app.visible_rows
	app.pointer_event(.scroll, .no_button, -2, 200, 130, 780, 540)
	assert app.scroll[3] == app.visible_rows + 6
	app.key_input('\x1b[F')
	assert app.scroll[3] == app.sections[3].rows.len - app.visible_rows
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 780, 540))!)
	app.key_input('\x0c')
	app.paste_input('/tmp/Ж\n\r\x1b\t')
	assert disk_usage_buffer_text(app.report_path) == '/tmp/Ж'
	assert app.report_status == ''
	app.key_input('\x7f')
	assert disk_usage_buffer_text(app.report_path) == '/tmp/'
	app.key_input('\xe2')
	app.key_input('\x82\xac')
	assert disk_usage_buffer_text(app.report_path) == '/tmp/€'
	app.key_input('\x15')
	for _ in 0 .. system_information_path_limit - 1 { app.key_input('a') }
	app.paste_input('Ж')
	assert app.report_path.len == system_information_path_limit - 1
	app.key_input('\x1b')
	app.paste_input('ignored')
	assert app.report_path.len == system_information_path_limit - 1
}

fn test_system_information_capacity_rejects_unknown_overflow_and_invalid_counters() {
	capacity := system_information_capacity(4096, 100, 40, 30) or { panic('valid capacity rejected') }
	assert capacity == [u64(409600), 245760, 122880]!
	assert system_information_capacity(4096, 0, 0, 0) == none
	assert system_information_capacity(4096, u64(-1), 0, 0) == none
	assert system_information_capacity(4096, 100, 101, 30) == none
	assert system_information_capacity(4096, 100, 40, 101) == none
	decoded := system_information_unescape_mount('/media/a\\040b\\134c')
	assert decoded == '/media/a b\\c'
	unsafe { decoded.free() }
}

fn test_system_information_unavailable_values_follow_language_without_refresh() {
	previous := desktop_language
	defer { set_desktop_language(previous) }
	mut app := SystemInformationApp{initialized: true}
	defer { app.close_app() }
	app.value(0, 'system_information.cpu', '')
	assert app.sections[0].rows[0].unavailable
	set_desktop_language(.en)
	english, english_owned := system_information_row_text(app.sections[0].rows[0])
	assert english_owned && english.contains('Unavailable')
	unsafe { english.free() }
	set_desktop_language(.ru)
	russian, russian_owned := system_information_row_text(app.sections[0].rows[0])
	assert russian_owned && russian.contains('Недоступно')
	unsafe { russian.free() }
	report := app.report()
	assert unsafe { tos(report.data, report.len) }.contains('Недоступно')
	unsafe { report.free() }
}
