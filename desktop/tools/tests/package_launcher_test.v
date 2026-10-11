// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.packagecore
import desktop.sessioncore
import ui2
import os
import json2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn package_assert_heap_flat(label string) {
	retained := C.vinix_heap_end()
	if retained > 0 { eprintln('${label}: ${retained} retained bytes') }
	assert retained == 0
}

fn package_tree_has(element ui2.Element, id string) bool {
	if element.id == id { return true }
	for child in element.children { if package_tree_has(child, id) { return true } }
	return false
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
