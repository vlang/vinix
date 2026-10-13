// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.packagecore
import desktop.sessioncore
import ui2
import os
import json2
import time
import tools.packages.pkgprotocol

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.vinix_heap_size_at(u32) u64

fn package_assert_heap_flat(label string) {
	retained := C.vinix_heap_end()
	if retained > 0 {
		mut sizes := map[u64]int{}
		for i in 0 .. C.vinix_heap_count() { sizes[C.vinix_heap_size_at(i)]++ }
		eprintln('${label}: ${retained} retained bytes, sizes=${sizes}')
	}
	assert retained == 0
}

fn package_tree_has(element ui2.Element, id string) bool {
	if element.id == id { return true }
	for child in element.children { if package_tree_has(child, id) { return true } }
	return false
}

fn test_package_terminal_uses_literal_arguments_and_releases_screen_history_and_launch_storage() {
	input := 'sqlite> SELECT 42;\r\n42\r\n'.bytes()
	expected := ['/missing-fixture-package-service', 'run-terminal', 'org.sqlite.cli', '/home/alex/a space; \$literal.txt']
	defer { unsafe { (&array(&expected)).free() } }
	defer { unsafe { input.free() } }
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 50 {
			mut app := SoftwareApp{ service_path: '/missing-fixture-package-service'.clone() }
			app.open_terminal_request(packagecore.Request{ id: 'org.sqlite.cli', document: '/home/alex/a space; \$literal.txt' })!
			assert app.terminal_app.package_argv == expected
			app.terminal_app.started = true // exercise rendering without spawning a host application
			app.terminal_app.set_geometry(3, 40)
			for _ in 0 .. 10 { app.terminal_app.ingest_output(input) }
			assert app.terminal_app.lines.len > 0
			begin_frame_elements()
			tree := app.build(ui2.rect(0, 0, 900, 660))!
			assert !package_tree_has(tree, 'software.terminal-back')
			free_tree(tree)
			assert !app.prepare_close()
			app.handle('software.terminal-back')!
			assert app.terminal_app != unsafe { nil }
			app.terminal_app.exited = true
			begin_frame_elements()
			finished := app.build(ui2.rect(0, 0, 900, 660))!
			assert package_tree_has(finished, 'software.terminal-back')
			free_tree(finished)
			assert app.prepare_close()
			app.handle('software.terminal-back')!
			assert app.terminal_app == unsafe { nil }
			app.close_app()
		}
	}
	retained := C.vinix_heap_end()
	if retained > 0 {
		mut sizes := map[u64]int{}
		for i in 0 .. C.vinix_heap_count() { sizes[C.vinix_heap_size_at(i)]++ }
		eprintln('package terminal retained: ${retained}, sizes=${sizes}')
	}
	assert retained == 0
}

fn test_package_terminal_spawn_retires_parent_argv_and_environment_storage() {
	if !os.is_file('/usr/bin/true') { return }
	args := ['/usr/bin/true', 'run-terminal', 'fixture']
	defer { unsafe { (&array(&args)).free() } }
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 20 {
			child := desktop_spawn_terminal_command(args, 24, 80, 640, 384) or { panic('PTY wrapper failed') }
			mut status := i32(0)
			assert C.waitpid(child.pid, &status, 0) == child.pid
			// /root is a guest directory; host fixtures may correctly refuse it.
			assert status == 0 || status == 126 << 8
			C.close(child.terminal)
		}
	}
	package_assert_heap_flat('package terminal spawn parent storage')
}

fn test_software_launch_options_render_parse_refuse_and_terminal_retirement_keep_heap_flat() {
	expected := ['/missing-fixture-package-service', 'run-terminal-args', 'org.ffmpeg.cli', '--data-cwd', '--file', '/home/alex/a space; $literal.avi', '--', '-i', '/home/alex/a space; $literal.avi', '-f', 'null', '-', '', '$(literal)']
	defer { unsafe { (&array(&expected)).free() } }
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 30 {
			mut app := &SoftwareApp{ service_path: '/missing-fixture-package-service'.clone(),
				rows: [SoftwareRow{ id: 'org.ffmpeg.cli'.clone(), name: 'FFmpeg'.clone(), kind: 'linux'.clone(),
					installed_version: '8.0.1'.clone(), permissions: ['files'.clone()] }], selected: 0 }
			app.handle('software.run-options')!
			assert app.launch_mode && app.launch_data_cwd
			app.handle('software.launch.arguments')!
			app.paste_input('"unterminated')
			app.handle('software.launch.run')!
			assert app.worker == unsafe { nil } && app.status.contains('quoted argument')
			app.key_input('\x01')
			app.paste_input('-i "/home/alex/a space; $literal.avi" -f null - "" $(literal)')
			app.paste_input('\x00')
			assert editor_bytes_text(app.launch_arguments).ends_with('$(literal)')
			app.handle('software.launch.file')!
			for _ in 0 .. 2 {
				app.paste_input('/home/alex/a space; $literal.avi')
				app.handle('software.launch.add-file')!
			}
			assert app.launch_documents.len == 1 && app.status.contains('already allowed')
			app.key_input('\x01'); app.key_input('\x7f')
			for _ in 0 .. 3 {
				begin_frame_elements()
				tree := app.build(ui2.rect(0, 0, 900, 660))!
				assert package_tree_has(tree, 'software.launch.file.0') && package_tree_has(tree, 'software.launch.terminal')
				free_tree(tree)
			}
			app.handle('software.launch.terminal')!
			assert app.terminal_app != unsafe { nil } && !app.launch_mode
			assert app.terminal_app.package_argv == expected
			app.terminal_app.started = true; app.terminal_app.exited = true
			app.handle('software.terminal-back')!
			app.close_app(); unsafe { free(app) }
		}
	}
	package_assert_heap_flat('Software launch options, parser errors and terminal handoff')
}

fn test_software_launch_options_page_remove_bound_and_cancel_explicit_file_grants() {
	mut app := &SoftwareApp{ rows: [SoftwareRow{ id: 'editor'.clone(), name: 'Editor'.clone(), kind: 'native'.clone(),
		installed_version: '1.0.0'.clone(), permissions: ['files'.clone()] }], selected: 0 }
	app.handle('software.run-options')!
	app.handle('software.launch.file')!
	for i in 0 .. 8 {
		path := '/home/alex/' + i.str()
		app.paste_input(path); unsafe { path.free() }
		app.handle('software.launch.add-file')!
	}
	assert app.launch_documents.len == 8 && app.launch_file_scroll == 3
	app.handle('software.launch.up')!
	assert app.launch_file_scroll == 0
	app.handle('software.launch.down')!
	assert app.launch_file_scroll == 5
	app.handle('software.launch.file.0')!
	app.handle('software.launch.remove-file')!
	assert app.launch_documents.len == 7 && '/home/alex/5' !in app.launch_documents
	app.handle('software.launch.arguments')!
	app.paste_input('kept')
	app.key_input('\x01')
	too_large := 'x'.repeat(4097)
	app.paste_input(too_large); unsafe { too_large.free() }
	assert editor_bytes_text(app.launch_arguments) == 'kept'
	app.handle('software.launch.data-cwd')!
	assert !app.launch_data_cwd
	app.handle('software.launch.back')!
	assert !app.launch_mode && app.launch_documents.len == 0 && app.launch_arguments.len == 0
	app.close_app(); unsafe { free(app) }
}

fn test_software_launch_options_use_installed_permissions_and_kind_instead_of_the_pending_update() {
	mut app := &SoftwareApp{ rows: [SoftwareRow{ id: 'editor'.clone(), name: 'Future assets'.clone(), kind: 'data'.clone(),
		installed_name: 'Installed editor'.clone(), installed_kind: 'native'.clone(), installed_version: '1.0.0'.clone(),
		permissions: ['files'.clone()], installed_permissions: [] }], selected: 0 }
	app.handle('software.run-options')!
	assert app.launch_mode && app.launch_name == 'Installed editor' && !app.launch_files_allowed
	app.handle('software.launch.file')!
	app.paste_input('/home/alex/a.txt')
	app.handle('software.launch.add-file')!
	assert app.launch_documents.len == 0 && app.status.contains('does not declare')
	app.close_app(); unsafe { free(app) }
}

fn test_package_terminal_exit_poll_retires_its_output_buffers() {
	if !os.is_file('/usr/bin/true') { return }
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 20 {
			mut terminal := &TerminalApp{ read_buf: []u8{len: terminal_read_chunk} }
			terminal.configure_package(packagecore.Request{ id: 'fixture' }, '/usr/bin/true')!
			terminal.set_geometry(24, 80)
			terminal.start_shell(24, 80, 640, 384)
			for _ in 0 .. 1000 {
				terminal.poll()
				if terminal.exited { break }
				time.sleep(time.millisecond)
			}
			assert terminal.exited && terminal.terminal == -1
			terminal.close_app()
			unsafe { free(terminal) }
		}
	}
	package_assert_heap_flat('package terminal exit poll storage')
}

fn test_package_entries_share_start_quick_launch_and_paged_document_choices() {
	assert sessioncore.mime_for_path('/home/user/Report.TXT') == 'text/plain'
	assert sessioncore.mime_for_path('/home/user/Photo.JPEG') == 'image/jpeg'
	assert sessioncore.mime_for_path('/home/folder.txt/no-extension') == 'application/octet-stream'
	// Owned records have the same lifetime as a real registration load.
	packaged_apps.close()
	packaged_apps.apps = [packagecore.App{
		id:           'org.fixture.editor'.clone()
		name:         'Fixture editor'.clone()
		description:  'Write signed documents'.clone()
		association:  'package.org.fixture.editor'.clone()
		start_action: 'start.package.org.fixture.editor'.clone()
		open_action:  'session.open.package.org.fixture.editor'.clone()
		mime_types:   ['text/plain'.clone()]
	}]
	defer { packaged_apps.close() }
	mut desktop := Desktop{
		canvas:              Canvas{ width: 1024, height: 768 }
		start_menu_open:     true
		start_menu_all_apps: true
		start_menu_query:    []u8{cap: 48}
	}
	defer {
		desktop.free_start_menu_query()
		desktop.quick_launch_free_query()
	}
	for byte in 'signed' { desktop.start_menu_query << byte }
	assert desktop.start_menu_result_count() == 1
	begin_frame_elements()
	start := desktop.start_menu_element()
	assert package_tree_has(start, 'start.package.org.fixture.editor')
	free_tree(start)
	desktop.start_menu_query.clear()
	assert desktop.start_menu_result_count() == available_apps.len + 1
	desktop.switcher.query = 'signed'.bytes()
	assert desktop.quick_launch_match_count() == 1
	assert (desktop.quick_launch_app_index(0) or { panic('missing package result') }) == available_apps.len
	assert desktop_menu_name(available_apps.len) == 'Fixture editor'
	for index in 0 .. 7 { desktop.switcher.ids << 'switch.${index}' }
	begin_frame_elements()
	quick := desktop.quick_launch_element()
	assert package_tree_has(quick, 'switch.0')
	free_tree(quick)
	desktop.hub.open_path.set('/home/user/document.txt')!
	assert desktop.open_with_count() == 6
	desktop.hub.open_page = 1
	begin_frame_elements()
	choices := desktop.open_with_contents(520)
	assert choices.any(it.id == 'session.open.package.org.fixture.editor')
	assert choices.any(it.id == 'session.open.previous')
	for choice in choices { free_tree(choice) }
	// Warm the pooled builders and translated built-ins, then measure actual
	// retention across repeated Start, Quick Launch and Open With redraws.
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 100 {
			begin_frame_elements()
			menu := desktop.start_menu_element()
			desktop.record_subtree_targets(&menu, 0, 0, int(menu.frame.width), int(menu.frame.height))
			free_tree(menu)
			desktop.clear_hit_targets()
			begin_frame_elements()
			launcher := desktop.quick_launch_element()
			desktop.record_subtree_targets(&launcher, 0, 0, int(launcher.frame.width), int(launcher.frame.height))
			free_tree(launcher)
			desktop.clear_hit_targets()
			begin_frame_elements()
			dialog := desktop.open_with_contents(520)
			for child in dialog {
				desktop.record_subtree_targets(&child, 0, 0, int(child.frame.width), int(child.frame.height))
				free_tree(child)
			}
			desktop.clear_hit_targets()
		}
	}
	package_assert_heap_flat('package menu redraw')
	desktop.hub.open_path.set('/home/user/image.png')!
	assert desktop.open_with_count() == 5
	// Installation never sets defaults. A user choice is shared by document
	// entry points, falls back after removal and becomes usable on rollback.
	assert desktop.hub.association_overrides.count == 0
	begin_frame_elements()
	target := desktop.package_menu_button(available_apps.len, 0, 0, 200, 32)
	desktop.record_target(&target, 0, 0, 200, 32)
	assert desktop.targets[0].owns_action
	assert desktop.targets[0].world == .desktop
	desktop.hub.association_overrides.set('text/plain', 'package.org.fixture.editor', false)!
	assert desktop.registered_document_app('/home/user/document.txt', 'vinix-editor') == 'package.org.fixture.editor'
	assert desktop.registered_document_app('/home/user/image.png', 'vinix-preview') == 'vinix-preview'
	packaged_apps.close()
	// Pointer selectors survive registration retirement until the next frame.
	assert desktop.targets[0].action_id == 'start.package.org.fixture.editor'
	desktop.clear_hit_targets()
	unsafe { desktop.targets.free() }
	assert desktop.registered_document_app('/home/user/document.txt', 'vinix-editor') == 'vinix-editor'
	assert desktop.hub.association_overrides.count == 1
	// Restore equivalent registration without changing the stored user choice.
	packaged_apps.apps = [packagecore.App{
		id:           'org.fixture.editor'.clone()
		name:         'Fixture editor'.clone()
		description:  ''.clone()
		association:  'package.org.fixture.editor'.clone()
		start_action: ''.clone()
		open_action:  ''.clone()
		mime_types:   ['text/plain'.clone()]
	}]
	assert desktop.registered_document_app('/home/user/document.txt', 'vinix-editor') == 'package.org.fixture.editor'
}

fn test_package_registry_reload_and_retirement_release_all_storage() {
	root := os.real_path(os.temp_dir()) + '/vinix-package-registry-memory-' + os.getpid().str()
	os.mkdir_all(root + '/generations/1')!
	defer { os.rmdir_all(root) or {} }
	for path in [root, root + '/generations', root + '/generations/1'] { os.chmod(path, 0o755)! }
	state := '{"format":1,"generation":1,"architecture":"aarch64","packages":[{"repository":"publisher","public_key":"ignored-by-presentation","sequence":1,"package":{"id":"editor","name":"Editor","description":"Write text","architecture":"aarch64","kind":"native","permissions":["files"],"associations":["text/plain"],"arguments":["ignored"],"files":[{"path":"bin/editor","sha256":"ignored","bytes":123,"executable":true}]}}]}'
	os.write_file(root + '/generations/1/state.json', state)!
	os.chmod(root + '/generations/1/state.json', 0o644)!
	os.symlink('generations/1', root + '/current')!
	mut registry := packagecore.Registry{}
	assert registry.refresh(root, u32(os.geteuid()), 'aarch64')!
	registry.close()
	// json2 currently boxes a one-byte Error{} to signal successful end of
	// input, and drops it internally even with -manualfree (measured with
	// the allocator and debugger). Compare its independent decode baseline:
	// every allocation owned by the registration must still be retired.
	assert json2.decode[bool]('true')!
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert json2.decode[bool]('true')!
	}
	decoder_baseline := C.vinix_heap_end()
	assert decoder_baseline <= 100
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert registry.refresh(root, u32(os.geteuid()), 'aarch64')!
		assert !registry.refresh(root, u32(os.geteuid()), 'aarch64')!
		registry.close()
	}
	assert C.vinix_heap_end() == decoder_baseline
	assert registry.refresh(root, u32(os.geteuid()), 'aarch64')!
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert !registry.refresh(root, u32(os.geteuid()), 'aarch64')!
	}
	registry.close()
	package_assert_heap_flat('cached package registration')
}

const software_review_fixture = '{"format":1,"operation":"install","names":["editor"],"architecture":"aarch64","generation":1,"target_generation":0,"fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","requested":["editor"],"disk_needed":4096,"disk_available":65536,"disk_reserve":1024,"rows":[{"id":"editor","name":"Editor","description":"Write text","version":"2.0.0","installed_version":"1.0.0","architecture":"aarch64","kind":"linux","runtime":"runtime","repository":"trusted","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","license":"MIT","permissions":["files"],"requested":true,"action":"update"},{"id":"runtime","name":"Runtime","description":"Explicit runtime","version":"2.0.0","installed_version":"1.0.0","architecture":"aarch64","kind":"runtime","repository":"vendor","public_key":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","license":"Vendor-EULA","proprietary":true,"firmware":true,"permissions":["network","process"],"action":"update"}]}'

const software_repository_status_fixture = '{"format":1,"architecture":"aarch64","repositories":[{"id":"fixture","url":"https://example.invalid/catalog","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],"history":[{"id":"fixture","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","sequence":7,"index_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}]}'
const software_repository_review_fixture = '{"format":1,"architecture":"aarch64","operation":"enroll","id":"fixture","url":"https://example.invalid/a/long/catalog/path/which/must/be/reviewed/completely/before/confirmation/including/this/final/segment","public_key":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","previous_url":"https://example.invalid/catalog","previous_public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","fingerprint":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","index_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","sequence":7,"expires":2000000000,"package_count":3,"remembered_sequence":6}'

fn test_repository_management_redraw_decode_and_retirement_release_storage() {
	mut app := SoftwareApp{ repository_mode: true, output: software_repository_status_fixture.bytes() }
	app.load_repositories()
	app.handle_repositories('software.row.0')
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	}
	package_assert_heap_flat('Software repository form redraw')
	C.vinix_heap_begin()
	for _ in 0 .. 100 { assert json2.decode[bool]('true')! }
	baseline := C.vinix_heap_end()
	C.vinix_heap_begin()
	for _ in 0 .. 100 { app.load_repositories() }
	app.close_app()
	assert C.vinix_heap_end() == baseline
	mut review := pkgprotocol.decode_repository_review(software_repository_review_fixture)!
	mut reviewing := SoftwareApp{ repository_mode: true, output: software_repository_review_fixture.bytes(),
		repository_operation: 'enroll'.clone(), repository_pending: pkgprotocol.Repository{
			id: review.id.clone(), url: review.url.clone(), public_key: review.public_key.clone()
		} }
	review.close()
	reviewing.load_repository_review()
	assert reviewing.repository_url_pages.len > 1 && reviewing.repository_review_ready
	begin_frame_elements()
	free_tree(reviewing.build(ui2.rect(0, 0, 640, 610))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for page in 0 .. reviewing.repository_url_pages.len {
			reviewing.repository_url_page = page
			begin_frame_elements()
			free_tree(reviewing.build(ui2.rect(0, 0, 640, 610))!)
		}
	}
	package_assert_heap_flat('Software repository review and URL paging redraw')
	C.vinix_heap_begin()
	for _ in 0 .. 100 { reviewing.load_repository_review() }
	reviewing.close_app()
	assert C.vinix_heap_end() == baseline
}

const software_updates_fixture = '{"format":1,"architecture":"aarch64","rows":[{"id":"runtime","name":"Runtime","description":"Explicit runtime","version":"2.0.0","installed_version":"1.0.0","architecture":"aarch64","kind":"runtime","repository":"trusted","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","license":"MIT","permissions":["process"],"updatable":true,"update_action":"update"},{"id":"assets","name":"Retired assets","version":"1.0.0","installed_version":"1.0.0","architecture":"all","kind":"data","repository":"trusted","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","license":"MIT","updatable":true,"update_action":"remove"}]}'
const software_blocked_updates_fixture = '{"format":1,"architecture":"aarch64","update_error":"runtime: permissions blocked by organization policy","rows":[{"id":"runtime","name":"Runtime","description":"Explicit runtime","version":"1.0.0","installed_version":"1.0.0","architecture":"aarch64","kind":"runtime","repository":"trusted","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","license":"MIT","permissions":["process"],"diagnostic":"runtime: permissions blocked by organization policy"}]}'

fn test_software_resolved_update_redraw_reload_and_failure_storage_are_released() {
	mut app := SoftwareApp{ output: software_updates_fixture.bytes() }
	app.load_view()
	app.selected = 0
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		for selected in 0 .. 2 {
			app.selected = selected
			begin_frame_elements()
			free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
		}
	}
	package_assert_heap_flat('Software resolved updates redraw')
	C.vinix_heap_begin()
	for _ in 0 .. 100 { assert json2.decode[bool]('true')! }
	baseline := C.vinix_heap_end()
	C.vinix_heap_begin()
	for _ in 0 .. 100 { app.load_view() }
	app.close_app()
	assert C.vinix_heap_end() == baseline
	mut blocked := SoftwareApp{ output: software_blocked_updates_fixture.bytes() }
	blocked.load_view()
	blocked.handle('software.updates')!
	assert blocked.status.contains('permissions blocked') && blocked.matching.len == 0
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		blocked.load_view()
		blocked.handle('software.updates')!
	}
	blocked.close_app()
	assert C.vinix_heap_end() == baseline
}

fn test_software_review_redraw_cancel_and_decoded_storage_are_released() {
	mut app := SoftwareApp{ output: software_review_fixture.bytes(), review: 'install'.clone(), review_names: ['editor'.clone()] }
	app.load_review()
	assert app.review_ready && app.review_snapshot.rows.len == 2
	app.review_selected = 1
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	}
	package_assert_heap_flat('Software review redraw')
	app.clear_review()
	// Compare the JSON decoder's independent EOF allocation baseline.
	C.vinix_heap_begin()
	for _ in 0 .. 100 { assert json2.decode[bool]('true')! }
	baseline := C.vinix_heap_end()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut review := pkgprotocol.decode_review(software_review_fixture)!
		review.validate()!
		review.close()
	}
	assert C.vinix_heap_end() == baseline
	// Warm the status buffer, then exercise the actual decode/cancel UI path.
	app.review = 'install'.clone()
	app.review_names = ['editor'.clone()]
	app.load_review()
	app.clear_review()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.review = 'install'.clone()
		app.review_names = ['editor'.clone()]
		app.load_review()
		assert app.review_ready
		app.clear_review()
	}
	app.close_app() // retire the final persistent status message before measuring
	assert C.vinix_heap_end() == baseline
}

fn test_software_deployment_form_review_and_retirement_release_storage() {
	mut app := SoftwareApp{ deployment_mode: true, output: []u8{cap: 8192} }
	app.initialize_deployment_field()
	software_repository_text(mut app.deployment_path, '/etc/company/deployment with spaces.json')
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	}
	package_assert_heap_flat('Software deployment form redraw')
	app.output = software_review_fixture.replace('"operation":"install"', '"operation":"deploy"').bytes()
	app.review = 'deploy'.clone()
	app.deployment_pending = '/etc/company/deployment.json'.clone()
	app.load_review()
	assert app.review_ready
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	}
	package_assert_heap_flat('Software deployment review redraw')
	app.clear_review()
	C.vinix_heap_begin()
	for _ in 0 .. 100 { assert json2.decode[bool]('true')! }
	baseline := C.vinix_heap_end()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.review = 'deploy'.clone()
		app.deployment_pending = '/etc/company/deployment.json'.clone()
		app.load_review()
		assert app.review_ready
		app.clear_review()
	}
	app.close_app()
	assert C.vinix_heap_end() == baseline
}

fn test_software_progress_redraw_and_stream_storage_are_released() {
	text := '{"format":1,"phase":"download","package":"app","repository":"trusted","path":"bin/app","current":64,"total":128}'
	frame := pkgprotocol.progress_prefix + text + '\n'
	mut app := SoftwareApp{ output: []u8{cap: 8192}, query: []u8{cap: 256} }
	app.operation_output(frame)
	assert app.progress_seen
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	}
	package_assert_heap_flat('Software progress redraw')
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut event := pkgprotocol.decode_progress(text)!
		event.close()
	}
	baseline := C.vinix_heap_end()
	C.vinix_heap_begin()
	for _ in 0 .. 100 { app.operation_output(frame) }
	app.close_app()
	assert C.vinix_heap_end() == baseline
}

fn test_software_mirror_form_destination_pages_closure_and_cancel_release_storage() {
	path := '/media/' + 'offline-export-'.repeat(24)
	mut app := SoftwareApp{ mirror_mode: true, mirror_pending: path.clone(), review: 'mirror'.clone(),
		review_names: ['editor'.clone()] }
	app.initialize_mirror_field()
	software_repository_text(mut app.mirror_path, path)
	row_text := software_review_fixture.replace('"operation":"install"', '"operation":"mirror"')
		.replace('"generation":1', '"generation":0').replace('"action":"update"', '"action":"export"')
	text := '{"format":1,"input_destination":"${path}","destination":"${path}","cache_needed":1024,"cache_available":65536,"shared_disk":true,"review":${row_text}}'
	app.output = text.bytes()
	unsafe { row_text.free(); text.free(); path.free() }
	app.load_review()
	assert app.review_ready && app.mirror_details && app.mirror_pages.len > 1
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 640, 610))!)
		app.handle('software.mirror.next')!
		app.handle('software.mirror.previous')!
	}
	package_assert_heap_flat('Software mirror destination redraw and paging')
	for app.mirror_seen + 1 < app.mirror_pages.len { app.handle('software.mirror.next')! }
	app.handle('software.mirror.packages')!
	assert !app.mirror_details
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 900, 660))!)
	}
	package_assert_heap_flat('Software mirror closure redraw')
	app.clear_review()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	}
	package_assert_heap_flat('Software mirror form redraw')
	C.vinix_heap_begin()
	for _ in 0 .. 100 { assert json2.decode[bool]('true')! }
	baseline := C.vinix_heap_end()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.review = 'mirror'.clone()
		app.review_names = ['editor'.clone()]
		app.mirror_pending = editor_bytes_text(app.mirror_path).clone()
		app.load_review()
		assert app.review_ready
		app.clear_review()
	}
	app.close_app()
	retained := C.vinix_heap_end()
	assert retained == baseline
	println('Software offline export memory: redraw/paging=0; review retirement=${retained} bytes (decoder baseline ${baseline})')
}
