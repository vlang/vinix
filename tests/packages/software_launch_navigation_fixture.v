// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

const launch_navigation_arguments = '--title "λ; $(literal)" "" --flag'

fn launch_navigation_files() []string {
	return ['/private/tmp/a space; $literal.txt', '/private/tmp/文档.txt', '/private/tmp/third',
		'/private/tmp/fourth', '/private/tmp/fifth', '/private/tmp/sixth', '/private/tmp/seventh']
}

fn launch_navigation_app() SoftwareApp {
	return SoftwareApp{ administration_required: true, service_path: os.executable(), output: []u8{cap: 8192},
		query: 'kept query'.bytes(), matching: [1, 0], filter: 2, selected: 0, rows: [
		SoftwareRow{ id: 'launch-app', name: 'Candidate', kind: 'linux', permissions: [],
			installed_name: 'Installed App é', installed_kind: 'linux', installed_version: '1.0.0', installed_permissions: ['files'] },
		SoftwareRow{ id: 'no-files', name: 'Candidate files', kind: 'linux', permissions: ['files'],
			installed_name: 'Installed without files', installed_kind: 'linux', installed_version: '1.0.0' }] }
}

fn fill_launch_navigation_draft(mut app SoftwareApp, files []string) ! {
	app.handle('software.run-options')!
	app.handle('software.launch.arguments')!; app.paste_input(launch_navigation_arguments)
	app.handle('software.launch.data-cwd')!
	for path in files {
		app.handle('software.launch.file')!; app.paste_input(path); app.handle('software.launch.add-file')!
	}
	app.handle('software.launch.arguments')!
}

fn software_launch_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION')
	if mode == '' || args.len < 2 || args[1] != 'run-args' { return false }
	mut words := pkgprotocol.command_words(launch_navigation_arguments)!
	files := launch_navigation_files()
	mut expected := pkgprotocol.command_vector('launch-app', words, files, false, false)!
	defer { pkgprotocol.free_command_values(mut words); pkgprotocol.free_command_values(mut expected); unsafe { (&array(&files)).free() } }
	if args[1..] != expected { return error('launch service received a different literal command') }
	println('Application is running with the frozen literal command.'); flush_stdout()
	mut release := u8(0)
	if C.read(0, &release, 1) != 1 { return error('launch service release barrier failed') }
	os.write_file(os.getenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION_RECEIPT'), json2.encode(args[1..]))!
	if mode == 'failed' { eprintln('Granted file is unavailable to the ordinary account. Correct file access and retry.'); exit(27) }
	println('Application finished successfully.')
	return true
}

fn wait_for_launch_navigation_output(mut app SoftwareApp) {
	for _ in 0 .. 5000 {
		app.poll()
		if app.output.len > 0 { return }
		time.sleep(time.millisecond)
	}
	assert false, 'launch fixture did not reach its output barrier: ${app.status}'
}

fn check_launch_empty_paste(mut app SoftwareApp) {
	arguments := editor_bytes_text(app.launch_arguments); file := editor_bytes_text(app.launch_file)
	argument_storage := app.launch_arguments.data; file_storage := app.launch_file.data
	status := app.status; selected := app.launch_file_selected; scroll := app.launch_file_scroll
	count := app.launch_documents.len; cwd := app.launch_data_cwd; id := app.launch_id
	focused := app.launch_focus; selection := app.select_all
	for focus in 0 .. 3 {
		for select_all in [false, true]! {
			app.launch_focus = focus; app.select_all = select_all
			app.paste_input('')
			assert editor_bytes_text(app.launch_arguments) == arguments && editor_bytes_text(app.launch_file) == file
			assert app.launch_arguments.data == argument_storage && app.launch_file.data == file_storage
			assert app.launch_focus == focus && app.select_all == select_all && app.status == status
			assert app.launch_mode && app.launch_id == id && app.launch_data_cwd == cwd && app.launch_documents.len == count
			assert app.launch_file_selected == selected && app.launch_file_scroll == scroll && app.worker == unsafe { nil }
		}
	}
	app.launch_focus = focused; app.select_all = selection
}

fn launch_reader_text(a &SoftwareApp) string {
	mut bytes := []u8{cap: 16384}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	for page in a.details_pages {
		mut lines := page.text.split_into_lines()
		for line in lines {
			// Each canonical line has a bullet or continuation prefix.
			start := if line.starts_with('• ') { 4 } else { 2 }
			for index in start .. line.len { bytes << line[index] }
		}
		software_policy_free_lines(mut lines)
	}
	return bytes.bytestr()
}

fn launch_reader_cycle(mut app SoftwareApp) ! {
	focus := app.launch_focus; selection := app.select_all
	selected := app.launch_file_selected; scroll := app.launch_file_scroll
	arguments := editor_bytes_text(app.launch_arguments); file := editor_bytes_text(app.launch_file)
	argument_storage := app.launch_arguments.data; file_storage := app.launch_file.data; files := app.launch_documents.data
	id := app.launch_id; name := app.launch_name; cwd := app.launch_data_cwd; allowed := app.launch_files_allowed; status := app.status
	app.handle('software.report.read')!; assert app.report_reader_mode && app.details_pages.len > 0
	for size in [ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 160, 96)]! {
		free_window_tree(app.build(size)!)
	}
	app.key_input('\x1b[C'); app.key_input('\t'); app.key_input('\x1b[Z')
	request := packagecore.request_prefix + '{"id":"no-files"}'
	defer { unsafe { request.free() } }
	for action in ['software.launch.arguments', 'software.launch.file', 'software.launch.data-cwd', 'software.launch.add-file',
		'software.launch.remove-file', 'software.launch.up', 'software.launch.down', 'software.launch.file.0',
		'software.launch.run', 'software.launch.terminal', 'software.launch.back', 'software.reload', 'software.cancel', 'software.confirm',
		'software.run-options', 'software.report.read', request]! {
		app.handle(action)!
	}
	app.key_input('typed'); app.key_input('\x01'); app.key_input('\x08'); app.key_input('\r')
	app.paste_input('changed'); app.paste_input('\x1b'); app.paste_input('')
	assert app.report_reader_mode && app.worker == unsafe { nil } && app.terminal_app == unsafe { nil } && !app.admin_prompt
	assert app.launch_focus == focus && app.select_all == selection && app.launch_file_selected == selected && app.launch_file_scroll == scroll
	assert editor_bytes_text(app.launch_arguments) == arguments && editor_bytes_text(app.launch_file) == file
	assert app.launch_arguments.data == argument_storage && app.launch_file.data == file_storage && app.launch_documents.data == files
	assert app.launch_id == id && app.launch_name == name && app.launch_data_cwd == cwd && app.launch_files_allowed == allowed && app.status == status
	app.key_input('\x1b')
	assert !app.report_reader_mode && app.launch_mode && app.details_pages.len == 0 && app.details_compact_pages.len == 0
	assert app.launch_focus == focus && app.select_all == selection && app.launch_file_selected == selected && app.launch_file_scroll == scroll
}

fn check_software_launch_reader() ! {
	mut app := launch_navigation_app()
	defer { app.close_app() }
	mut files := []string{cap: 256}
	unsafe { files.flags |= .noslices }
	for index in 0 .. 256 {
		number := index.str()
		files << '/private/tmp/document-' + number
		unsafe { number.free() }
	}
	padding := '文'.repeat(1359)
	long_file := '/private/tmp/' + padding + 'é.txt'
	arguments := 'λ'.repeat(2048)
	defer { pkgprotocol.free_command_values(mut files); unsafe { padding.free(); long_file.free(); arguments.free() } }
	unsafe { files[255].free() }; files[255] = long_file.clone()
	assert long_file.len == 4096 && arguments.len == 4096
	fill_launch_navigation_draft(mut app, files)!
	app.handle('software.launch.arguments')!; app.key_input('\x01'); app.paste_input(arguments)
	app.handle('software.launch.file')!; app.paste_input(long_file); app.key_input('\x01')
	launch_reader_cycle(mut app)!
	app.handle('software.report.read')!
	text := launch_reader_text(&app)
	assert text.contains('Installed application ID: launch-app') && text.contains('Installed application name: Installed App é')
	assert text.contains('Argument text: ' + arguments) && text.contains('Allowed file path: ' + long_file)
	assert text.contains('Entered file path (not yet granted): ' + long_file)
	assert text.contains('Allowed files: 256') && text.contains('Installed application directory (read-only)')
	assert text.contains('readable and writable') && text.contains('does not validate or run')
	unsafe { text.free() }
	for canonical, full in app.details_pages {
		mut bytes := []u8{cap: full.text.len}
		for short in app.details_compact_pages {
			if short.source_page == canonical { for byte in short.text { if byte != `\n` { bytes << byte } } }
		}
		expected := full.text.replace('\n', '')
		assert editor_bytes_text(bytes) == expected
		unsafe { bytes.free(); expected.free() }
	}
	for index, short in app.details_compact_pages {
		app.details_compact_page = index; app.details_page = short.source_page
		for size in [ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			details_fixture_rendered_lines(&tree, short.text, 14, 118, int(size.width) - 28, 18, 12)
			assert tree.children.any(it.id == 'software.report.back') && tree.children.any(it.text == short.label)
			assert !tree.children.any(it.id in ['software.launch.run', 'software.launch.terminal', 'software.launch.add-file', 'software.launch.remove-file'])
			for element in tree.children {
				assert element.frame.x >= 0 && element.frame.x + element.frame.width <= size.width
				assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
			}
			free_window_tree(tree)
		}
	}
	anchor := app.details_compact_page; canonical := app.details_page
	for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 160, 96), ui2.rect(0, 0, 180, 220)]! {
		free_window_tree(app.build(size)!); assert app.details_compact_page == anchor && app.details_page == canonical
	}
	app.key_input('\x1b[C'); assert app.details_compact_page == anchor
	app.key_input('\x1b[D'); assert app.details_compact_page == anchor - 1
	// Traverse all grants independently of the form's selection and file page.
	for app.launch_read_file > 0 { app.key_input('\x1b[A') }
	app.key_input('\x1b[Z'); assert app.launch_read_file == 0
	for index, path in files {
		assert app.launch_read_file == index
		current := launch_reader_text(&app); assert current.contains('Allowed file path: ' + path); unsafe { current.free() }
		app.key_input('\t'); assert app.launch_read_file == if index < 255 { index + 1 } else { 255 }
	}
	assert app.launch_file_selected == 255 && app.launch_file_scroll == 251
	app.handle('software.report.back')!
	assert app.launch_focus == 2 && app.select_all && app.details_pages.len == 0
	app.key_input('\x08'); app.handle('software.launch.data-cwd')!
	app.handle('software.report.read')!
	private := launch_reader_text(&app)
	assert private.contains('~/.local/share/vinix-apps/launch-app') && private.contains('Entered file path (not yet granted): (empty)')
	unsafe { private.free() }; app.key_input('\x1b')
	app.handle('software.launch.back')!; app.selected = 1; app.handle('software.run-options')!
	app.handle('software.report.read')!
	empty := launch_reader_text(&app)
	assert empty.contains('Argument text: (empty)') && empty.contains('No document files have been granted') && empty.contains('does not declare document-file access')
	unsafe { empty.free() }
	app.key_input('\t'); app.key_input('\x1b[A'); assert app.launch_read_file == -1
	app.key_input('\x1b'); launch_reader_cycle(mut app)!
	println('Software launch reader: complete 4096-byte Unicode arguments, pending and allowed paths; all 256 grants; installed permissions, both working folders, empty drafts, native lines, compact/full/tiny anchors and frozen form state passed')
}

fn check_software_launch_navigation() ! {
	check_software_launch_reader()!
	receipt := os.temp_dir() + '/vinix-launch-navigation-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION_RECEIPT', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION'); os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION_RECEIPT') }
	files := launch_navigation_files()
	defer { unsafe { (&array(&files)).free() } }
	mut words := pkgprotocol.command_words(launch_navigation_arguments)!
	mut vector := pkgprotocol.command_vector('launch-app', words, files, false, false)!
	defer { pkgprotocol.free_command_values(mut words); pkgprotocol.free_command_values(mut vector) }
	mut app := launch_navigation_app()
	defer { app.close_app() }
	fill_launch_navigation_draft(mut app, files)!
	check_launch_empty_paste(mut app)
	assert app.launch_files_allowed && app.launch_name == 'Installed App é' && app.launch_documents == files && !app.launch_data_cwd
	app.handle('software.launch.up')!; app.handle('software.launch.file.1')!; app.handle('software.launch.down')!
	assert app.launch_file_scroll == 5 && app.launch_file_selected == 1
	app.key_input('\x01')
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
		tree := app.build(size)!
		assert tree.children.any(it.id == 'software.launch.back')
		assert tree.children.any(it.id == 'software.launch.run') == (size.width >= 640)
		if size.width < 640 {
			assert tree.children.any(it.id == 'software.launch.arguments') && tree.children.any(it.id == 'software.status')
		}
		free_window_tree(tree)
		assert app.launch_file_scroll == 5 && app.launch_file_selected == 1 && app.launch_focus == 1 && app.select_all
	}
	for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f', '\xc2\x85', '\xff']! {
		app.paste_input(input)
		assert app.launch_mode && app.launch_focus == 1 && app.select_all && editor_bytes_text(app.launch_arguments) == launch_navigation_arguments
	}
	app.paste_input('x'.repeat(4097))
	assert editor_bytes_text(app.launch_arguments) == launch_navigation_arguments && app.select_all
	app.handle('software.launch.remove-file')!
	assert app.launch_documents.len == 6 && !app.launch_documents.contains(files[1]) && app.launch_file_selected == -1
	app.key_input('\x1b'); assert app.launch_mode && app.launch_focus == 0 && !app.select_all
	app.paste_input('\x1b'); assert app.launch_mode
	app.key_input('\x1b')
	assert !app.launch_mode && app.launch_documents.len == 0 && app.launch_arguments.len == 0 && app.launch_id == ''
	assert app.query.bytestr() == 'kept query' && app.matching == [1, 0] && app.selected == 0 && app.filter == 2
	fill_launch_navigation_draft(mut app, files)!
	app.handle('software.launch.file')!; app.paste_input('/private/tmp/not-yet-added')
	check_launch_empty_paste(mut app)
	app.handle('software.launch.run')!; assert app.worker == unsafe { nil } && app.status.contains('Add the entered file')
	app.key_input('\x01'); app.key_input('\x08')
	assert app.launch_file.len == 0
	app.handle('software.launch.arguments')!; app.key_input('\x01'); app.paste_input('"unfinished')
	app.handle('software.launch.run')!; assert app.worker == unsafe { nil } && app.status.contains('quoted argument')
	app.key_input('\x01'); app.paste_input(launch_navigation_arguments); app.key_input('\r')
	assert app.launch_focus == 0 && !app.select_all
	for mode in ['failed', 'complete']! {
		os.setenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION', mode, true)
		app.handle('software.launch.run')!; pid := app.worker.pid
		wait_for_launch_navigation_output(mut app)
		assert app.worker_run && app.worker.args == vector && !app.admin_prompt && !app.prepare_close()
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			assert tree.children.any(it.text == app.status)
			assert !tree.children.any(it.id in ['software.launch.back', 'software.launch.run', 'software.launch.terminal', 'software.failure', 'software.report.read'])
			free_window_tree(tree)
		}
		for event in ['software.launch.back', 'software.launch.arguments', 'software.launch.file', 'software.launch.data-cwd',
			'software.launch.add-file', 'software.launch.remove-file', 'software.launch.up', 'software.launch.down', 'software.launch.file.0',
			'software.launch.run', 'software.launch.terminal', 'software.reload', 'software.cancel', 'software.report.read']! { app.handle(event)! }
		app.key_input('\x1b'); app.key_input('\x01'); app.paste_input('must not edit')
		app.handle(packagecore.request_prefix + '{"id":"no-files"}')!
		assert app.worker.pid == pid && C.kill(pid, 0) == 0 && app.launch_mode && app.launch_request == '' && !os.exists(receipt)
		assert app.launch_documents == files && !app.launch_data_cwd && editor_bytes_text(app.launch_arguments) == launch_navigation_arguments
		assert !app.report_reader_mode && app.details_pages.len == 0
		app.worker.stdin_write('x'); wait_for_software(mut app)
		assert app.launch_mode && app.prepare_close() && app.launch_documents == files && app.worker == unsafe { nil }
		assert json2.decode[[]string](os.read_file(receipt)!)! == vector
		if mode == 'failed' {
			assert app.failure_pages.len > 0 && app.status.contains('Correct file access')
			app.launch_page = 5
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.launch.back')
			free_window_tree(compact)
			app.handle('software.failure')!; app.key_input('\x1b'); assert !app.failure_mode && app.launch_mode
			launch_reader_cycle(mut app)!
		} else { assert app.status.contains('finished successfully') }
		os.rm(receipt)!
	}
	os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION')
	app.handle('software.launch.terminal')!
	mut terminal_vector := pkgprotocol.command_vector('launch-app', words, files, false, true)!
	defer { pkgprotocol.free_command_values(mut terminal_vector) }
	assert !app.launch_mode && app.terminal_app != unsafe { nil } && app.terminal_app.argv == [app.service_path, ...terminal_vector]
	assert app.launch_documents.len == 0 && app.launch_arguments.len == 0 && !app.prepare_close()
	app.terminal_app.exited = true; app.close_terminal()
	app.selected = 1; app.handle('software.run-options')!
	assert !app.launch_files_allowed && app.launch_name == 'Installed without files' && app.launch_documents.len == 0
	app.handle('software.launch.file')!; app.paste_input(files[0]); app.handle('software.launch.add-file')!
	assert app.launch_documents.len == 0 && app.status.contains('does not declare file access')
	app.key_input('\x1b'); assert app.launch_mode && app.launch_focus == 0
	app.handle('software.launch.back')!; assert !app.launch_mode && app.launch_file.len == 0 && app.launch_documents.len == 0
	assert app.query.bytestr() == 'kept query' && app.matching == [1, 0] && app.filter == 2
	println('Software launch navigation: compact Back/status/failures, stable draft and file paging, Escape blur/back, control-paste refusal, installed permission basis, protected literal batch success/failure, retry and exact terminal transfer passed')
}

// These checks intentionally use explicit conditions: -prod removes assertions.
fn compact_launch_require(ok bool, message string) {
	if !ok { panic('compact Launch options: ' + message) }
}

fn compact_launch_page(mut app SoftwareApp, page int) ! {
	for app.launch_page > page { app.handle('software.launch.page.previous')! }
	for app.launch_page < page { app.handle('software.launch.page.next')! }
}

fn compact_launch_tree(mut app SoftwareApp, width int, height int, required string) ! {
	tree := app.build(ui2.rect(0, 0, width, height))!
	defer { free_window_tree(tree) }
	compact_launch_require(tree.children.any(it.id == required), 'missing visible control ' + required)
	for index, element in tree.children {
		compact_launch_require(element.frame.x >= 0 && element.frame.y >= 0
			&& element.frame.width > 0 && element.frame.height > 0
			&& element.frame.x + element.frame.width <= width
			&& element.frame.y + element.frame.height <= height, 'control outside window')
		for other in tree.children[index + 1..] {
			compact_launch_require(element.frame.x + element.frame.width <= other.frame.x
				|| other.frame.x + other.frame.width <= element.frame.x
				|| element.frame.y + element.frame.height <= other.frame.y
				|| other.frame.y + other.frame.height <= element.frame.y, 'overlapping controls')
		}
	}
}

fn check_software_launch_compact() ! {
	check_software_compact_launch_entry()!
	mut app := launch_navigation_app()
	defer { app.close_app() }
	app.handle('software.run-options')!
	app.handle('software.launch.arguments')!; app.paste_input(launch_navigation_arguments); app.key_input('\x01')
	for focus in [1, 2]! {
		if focus == 2 { app.handle('software.launch.file')!; app.paste_input('/private/tmp/pending'); app.key_input('\x01') }
		page := app.launch_page
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 180, 220)]! {
			free_window_tree(app.build(size)!)
			compact_launch_require(app.launch_focus == focus && app.select_all && app.launch_page == page
				&& editor_bytes_text(app.launch_arguments) == launch_navigation_arguments
				&& (focus == 1 || editor_bytes_text(app.launch_file) == '/private/tmp/pending'), 'resize changed draft or field selection')
		}
	}
	app.key_input('\x08')
	app.handle('software.launch.page.previous')!
	compact_launch_require(app.launch_page == 0 && app.launch_focus == 0 && !app.select_all, 'page navigation did not blur editing')
	app.paste_input('ignored'); app.key_input('\x1b[C')
	compact_launch_require(app.launch_page == 1 && editor_bytes_text(app.launch_arguments) == launch_navigation_arguments, 'compact keyboard navigation edited draft')
	app.handle('software.launch.file')!; app.paste_input('relative'); app.handle('software.launch.add-file')!
	compact_launch_require(app.launch_documents.len == 0 && app.status != '', 'relative grant accepted')
	app.key_input('\x01'); app.key_input('\x08')
	for index in 0 .. 256 {
		path := '/private/tmp/document-' + index.str()
		app.paste_input(path); app.handle('software.launch.add-file')!
		unsafe { path.free() }
	}
	compact_launch_require(app.launch_documents.len == 256 && app.launch_file_scroll == 251 && app.launch_file_selected == 255, 'grant limit or five-row starting scroll changed')
	app.paste_input('/private/tmp/overflow'); app.handle('software.launch.add-file')!
	compact_launch_require(app.launch_documents.len == 256 && app.status.contains('At most 256'), 'grant limit not enforced')
	app.key_input('\x01'); app.key_input('\x08')
	compact_launch_page(mut app, 2)!
	for app.launch_file_scroll > 0 { app.handle('software.launch.file.previous')! }
	for index in 0 .. 256 {
		tree := app.build(ui2.rect(0, 0, 320, 240))!
		compact_launch_require(app.launch_file_scroll == index && tree.children.any(it.id == 'software.launch.file.0' && it.text == app.launch_documents[index]), 'compact grant traversal skipped a file')
		free_window_tree(tree)
		app.handle('software.launch.file.next')!
	}
	compact_launch_require(app.launch_file_scroll == 255, 'file navigation exceeded last grant')
	for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
		free_window_tree(app.build(size)!)
		compact_launch_require(app.launch_file_scroll == 255 && app.launch_file_selected == 255 && app.launch_page == 2, 'resize changed grant selection or shared scroll')
	}
	app.handle('software.launch.file.0')!; app.handle('software.launch.remove-file')!
	compact_launch_require(app.launch_documents.len == 255 && app.launch_file_selected == -1, 'visible grant removal did not dispatch')
	app.handle('software.launch.up')!
	compact_launch_require(app.launch_file_scroll == 245, 'full grant paging stride changed')
	app.handle('software.launch.down')!
	compact_launch_require(app.launch_file_scroll == 250, 'full grant paging return changed')
	for page, control in ['software.launch.arguments', 'software.launch.add-file', 'software.launch.file.0', 'software.launch.data-cwd', 'software.launch.run'] {
		compact_launch_page(mut app, page)!
		for size in [ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 639, 609)]! {
			compact_launch_tree(mut app, int(size.width), int(size.height), control)!
		}
	}
	compact_launch_page(mut app, 3)!
	app.handle('software.launch.data-cwd')!
	compact_launch_require(!app.launch_data_cwd, 'compact folder choice did not dispatch')
	app.handle('software.launch.data-cwd')!
	compact_launch_require(app.launch_data_cwd, 'compact private folder choice did not dispatch')
	app.launch_page = 99; free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	app.launch_page = 4
	app.handle('software.report.read')!
	compact_launch_require(app.report_reader_mode, 'Read draft did not open')
	app.handle('software.launch.page.previous')!; app.handle('software.launch.file.previous')!
	compact_launch_require(app.launch_page == 4 && app.launch_file_scroll == 250, 'reader allowed hidden page action')
	app.key_input('\x1b')
	app.handle('software.status')!; compact_launch_require(app.status_reader.mode, 'Status did not open')
	app.key_input('\x1b')
	compact_launch_tree(mut app, 160, 96, 'software.launch.back')!
	compact_launch_require(app.launch_documents.len == 255, 'tiny layout discarded draft')
	app.handle('software.launch.back')!
	compact_launch_require(!app.launch_mode && app.query.bytestr() == 'kept query' && app.filter == 2, 'Back lost catalog state')
	app.selected = 1; app.handle('software.run-options')!
	compact_launch_page(mut app, 1)!
	tree := app.build(ui2.rect(0, 0, 320, 240))!
	compact_launch_require(!tree.children.any(it.id in ['software.launch.file', 'software.launch.add-file']), 'installed permission refusal missing')
	free_window_tree(tree)
	app.handle('software.launch.file')!; app.paste_input('/private/tmp/refused'); app.handle('software.launch.add-file')!
	compact_launch_require(app.launch_documents.len == 0 && app.status.contains('does not declare file access'), 'injected grant bypassed installed permission')
	app.handle('software.launch.back')!; app.selected = 0
	files := launch_navigation_files()
	defer { unsafe { (&array(&files)).free() } }
	fill_launch_navigation_draft(mut app, files)!
	compact_launch_page(mut app, 4)!
	app.handle('software.launch.file')!; app.paste_input('/private/tmp/pending')
	compact_launch_page(mut app, 4)!; app.handle('software.launch.run')!
	compact_launch_require(app.worker == unsafe { nil } && app.status.contains('Add the entered file'), 'run accepted unsubmitted file')
	app.handle('software.launch.file')!; app.key_input('\x01'); app.key_input('\x08')
	app.handle('software.launch.arguments')!; app.key_input('\x01'); app.paste_input('"unfinished')
	compact_launch_page(mut app, 4)!; app.handle('software.launch.run')!
	compact_launch_require(app.worker == unsafe { nil } && app.status.contains('quoted argument'), 'run accepted invalid argument quoting')
	app.handle('software.launch.arguments')!; app.key_input('\x01'); app.paste_input(launch_navigation_arguments)
	compact_launch_page(mut app, 4)!
	mut words := pkgprotocol.command_words(launch_navigation_arguments)!
	mut vector := pkgprotocol.command_vector('launch-app', words, files, false, false)!
	defer { pkgprotocol.free_command_values(mut words); pkgprotocol.free_command_values(mut vector) }
	receipt := os.temp_dir() + '/vinix-compact-launch-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION_RECEIPT', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION'); os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION_RECEIPT') }
	for mode in ['failed', 'complete']! {
		os.setenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION', mode, true)
		app.handle('software.launch.run')!
		compact_launch_require(app.worker != unsafe { nil }, 'Run did not create worker')
		pid := app.worker.pid
		for _ in 0 .. 5000 { app.poll(); if app.output.len > 0 { break }; time.sleep(time.millisecond) }
		compact_launch_require(app.output.len > 0 && app.worker != unsafe { nil } && app.worker.args == vector && app.worker_run, 'literal worker did not reach barrier')
		compact_launch_require(!app.prepare_close(), 'live worker lost close guard')
		for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
			busy := app.build(size)!
			compact_launch_require(!busy.children.any(it.id in ['software.launch.back', 'software.launch.run', 'software.launch.terminal', 'software.launch.page.previous', 'software.launch.page.next', 'software.launch.add-file']), 'live worker exposed a mutating control')
			free_window_tree(busy)
		}
		for event in ['software.launch.page.previous', 'software.launch.page.next', 'software.launch.file.previous', 'software.launch.file.next', 'software.launch.back', 'software.launch.arguments', 'software.launch.file', 'software.launch.data-cwd', 'software.launch.add-file', 'software.launch.remove-file', 'software.launch.up', 'software.launch.down', 'software.launch.file.0', 'software.launch.run', 'software.launch.terminal']! { app.handle(event)! }
		app.key_input('\x1b[C'); app.key_input('\x1b'); app.paste_input('blocked')
		compact_launch_require(app.worker.pid == pid && C.kill(pid, 0) == 0 && app.launch_page == 4 && app.launch_focus == 0
			&& app.launch_documents == files && app.launch_file_scroll == 2 && app.launch_file_selected == 6
			&& !app.launch_data_cwd && editor_bytes_text(app.launch_arguments) == launch_navigation_arguments && !os.exists(receipt), 'worker allowed draft mutation or exited before release')
		app.worker.stdin_write('x'); wait_for_software(mut app)
		compact_launch_require(app.worker == unsafe { nil } && app.launch_mode && json2.decode[[]string](os.read_file(receipt)!)! == vector, 'worker completion lost draft or command receipt')
		if mode == 'failed' {
			compact_launch_require(app.failure_pages.len > 0, 'failed run lost diagnostic')
			compact_launch_page(mut app, 5)!; compact_launch_tree(mut app, 320, 240, 'software.failure')!
			app.handle('software.failure')!; app.key_input('\x1b')
			compact_launch_require(!app.failure_mode && app.launch_mode, 'failure reader did not return to launch draft')
			compact_launch_page(mut app, 4)!
		} else { compact_launch_require(app.status.contains('finished successfully'), 'successful retry not reported') }
		os.rm(receipt)!
	}
	os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION')
	compact_launch_tree(mut app, 320, 240, 'software.launch.terminal')!
	app.handle('software.launch.terminal')!
	mut terminal_vector := pkgprotocol.command_vector('launch-app', words, files, false, true)!
	defer { pkgprotocol.free_command_values(mut terminal_vector) }
	compact_launch_require(!app.launch_mode && app.terminal_app != unsafe { nil } && app.terminal_app.argv == [app.service_path, ...terminal_vector], 'Terminal did not receive exact literal command')
	app.terminal_app.exited = true; app.close_terminal()
	println('Software compact launch: PASS')
}

fn check_software_launch_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut files := []string{cap: 256}
		for index in 0 .. 256 { files << '/private/tmp/document-' + index.str() + ' é; $literal.txt' }
		defer { pkgprotocol.free_command_values(mut files) }
		arguments := ['run-args']
		defer { unsafe { (&array(&arguments)).free() } }
		mut app := launch_navigation_app()
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				fill_launch_navigation_draft(mut app, files)!
				check_launch_empty_paste(mut app)
				assert app.launch_documents.len == 256 && app.launch_file_scroll == 251 && app.launch_file_selected == 255
				launch_reader_cycle(mut app)!
				app.handle('software.launch.file')!; app.paste_input('/private/tmp/overflow'); app.handle('software.launch.add-file')!
				check_launch_empty_paste(mut app)
				assert app.launch_documents.len == 256 && app.status.contains('At most 256')
				app.launch_file.clear(); app.handle('software.launch.arguments')!; app.key_input('\x01')
				app.paste_input('\x1b'); assert app.launch_focus == 1 && app.launch_mode && app.select_all
				free_window_tree(app.build(ui2.rect(0, 0, 900, 660))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.key_input('\x1b'); assert app.launch_mode && app.launch_focus == 0 && !app.select_all
				app.handle('software.launch.remove-file')!
				assert app.launch_documents.len == 255 && app.launch_file_selected == -1
				app.handle('software.launch.file')!; app.paste_input(files[255]); app.handle('software.launch.add-file')!
				assert app.launch_documents.len == 256
				app.capture_failure(arguments, 27)
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.handle('software.launch.terminal')!
				assert app.terminal_app != unsafe { nil } && !app.launch_mode && app.launch_documents.len == 0
				app.terminal_app.exited = true; app.close_terminal(); app.clear_failure()
				app.open_launch_options(); app.key_input('\x1b'); assert !app.launch_mode && app.launch_documents.len == 0
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'launch navigation retained ${kept} bytes'
		println('Software launch navigation: 1000 256-file draft/full/compact/paging/paste/blur/failure/terminal-transfer/retirement cycles retain zero tracked bytes')
		println('Software launch reader: 1000 entry/file/page/render/resize/ignored-run/Back/cache-retirement cycles retain zero tracked bytes')
	}
}
