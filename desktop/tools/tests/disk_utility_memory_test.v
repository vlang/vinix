// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_disk_utility_refresh_build_report_and_close_release_owned_memory() {
	root := os.join_path(os.temp_dir(), 'vinix-disk-utility-heap-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	mounts := disk_utility_join_path(root, 'mounts')
	path := disk_utility_join_path(root, 'report-Ж.txt')
	defer { unsafe { mounts.free(); path.free() } }
	data := '/dev/test ${root} ext2 rw 0 0\n/dev/other /missing-vinix-volume tmpfs ro 0 0\n'
	os.write_file(mounts, data)!
	unsafe { data.free() }
	sources := DiskUtilitySources{devices: root, mounts: mounts}
	mut app := DiskUtilityApp{}
	app.initialize()
	app.refresh_sources(sources)
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 780, 560))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.refresh_sources(sources)
		app.device_metadata('/dev/nvme0n1p0', u32(C.S_IFBLK), 536870912)
		for tab in 0 .. 2 {
			app.tab = tab
			begin_frame_elements()
			free_tree(app.build(ui2.rect(0, 0, 780, 560))!)
		}
		app.key_input('\x0c')
		app.paste_input(path)
		app.export_report()
		assert app.report_status == 'disk_utility.report.saved'
		assert C.unlink(&char(path.str)) == 0
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_disk_utility_factory_native_reinitialize_paste_export_releases_owned_memory() {
	root := os.join_path(os.temp_dir(), 'vinix-disk-utility-native-heap-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := disk_utility_join_path(root, 'report-Ж.txt')
	defer { unsafe { path.free() } }
	mut desktop := Desktop{}
	mut app := open_disk_utility(mut desktop)!
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 780, 560))!)
	// Factory object and frame pool live for the native process. Measure its
	// repeated owned buffers and native interface input, not that fixture.
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		if mut app is DiskUtilityApp { app.initialize(); app.initialize(); app.close_app(); app.initialize(); app.refresh() }
		app.handle('disk_utility.path')!
		mut pasted := false
		if mut app is PastingApp { mut paster := PastingApp(app); paster.paste_input(path); pasted = true }
		assert pasted
		app.handle('disk_utility.export')!
		assert C.unlink(&char(path.str)) == 0
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 780, 560))!)
		if mut app is DiskUtilityApp { app.close_app() }
	}
	assert C.vinix_heap_end() == 0
}
