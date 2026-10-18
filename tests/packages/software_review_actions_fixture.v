// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import ui2
import tools.packages.pkgprotocol

fn action_fixture_review(format int, action string, previous string, target string) pkgprotocol.Review {
	return pkgprotocol.Review{format: format, operation: 'upgrade', architecture: 'aarch64', fingerprint: 'c'.repeat(64),
		requested: if action == 'remove' { []string{} } else { ['editor'] },
		rows: [pkgprotocol.ReviewPackage{id: 'editor', name: 'Editor', version: target, installed_version: previous,
			architecture: 'aarch64', kind: 'native', repository: 'trusted',
			public_key: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			license: 'MIT', action: action, requested: action != 'remove', permissions: ['files']}]}
}

fn action_fixture_load(mut app SoftwareApp, text string) {
	app.clear_review(); app.review = 'upgrade'.clone()
	metadata_fixture_output(mut app, text); app.load_review()
}

fn action_fixture_refused(mut app SoftwareApp, text string) ! {
	action_fixture_load(mut app, text)
	assert !app.review_ready && app.review == '' && app.review_snapshot.rows.len == 0 && app.review_snapshot.fingerprint == ''
	assert app.status.contains('invalid package review') && !app.admin_prompt && app.worker == unsafe { nil }
	for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
		tree := app.build(size)!; assert !tree.children.any(it.id == 'software.confirm'); free_window_tree(tree)
	}
	app.handle('software.confirm')!
	assert !app.admin_prompt && app.worker == unsafe { nil }
}

fn check_software_review_actions() ! {
	mut app := SoftwareApp{administration_required: true, output: []u8{cap: 8192}}
	defer { app.close_app() }
	for format in [1, 2]! {
		mut valid := action_fixture_review(format, 'update', '1.0.0', '2.0.0')
		good := json2.encode(valid); valid.close()
		defer { unsafe { good.free() } }
		for action in ['install', 'update', 'keep', 'remove']! {
			for previous in ['', '1.0.0']! {
				if action == 'install' && previous == '' { continue }
				if action == 'update' && previous != '' { continue }
				mut review := action_fixture_review(format, action, previous, '2.0.0')
				text := json2.encode(review)
				// Even direct renderer callers must not compare missing old facts
				// as an empty set for an action that claims an installed package.
				if previous == '' || action == 'install' {
					app.review_snapshot = review
					assert app.review_permission_counts() == [0, 0, 1]!
					mut values := []string{cap: 16}
					software_review_permission_values(review.rows[0], mut values)
					assert values.any(it.contains('Unavailable from this service; changes cannot be compared'))
					assert !values.any(it.contains('Not installed') || it.starts_with('Added permission') || it.starts_with('Removed permission') || it.contains('No permission declaration changes'))
					software_policy_free_lines(mut values); app.clear_review()
				} else { review.close() }
				// Replacing a previously ready proposal clears its authority too.
				action_fixture_load(mut app, good); assert app.review_ready
				action_fixture_refused(mut app, text)!
				unsafe { text.free() }
			}
		}
		action_fixture_load(mut app, good)
		assert app.review_ready && app.review_permission_counts() == [0, 0, 1]!
		app.open_details(); mut unknown := details_fixture_values(&app, 3)
		assert unknown.any(it.contains('Unavailable from this service; changes cannot be compared'))
		software_policy_free_lines(mut unknown); app.clear_review()
		mut fresh := action_fixture_review(format, 'install', '', '2.0.0')
		fresh_text := json2.encode(fresh); fresh.close(); action_fixture_load(mut app, fresh_text)
		assert app.review_ready && app.review_permission_counts() == [1, 0, 0]!
		app.open_details(); mut values := details_fixture_values(&app, 3)
		assert 'Previous declarations: Not installed' in values && 'Added permission declaration: files' in values
		software_policy_free_lines(mut values); unsafe { fresh_text.free() }; app.clear_review()
	}
	println('REVIEW ACTIONS Software rejects contradictory current/legacy rows before confirmation, clears prior proposals and preserves conservative permission history PASS')
}

fn check_software_review_actions_memory() ! {
	$if !track_heap ? { return error('compile review action memory with -d track_heap') }
	$if track_heap ? {
		mut texts := []string{cap: 8}
		for format in [1, 2]! {
			for action in ['update', 'keep', 'remove', 'install']! {
				mut review := action_fixture_review(format, action, '', '2.0.0')
				texts << json2.encode(review); review.close()
			}
		}
		mut app := SoftwareApp{administration_required: true, output: []u8{cap: 8192}}
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for index, text in texts {
					if index % 4 == 3 {
						action_fixture_load(mut app, text)
						assert app.review_ready && app.review_permission_counts() == [1, 0, 0]!
						app.open_details(); app.handle_details('software.details.permissions')
						free_window_tree(app.build_details(320, 240)); app.clear_review()
					} else { action_fixture_refused(mut app, text)! }
				}
			}
		}
		app.close_app()
		kept := C.vinix_heap_end(); assert kept == 0, 'review actions retained ' + kept.str()
		unsafe { for text in texts { text.free() }; (&array(&texts)).free() }
		println('REVIEW ACTIONS 1000 current/legacy refusal/render/blocked-confirm and new-install/permission/retirement cycles retain zero tracked bytes PASS')
	}
}
