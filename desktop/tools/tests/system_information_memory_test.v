// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import os

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_system_information_factory_interface_edits_and_exports_release_owned_memory() {
	root := os.join_path(os.temp_dir(), 'vinix-system-information-native-heap-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := system_information_join_path(root, 'report-Ж.txt')
	defer { unsafe { path.free() } }
	mut desktop := Desktop{}
	// The factory model lives for the native process. Keep that fixture and
	// the frame pool outside tracking; measure its repeatedly owned buffers.
	mut app := open_system_information(mut desktop)!
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 780, 516))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		if mut app is SystemInformationApp {
			app.initialize()
			app.initialize()
			app.close_app()
			app.initialize()
			app.refresh()
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
		free_tree(app.build(ui2.rect(0, 0, 780, 516))!)
		assert C.unlink(&char(path.str)) == 0
		if mut app is SystemInformationApp {
			app.close_app()
		}
	}
	assert C.vinix_heap_end() == 0
}

fn test_system_information_refresh_report_frames_and_close_release_owned_memory() {
	// Reading real host procfs may be unavailable; both the populated and
	// unavailable paths are exercised by explicit bounded model data below.
	mut app := SystemInformationApp{}
	app.initialize()
	app.refresh()
	for tab in 0 .. 4 {
		app.tab = tab
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 780, 540))!)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.refresh()
		app.sections[3].clear()
		mut parser := SystemInformationPackageParser{}
		parser.line(mut app.sections[3], 'P:heap-package')
		parser.line(mut app.sections[3], 'V:1.2-r3')
		parser.finish(mut app.sections[3])
		for tab in 0 .. 4 {
			app.tab = tab
			begin_frame_elements()
			free_tree(app.build(ui2.rect(0, 0, 780, 540))!)
		}
		app.key_input('\x0c')
		app.paste_input('/tmp/system-information-Ж.txt')
		app.key_input('\x7f')
		report := app.report()
		unsafe { report.free() }
	}
	app.close_app()
	app.close_app()
	live := C.vinix_heap_end()
	assert live == 0, 'System Information retained ${live} bytes after closing'
}

fn test_system_information_populated_file_refresh_and_export_do_not_retain_heap() {
	root := os.join_path(os.temp_dir(), 'vinix-system-information-heap-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	values := join_path(root, 'values')
	mounts := join_path(root, 'mounts')
	packages := join_path(root, 'installed')
	report_path := join_path(root, 'report.txt')
	defer { unsafe { values.free(); mounts.free(); packages.free(); report_path.free() } }
	os.write_file(values, 'model name: Heap CPU\nCPU architecture: 8\nMemTotal: 16384 kB\nMemAvailable: 8192 kB\nCached: 1024 kB\n')!
	mount_data := 'tmpfs ${root} tmpfs rw 0 0\n'
	os.write_file(mounts, mount_data)!
	unsafe { mount_data.free() }
	os.write_file(packages, 'P:heap-alpha\nV:1.0-r1\nF:usr/bin\nR:alpha\n\nP:heap-beta\nV:2\n')!
	sources := SystemInformationSources{version: values, cpu: values, memory: values, uptime: values,
		cpu_online: values, node_online: values, gpu: values, network: values, mounts: mounts,
		packages: packages, custom_directory: root}
	mut app := SystemInformationApp{}
	app.refresh_sources(sources)
	for tab in 0 .. 4 {
		app.tab = tab
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 780, 540))!)
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.refresh_sources(sources)
		for tab in 0 .. 4 {
			app.tab = tab
			begin_frame_elements()
			free_tree(app.build(ui2.rect(0, 0, 780, 540))!)
		}
		app.key_input('\x0c')
		app.paste_input(report_path)
		app.export_report()
		assert app.report_status == 'system_information.report.saved'
		assert C.unlink(&char(report_path.str)) == 0
	}
	app.close_app()
	live := C.vinix_heap_end()
	assert live == 0, 'System Information fixture refresh/export retained ${live} bytes'
}
