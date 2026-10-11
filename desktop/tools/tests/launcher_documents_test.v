// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os

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
	defer { desktop.switcher_close(); launcher_documents.close() }
	assert launcher_index_worker > 0
	for _ in 0 .. 300 { desktop.poll_workflow_search(); if launcher_index_worker == 0 { break }; desktop_sleep_ms(10) }
	assert launcher_index_worker == 0
	desktop.quick_launch_take_keys('uniquelysearchabledocument')
	assert desktop.quick_launch_match_count() == 1
	begin_frame_elements()
	tree := desktop.build_tree()
	free_tree(tree)
	os.chmod(home + '/meeting.txt', 0o000)!
	assert desktop.quick_launch_match_count() == 0
	os.chmod(home + '/meeting.txt', 0o600)!
	launcher_documents.roots[0].contents = false
	launcher_documents.save(home)!
	// The launcher remains open while another Files window changes policy.
	launcher_policy_checked = 0
	desktop.poll_workflow_search()
	assert desktop.quick_launch_match_count() == 0
}
