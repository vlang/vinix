// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import ui2
import desktop.workflowcore

fn launcher_wait_for_search(mut desktop Desktop, count int) {
	for _ in 0 .. 500 {
		desktop.poll_workflow_search()
		if launcher_index_worker == 0 && desktop.switcher.search.requested
			&& desktop.switcher.search.worker == 0 && desktop.switcher.search.results.len == count {
			return
		}
		desktop_sleep_ms(10)
	}
	assert launcher_index_worker == 0
	assert desktop.switcher.search.requested
	assert desktop.switcher.search.worker == 0
	assert desktop.switcher.search.results.len == count
}

fn launcher_tree_has_result(element ui2.Element, text string, image string) bool {
	if element.text == text && element.image_path == image { return true }
	for child in element.children {
		if launcher_tree_has_result(child, text, image) { return true }
	}
	return false
}

fn launcher_change_query(mut desktop Desktop, query string) {
	desktop.quick_launch_reset_query()
	desktop.quick_launch_take_keys(query)
}

fn test_default_app_routes_shared_document_formats() {
	assert workflow_default_app('/missing/plot.vgraph') == 'vinix-grapher'
	for suffix in ['.pdf', '.doc', '.docx', '.xlsx', '.epub', '.avi', '.m4a']! {
		assert workflow_default_app('/missing/document' + suffix) == 'vinix-preview'
	}
	assert workflow_default_app('/missing/archive.tar') == 'vinix-archive'
	for suffix in ['.zip', '.tgz', '.7z', '.rar']! {
		assert workflow_default_app('/missing/archive' + suffix) == 'vinix-preview'
	}
	assert workflow_default_app('/missing/source.v') == 'vinix-editor'
}

fn test_launcher_indexes_home_before_files_is_opened_and_hides_revoked_matches() {
	home := os.real_path(os.temp_dir()) + '/vinix-launcher-index-${C.getpid()}'
	os.mkdir_all(home)!
	defer { os.rmdir_all(home) or {} }
	os.write_file(home + '/meeting.txt', 'UniquelySearchableDocument')!
	mut desktop := Desktop{home: home, canvas: Canvas{width: 1024, height: 768}}
	desktop.toggle_quick_launch()
	defer { desktop.switcher_close(); desktop.close_quick_launch_search() }
	// Opening the overlay and typing never load the index on the compositor's
	// input path. Polling starts the deferred workers afterwards.
	assert launcher_index_worker == 0
	assert desktop.switcher.search.worker == 0
	desktop.quick_launch_take_keys('uniquelysearchabledocument')
	assert desktop.quick_launch_match_count() == 0
	launcher_wait_for_search(mut desktop, 1)
	assert desktop.quick_launch_match_count() == 1
	begin_frame_elements()
	tree := desktop.build_tree()
	free_tree(tree)
	mut index := workflowcore.load_index(home)!
	defer { index.close() }
	index.roots[0].contents = false
	index.save(home)!
	// The launcher remains open while another Files window changes policy.
	desktop.switcher.search.refresh_at = 0
	desktop.poll_workflow_search()
	launcher_wait_for_search(mut desktop, 0)
	assert desktop.quick_launch_match_count() == 0
	index.roots[0].contents = true
	index.save(home)!
	desktop.switcher.search.refresh_at = 0
	desktop.poll_workflow_search()
	launcher_wait_for_search(mut desktop, 1)
	os.chmod(home + '/meeting.txt', 0o000)!
	defer { os.chmod(home + '/meeting.txt', 0o600) or {} }
	desktop.switcher.search.refresh_at = 0
	desktop.poll_workflow_search()
	launcher_wait_for_search(mut desktop, 0)
}

fn test_launcher_finds_folders_later_and_orders_them_before_documents() {
	home := os.real_path(os.temp_dir()) + '/vinix-launcher-folders-${C.getpid()}'
	folder := home + '/Spotlight Projects with a directory name longer than forty eight bytes'
	os.mkdir_all(folder)!
	defer { os.rmdir_all(home) or {} }
	os.write_file(home + '/Spotlight Plan.txt', 'Project plan')!
	mut desktop := Desktop{home: home, canvas: Canvas{width: 1024, height: 768}}
	desktop.toggle_quick_launch()
	defer { desktop.switcher_close(); desktop.close_quick_launch_search() }
	desktop.quick_launch_take_keys('spotlight')
	assert desktop.quick_launch_match_count() == 0
	assert desktop.quick_launch_search_pending()
	assert desktop.switcher.search.worker == 0
	begin_frame_elements()
	pending := desktop.build_tree()
	assert launcher_tree_has_result(pending, 'Searching folders and documents…', '')
	free_tree(pending)
	launcher_wait_for_search(mut desktop, 2)
	assert desktop.switcher.search.results[0].path == folder
	assert desktop.switcher.search.results[0].directory
	assert !desktop.switcher.search.results[1].directory
	begin_frame_elements()
	tree := desktop.build_tree()
	assert launcher_tree_has_result(tree, folder, 'builtin:folder')
	free_tree(tree)
	assert workflow_default_app(folder) == 'vinix-files'
	assert desktop.session_document_app(folder, 'vinix-editor') == 'vinix-files'

	launcher_change_query(mut desktop, '~/Spotlight Pro')
	assert desktop.switcher.search.results.len == 0
	launcher_wait_for_search(mut desktop, 1)
	assert desktop.switcher.search.results[0].path == folder
	launcher_change_query(mut desktop, folder)
	assert folder.len > 48
	assert desktop.quick_launch_query_text() == folder
	launcher_wait_for_search(mut desktop, 1)
	assert desktop.switcher.search.results[0].path == folder
}

fn test_launcher_discards_old_worker_results_after_typing_changes() {
	home := os.real_path(os.temp_dir()) + '/vinix-launcher-stale-${C.getpid()}'
	os.mkdir_all(home + '/Original Folder')!
	defer { os.rmdir_all(home) or {} }
	mut desktop := Desktop{home: home, canvas: Canvas{width: 1024, height: 768}}
	desktop.toggle_quick_launch()
	defer { desktop.switcher_close(); desktop.close_quick_launch_search() }
	desktop.quick_launch_take_keys('original')
	launcher_wait_for_search(mut desktop, 1)
	// Launch a fresh worker for the old query, then change the field before its
	// completion is polled. Its generation must never repopulate this field.
	desktop.quick_launch_search_changed()
	desktop.switcher.search.due = 0
	desktop.poll_workflow_search()
	assert desktop.switcher.search.worker > 0
	desktop.quick_launch_take_keys('missing')
	assert desktop.quick_launch_query_text() == 'originalmissing'
	assert desktop.switcher.search.results.len == 0
	launcher_wait_for_search(mut desktop, 0)
	assert desktop.quick_launch_match_count() == 0
}

fn test_launcher_deferred_replies_and_refresh_preserve_selected_application() {
	home := os.real_path(os.temp_dir()) + '/vinix-launcher-selection-${C.getpid()}'
	os.mkdir_all(home + '/Calendar Notes')!
	defer { os.rmdir_all(home) or {} }
	mut desktop := Desktop{home: home, canvas: Canvas{width: 1024, height: 768}}
	desktop.toggle_quick_launch()
	defer { desktop.switcher_close(); desktop.close_quick_launch_search() }
	desktop.quick_launch_take_keys('cal')
	assert desktop.quick_launch_match_count() == 6
	assert launcher_index_worker == 0
	assert desktop.switcher.search.worker == 0
	assert !desktop.switcher.search.requested
	desktop.quick_launch_move_selection(1)
	assert desktop.switcher.index == 1
	launcher_wait_for_search(mut desktop, 1)
	assert desktop.switcher.index == 1
	app := desktop.quick_launch_app_index(desktop.switcher.index) or { panic('selected application disappeared') }
	assert available_apps[app].title == 'Calendar'
	desktop.switcher.search.refresh_at = 0
	desktop.poll_workflow_search()
	assert desktop.switcher.search.worker > 0
	launcher_wait_for_search(mut desktop, 1)
	assert desktop.switcher.index == 1
}

fn test_launcher_dismissal_reaps_an_active_query_and_closes_its_pipe() {
	home := os.real_path(os.temp_dir()) + '/vinix-launcher-dismiss-${C.getpid()}'
	os.mkdir_all(home)!
	defer { os.rmdir_all(home) or {} }
	mut desktop := Desktop{home: home, canvas: Canvas{width: 1024, height: 768}}
	desktop.toggle_quick_launch()
	defer { desktop.close_quick_launch_search() }
	desktop.quick_launch_take_keys('missing')
	desktop.switcher.search.due = 0
	desktop.poll_workflow_search()
	assert desktop.switcher.search.worker > 0
	assert desktop.switcher.search.fd >= 0
	desktop.switcher_close()
	for _ in 0 .. 500 {
		desktop.poll_workflow_search()
		if desktop.switcher.search.worker == 0 { break }
		desktop_sleep_ms(10)
	}
	assert desktop.switcher.search.worker == 0
	assert desktop.switcher.search.fd == -1
	assert desktop.switcher.search.bytes.len == 0
	assert desktop.switcher.search.results.len == 0
}
