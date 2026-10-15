// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn check_repository_report_content(app &SoftwareApp) {
	mut bytes := []u8{}
	unsafe { bytes.flags |= .noslices }
	for page in app.details_pages {
		mut lines := page.text.split_into_lines()
		for line in lines {
			start := if line.starts_with('• ') { 4 } else { 2 }
			for index in start .. line.len { bytes << line[index] }
		}
		software_policy_free_lines(mut lines)
	}
	text := editor_bytes_text(bytes)
	defer { unsafe { bytes.free() } }
	review := app.repository_review
	mut values := ['Operation: ' + review.operation, 'Repository: ' + review.id,
		'Architecture: ' + review.architecture, 'Source URL: ' + review.url,
		'Publisher public key: ' + review.public_key, 'Review fingerprint: ' + review.fingerprint]
	unsafe { values.flags |= .noslices }
	if review.previous_url != '' {
		values << 'Previous source URL: ' + review.previous_url
		values << 'Previous publisher key: ' + review.previous_public_key
	} else { assert text.contains('No previous repository identity is configured.') }
	if review.operation == 'enroll' {
		sequence := review.sequence.str(); remembered := review.remembered_sequence.str()
		count := review.package_count.str(); expires := review.expires.str()
		values << 'Signed catalog SHA-256: ' + review.index_sha256
		values << 'Signed sequence: ' + sequence; values << 'Remembered sequence: ' + remembered
		values << 'Signed catalog entries: ' + count; values << 'Expires (Unix seconds): ' + expires
		unsafe { sequence.free(); remembered.free(); count.free(); expires.free() }
		assert text.contains('independently trusted channel') && text.contains('does not install applications')
		assert text.contains('Old-key applications lose launch and rollback trust') == (review.previous_public_key != '' && review.previous_public_key != review.public_key)
	} else {
		assert text.contains('Revocation disables acquisition, launch and rollback')
		assert text.contains('Installed payloads, personal data and sequence history remain. Uninstall stays available.')
		assert !text.contains('Signed catalog SHA-256:') && !text.contains('Signed sequence:')
	}
	for value in values { assert text.contains(value) }
	software_policy_free_lines(mut values)
	assert text.contains('does not approve the change or complete the source URL review')
}

fn check_repository_reader_boundaries() ! {
	prefix := 'file:///offline/部署 é🚀/'
	url := prefix + 'a'.repeat(4096 - prefix.len)
	old_url := prefix + 'b'.repeat(4096 - prefix.len)
	defer { unsafe { url.free(); old_url.free() } }
	for architecture in ['aarch64', 'x86_64']! {
		for variant in 0 .. 4 {
			key := 'b'.repeat(64); previous_key := 'a'.repeat(64)
			mut review := pkgprotocol.RepositoryReview{ format: 1, architecture: architecture.clone(),
				operation: if variant == 3 { 'revoke'.clone() } else { 'enroll'.clone() }, id: 'fixture'.clone(),
				url: url.clone(), public_key: key, previous_url: if variant == 0 { '' } else if variant == 3 { url.clone() } else { old_url.clone() },
				previous_public_key: if variant == 0 { '' } else if variant == 2 { previous_key.clone() } else { key.clone() },
				fingerprint: 'd'.repeat(64), index_sha256: if variant == 3 { '' } else { 'c'.repeat(64) },
				sequence: if variant == 3 { u64(0) } else { ~u64(0) }, remembered_sequence: if variant == 3 { u64(0) } else { ~u64(0) - 1 },
				expires: if variant == 3 { i64(0) } else { i64(0x7fffffffffffffff) }, package_count: if variant == 3 { 0 } else { 4096 } }
			text := json2.encode(review)
			mut app := SoftwareApp{ repository_mode: true, repository_operation: review.operation.clone(),
				repository_pending: pkgprotocol.Repository{ id: review.id.clone(), url: review.url.clone(), public_key: review.public_key.clone() },
				output: text.bytes(), repository_selected: 7, repository_scroll: 5 }
			app.load_repository_review(); assert app.repository_review_ready
			check_repository_report_content(&app); check_software_report_reader(mut app)!
			assert app.repository_url_seen == 0 && app.repository_url_page == 0
			app.handle('software.repository.confirm')!; assert app.worker == unsafe { nil }
			app.handle('software.repository.cancel')!
			assert !app.repository_review_ready && app.details_pages.len == 0 && app.details_compact_pages.len == 0
			assert !app.report_reader_mode && app.repository_operation == ''
			app.close_app(); review.close(); unsafe { text.free(); previous_key.free() }
		}
	}
	println('Software repository reader: complete trust fields, new/same/rotated keys and revocation effects, both architectures, maximum Unicode sources and counters, frozen URL gate and cache retirement passed')
}

fn check_software_repository_paste() ! {
	mut app := SoftwareApp{ repository_mode: true, service_path: os.executable(), output: []u8{cap: 8192} }
	app.initialize_repository_fields()
	defer { app.close_app() }
	for focus in 1 .. 4 {
		software_repository_text(mut app.repository_id, 'fixture')
		software_repository_text(mut app.repository_url, repository_fixture_url)
		software_repository_text(mut app.repository_key, 'b'.repeat(64))
		app.repository_focus = focus
		for selected in [false, true]! {
			app.select_all = selected
			for input in ['\x1b', '\r', '\n', '\t', '\x1b[Z', '\x01', '\x7f', '\x08', '\x00',
				'file:///trusted\n-source', 'bad\x00field', '\xff', '\xc3', '\xe2\x82', '\xed\xa0\x80', '\xf4\x90\x80\x80', '\xc2\x80', '\xc2\x9f']! {
				app.paste_input(input)
				assert app.repository_mode && app.repository_focus == focus && app.select_all == selected
				assert editor_bytes_text(app.repository_id) == 'fixture' && editor_bytes_text(app.repository_url) == repository_fixture_url
				assert editor_bytes_text(app.repository_key) == 'b'.repeat(64) && app.worker == unsafe { nil }
				assert app.repository_operation == '' && !app.admin_prompt
			}
			app.set_status('kept status'); app.paste_input('')
			assert app.select_all == selected && app.status == 'kept status'
		}
		limit := match focus { 1 { 128 } 2 { 4096 } else { 64 } }
		prefix := if focus == 2 { 'file:///offline/部署 é🚀 ; $literal/' } else { '' }
		value := prefix + 'b'.repeat(limit - prefix.len)
		oversized := value + '🚀'
		defer { unsafe { value.free(); oversized.free() } }
		app.select_all = true; app.paste_input(value)
		mut field := match focus { 1 { &app.repository_id } 2 { &app.repository_url } else { &app.repository_key } }
		assert field.len == limit && editor_bytes_text(*field) == value && !app.select_all
		app.paste_input('🚀'); assert editor_bytes_text(*field) == value && !app.select_all && app.status.contains('not truncated')
		app.select_all = true; app.paste_input(oversized)
		assert editor_bytes_text(*field) == value && app.select_all && app.status.contains('not truncated')
		app.paste_input('é🚀'); assert editor_bytes_text(*field) == 'é🚀' && !app.select_all
		app.key_input('\x7f'); assert editor_bytes_text(*field) == 'é'
		app.key_input('\x08'); assert field.len == 0
		app.key_input('typed\xfftext'); assert field.len == 0 && app.status.contains('kept intact')
		app.key_input('literal'); app.key_input('\x01'); app.key_input('\x7f'); assert field.len == 0 && !app.select_all
	}
	software_repository_text(mut app.repository_id, 'fixture')
	software_repository_text(mut app.repository_url, repository_fixture_url)
	software_repository_text(mut app.repository_key, 'b'.repeat(64))
	app.repository_focus = 0; app.select_all = true
	app.paste_input('must not edit'); app.paste_input('\n')
	assert app.repository_focus == 0 && app.select_all && app.worker == unsafe { nil }
	app.repository_focus = 3; app.key_input('\r')
	assert app.worker != unsafe { nil } && app.worker.args == ['repo-review', 'enroll', 'fixture', repository_fixture_url, 'b'.repeat(64)]
	wait_for_software(mut app)
	assert app.repository_review_ready && app.repository_review.id == 'fixture' && app.repository_review.url == repository_fixture_url
	for input in ['\x1b', '\n', '\t', '\x01', '\x7f', 'other source']! { app.paste_input(input) }
	assert app.repository_review_ready && app.repository_operation == 'enroll' && app.worker == unsafe { nil }
	assert app.repository_review.fingerprint == 'd'.repeat(64) && app.repository_url_seen == 0
	app.key_input('\x1b'); assert !app.repository_review_ready && app.repository_operation == ''
	println('Software repository paste: literal bounded UTF-8, atomic control/invalid/overflow refusal, preserved selection, empty/unfocused no-op, key-only commands and frozen trust review PASS')
}

fn software_repository_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('list-') || mode.starts_with('review-') {
		listing := args[1..] == ['--json', 'repo-config']
		reviewing := args[1] == 'repo-review'
		if (mode.starts_with('list-') && !listing) || (mode.starts_with('review-') && !reviewing) { return false }
		text := if listing {
			json2.encode(pkgprotocol.RepositoryConfiguration{ format: 1, scope: 'configuration', architecture: 'aarch64',
				repositories: [pkgprotocol.Repository{ id: 'replacement', url: repository_fixture_url, public_key: 'a'.repeat(64) }] })
		} else {
			assert args[2] in ['enroll', 'revoke']!
			json2.encode(repository_fixture_review(args[2], args[3], if args[2] == 'enroll' { args[4] } else { '' },
				if args[2] == 'enroll' { args[5] } else { '' })!)
		}
		partial := mode.ends_with('-partial')
		print(if partial { text[..text.len / 2] } else { text }); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if partial { print(text[text.len / 2..]) }
		return true
	}
	if mode.starts_with('write-') && args[1] in ['repo-apply', 'update']! {
		if args[1] == 'update' { assert os.args[1] == '--progress' }
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'stage', current: 1, total: 2 }))
		flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1 && release == `!`
		if mode == 'write-apply-failed' || (mode == 'write-refresh-failed' && args[1] == 'update') {
			eprintln('Repository operation failed: publisher unreachable. Review or reload to retry.'); exit(23)
		}
		assert software_repository_service_fixture(args)!
		return true
	}
	return false
}

fn wait_for_repository_output(mut app SoftwareApp, progress bool) {
	for _ in 0 .. 1000 {
		app.poll()
		if (progress && app.progress_seen) || (!progress && app.output.len > 0) { return }
		time.sleep(time.millisecond)
	}
	assert false, 'repository fixture did not reach its input barrier'
}

fn check_repository_writer_protected(mut app SoftwareApp) ! {
	pid := app.worker.pid
	assert !app.repository_read_running() && !app.prepare_close()
	for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
		tree := app.build(size)!
		assert tree.children.any(it.id == 'software.progress') && tree.children.any(it.text == app.status)
		assert !tree.children.any(it.id in ['software.repository.stop', 'software.repository.cancel', 'software.repository.back', 'software.repository.confirm'])
		free_window_tree(tree)
	}
	for action in ['software.repository.stop', 'software.repository.cancel', 'software.repository.back', 'software.report.read']! { app.handle(action)! }
	assert !app.report_reader_mode && app.details_pages.len == 0 && app.details_compact_pages.len == 0
	for input in ['\x1b', '\n', '\t', '\x01', '\x7f']! { app.paste_input(input) }
	app.key_input('\x1b'); app.stop_repository_read()
	assert app.worker.pid == pid && C.kill(pid, 0) == 0 && app.repository_mode
}

fn check_software_repository_navigation() ! {
	check_software_repository_paste()!
	check_repository_reader_boundaries()!
	receipt := os.temp_dir() + '/vinix-repository-navigation-' + os.getpid().str()
	url := repository_fixture_url + '/部署 ' + 'source-'.repeat(40)
	os.setenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE'); os.unsetenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION') }
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: 'kept search'.bytes(), filter: 1 }
	defer { app.close_app() }
	app.handle('software.repositories')!; wait_for_software(mut app)
	app.handle('software.row.0')!
	software_repository_text(mut app.repository_url, url); software_repository_text(mut app.repository_key, 'b'.repeat(64))
	for kind in ['list', 'enroll', 'revoke']! {
		for ending in ['partial', 'complete']! {
			for action in ['software.repository.stop', 'software.repository.cancel', 'escape']! {
				mode := if kind == 'list' { 'list-' + ending } else { 'review-' + ending }
				os.setenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION', mode, true)
				app.handle(if kind == 'list' { 'software.repository.reload' } else if kind == 'enroll' { 'software.repository.enroll' } else { 'software.repository.revoke' })!
				pid := app.worker.pid
				wait_for_repository_output(mut app, false)
				assert app.repository_read_running() && app.prepare_close() && !app.repository_review_ready && !app.admin_prompt
				for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
					tree := app.build(size)!
					assert tree.children.any(it.id == 'software.repository.stop') && tree.children.any(it.text == app.status)
					assert !tree.children.any(it.id in ['software.repository.confirm', 'software.repository.back', 'software.repository.cancel'])
					free_window_tree(tree)
				}
				app.handle('software.repository.confirm')!; app.handle('software.report.read')!; app.paste_input('must-not-edit')
				assert !app.report_reader_mode && app.details_pages.len == 0 && app.details_compact_pages.len == 0
				for input in ['\x1b', '\n', '\t', '\x01', '\x7f']! { app.paste_input(input) }
				assert app.worker.pid == pid && app.repository_read_running()
				assert !os.exists(receipt) && editor_bytes_text(app.repository_id) == 'fixture'
				if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
				assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && !app.worker_view && !app.worker_review
				assert app.repository_worker == .none && app.repository_operation == '' && !app.repository_review_ready
				assert app.repository_pending.id == '' && app.repository_url_pages.len == 0 && app.output.len == 0 && !app.output_truncated && !app.poll()
				assert app.repository_mode && app.repository_selected == 0 && app.repository_status.repositories[0].id == 'fixture'
				assert editor_bytes_text(app.repository_url) == url && editor_bytes_text(app.repository_key) == 'b'.repeat(64)
				assert app.status.contains('stopped') && !os.exists(receipt)
				os.unsetenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION')
				if kind == 'list' {
					app.handle('software.repository.reload')!; wait_for_software(mut app)
					assert app.repository_status.repositories[0].id == 'fixture'
				} else {
					app.begin_repository_review(kind); wait_for_software(mut app)
					assert app.repository_review_ready && app.repository_review.operation == kind
					for input in ['\x1b', '\n', '\t', '\x01', '\x7f']! { app.paste_input(input) }
					assert app.repository_review_ready && app.worker == unsafe { nil } && app.repository_operation == kind
					compact := app.build(ui2.rect(0, 0, 320, 240))!
					assert compact.children.any(it.id == 'software.repository.cancel') && !compact.children.any(it.id == 'software.repository.confirm')
					free_window_tree(compact)
					check_repository_report_content(&app); check_software_report_reader(mut app)!
					if kind == 'enroll' {
						assert app.repository_url_pages.len > 1 && app.repository_url_seen == 0
						unseen := app.build_repositories(640, 610)
						assert !unseen.children.any(it.id == 'software.repository.confirm'); free_window_tree(unseen)
						app.handle('software.repository.confirm')!; assert app.worker == unsafe { nil }
						for app.repository_url_page + 1 < app.repository_url_pages.len { app.handle('software.repository.url-next')! }
						full := app.build(ui2.rect(0, 0, 640, 610))!
						assert full.children.any(it.id == 'software.repository.confirm'); free_window_tree(full)
					}
					app.key_input('\x1b'); assert app.repository_operation == '' && !app.repository_review_ready
				}
			}
		}
	}
	for operation in ['enroll', 'revoke']! {
		for mode in ['write-complete', 'write-apply-failed', 'write-refresh-failed']! {
			if operation == 'revoke' && mode == 'write-refresh-failed' { continue }
			app.begin_repository_review(operation); wait_for_software(mut app)
			for app.repository_url_page + 1 < app.repository_url_pages.len { app.handle('software.repository.url-next')! }
			assert app.repository_review_ready
			os.setenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION', mode, true)
			app.handle('software.repository.confirm')!
			assert app.worker.args == if operation == 'enroll' { ['repo-apply', 'd'.repeat(64), 'enroll', 'fixture', url, 'b'.repeat(64)] } else { ['repo-apply', 'd'.repeat(64), 'revoke', 'fixture'] }
			wait_for_repository_output(mut app, true); check_repository_writer_protected(mut app)!
			if operation == 'revoke' && mode == 'write-complete' {
				os.setenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION', 'list-complete', true)
			}
			release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
			if operation == 'enroll' && mode != 'write-apply-failed' {
				for _ in 0 .. 1000 { app.poll(); if app.repository_worker == .refresh { break }; time.sleep(time.millisecond) }
				assert app.repository_worker == .refresh
				wait_for_repository_output(mut app, true); check_repository_writer_protected(mut app)!
				if mode == 'write-complete' { os.setenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION', 'list-complete', true) }
				assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
			}
			if mode == 'write-complete' {
				for _ in 0 .. 1000 { app.poll(); if app.repository_worker == .list { break }; time.sleep(time.millisecond) }
				assert app.repository_worker == .list
				wait_for_repository_output(mut app, false)
				assert app.repository_read_running() && app.prepare_close() && os.exists(receipt)
				app.handle('software.repository.stop')!
				assert app.repository_result != '' && os.exists(receipt)
				os.unsetenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION')
				app.handle('software.repository.reload')!
			}
			wait_for_software(mut app)
			assert app.repository_mode && !app.repository_review_ready && app.prepare_close()
			if mode == 'write-complete' { assert app.status.contains(if operation == 'enroll' { 'trusted' } else { 'revoked' }) }
			if mode != 'write-complete' {
				assert app.failure_pages.len > 0 && app.status.contains('publisher unreachable')
				if mode == 'write-refresh-failed' { assert app.status.contains('trust was saved') && os.exists(receipt) }
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.repository.back')
				free_window_tree(compact)
				app.handle('software.failure')!; assert app.failure_mode
				app.handle('software.failure.back')!; assert !app.failure_mode && app.repository_mode
			}
			os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_REPOSITORY_NAVIGATION')
			app.clear_failure()
		}
	}
	app.repository_focus = 2; app.key_input('\x1b'); assert app.repository_mode && app.repository_focus == 0
	app.key_input('\x1b'); wait_for_software(mut app)
	assert !app.repository_mode && app.query.bytestr() == 'kept search' && app.filter == 1
	println('Software repository navigation: compact list/review/status/progress/failures, partial and complete-before-exit Stop/Cancel/Escape, retained inputs/list, fresh paged review, protected apply/refresh and retry passed')
}

fn check_software_repository_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		url := repository_fixture_url + '/部署 ' + 'source-'.repeat(40)
		key := 'b'.repeat(64); old_key := 'a'.repeat(64); fingerprint := 'd'.repeat(64); digest := 'c'.repeat(64)
		review := pkgprotocol.RepositoryReview{ format: 1, architecture: 'aarch64', operation: 'enroll', id: 'fixture', url: url,
			public_key: key, previous_url: repository_fixture_url, previous_public_key: old_key, fingerprint: fingerprint, index_sha256: digest,
			sequence: 7, expires: 2000000000, package_count: 3 }
		texts := [json2.encode(review), json2.encode(pkgprotocol.RepositoryReview{ ...review, operation: 'revoke', url: repository_fixture_url, public_key: old_key, index_sha256: '', sequence: 0, expires: 0, package_count: 0 })]!
		repositories := [pkgprotocol.Repository{ id: 'fixture', url: repository_fixture_url, public_key: old_key }]
		configuration := json2.encode(pkgprotocol.RepositoryConfiguration{ format: 1, scope: 'configuration', architecture: 'aarch64', repositories: repositories })
		arguments := ['repo-apply']
		defer { unsafe { url.free(); key.free(); old_key.free(); fingerprint.free(); digest.free(); configuration.free(); for text in texts { text.free() }; (&array(&repositories)).free(); (&array(&arguments)).free() } }
		mut app := SoftwareApp{ repository_mode: true, output: []u8{cap: 8192} }
		app.initialize_repository_fields(); app.page_rows = 5
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.repository_focus = 2; app.select_all = true
				app.repository_paste_input(url)
				app.repository_paste_input('\x1b'); app.repository_paste_input('bad\xff')
				app.select_all = true; app.repository_paste_input('bad\nsource')
				assert editor_bytes_text(app.repository_url) == url && app.select_all && app.worker == unsafe { nil }
				app.output.clear(); for byte in configuration { app.output << byte }; app.load_repositories()
				software_repository_text(mut app.repository_id, 'fixture'); software_repository_text(mut app.repository_url, url); software_repository_text(mut app.repository_key, key)
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				for index, text in texts {
					app.repository_operation = if index == 0 { 'enroll'.clone() } else { 'revoke'.clone() }
					app.repository_pending = pkgprotocol.Repository{ id: 'fixture'.clone(), url: url.clone(), public_key: key.clone() }
					app.output.clear(); for byte in text { app.output << byte }; app.load_repository_review(); assert app.repository_review_ready
					for app.repository_url_page + 1 < app.repository_url_pages.len { app.handle_repositories('software.repository.url-next') }
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					page := app.repository_url_page; seen := app.repository_url_seen
					report_reader_cycle(mut app)!
					assert app.repository_url_page == page && app.repository_url_seen == seen && app.repository_review_ready
					app.repository_key_input('\x1b'); assert !app.repository_review_ready
				}
				app.capture_failure(arguments, 23); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!); app.clear_failure()
			}
		}
		// The last successfully decoded list is live state until explicitly
		// retired; include its retirement before measuring retained allocations.
		app.repository_status.close(); app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'repository navigation retained ${kept} bytes'
		println('Software repository navigation: 1000 configuration/enrollment/revocation/page/full/compact/failure/cancel/retirement cycles retain zero tracked bytes')
		println('Software repository paste: 1000 valid/rejected/selected-input cycles retain zero tracked bytes')
		println('Software repository reader: 1000 enrollment/revocation/read/page/resize/ignored-confirm/Back/cancel/retirement cycles retain zero tracked bytes')
	}
}
