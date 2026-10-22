// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn release_choice_test_home(name string) string {
	path := os.join_path(os.temp_dir(), 'vinix-release-choice-${os.getpid()}-${name}')
	os.mkdir(path) or { panic(err) }
	return path
}

fn test_release_choice_translations_include_every_prompt_key() {
	for language in desktop_languages {
		for suffix in ['heading', 'intro', 'removals', 'confirm', 'review', 'skip', 'save_failed']! {
			key := 'app_selection.release.' + suffix
			assert desktop_translations[language.code()][key].len > 0, '${language.code()} lacks ${key}'
		}
	}
}

fn test_release_choice_reaches_new_native_accounts_without_registration_or_pkg() {
	home := release_choice_test_home('account')
	defer { os.rmdir_all(home) or {} }
	declaration := home + '/applications.json'
	assert !first_run_release_pending(home, 1000, declaration)
	os.write_file(declaration, '{"format":1,"architecture":"aarch64","packages":["editor"]}\n')!
	assert !desktop_app_selection_pending(home)
	marker := home + '/' + first_run_release_decision_name
	for invalid in ['', 'review', 'skip\nextra', 'x'.repeat(1024)] {
		os.write_file(marker, invalid)!
		assert !first_run_release_decided(home)
		assert first_run_release_pending(home, 1000, declaration)
	}
	os.rm(marker)!
	os.symlink(declaration, marker)!
	assert !first_run_release_decided(home)
	os.rm(marker)!
	assert first_run_release_pending(home, 1000, declaration)
	assert first_run_release_pending(home, 1001, declaration)
	assert !first_run_release_pending(home, 0, declaration)
	assert desktop_mark_app_selection_pending(home)
	assert first_run_release_pending(home, 0, declaration)
	os.rename(declaration, declaration + '.real')!
	os.symlink(declaration + '.real', declaration)!
	assert !first_run_release_pending(home, 1000, declaration)
	os.rm(declaration)!
	os.mkdir(declaration)!
	assert !first_run_release_pending(home, 1000, declaration)
}

fn test_release_choice_skip_is_durable_and_save_failure_keeps_choice_open() {
	home := release_choice_test_home('save')
	defer { os.rmdir_all(home) or {} }
	declaration := home + '/applications.json'
	marker := home + '/' + first_run_release_decision_name
	os.write_file(declaration, '{}')!
	os.write_file(home + '/unchanged', 'personal file')!
	assert desktop_mark_app_selection_pending(home)
	// Crash leftovers, including the previous fixed-name link, cannot block or
	// redirect the new private temporary record. A failed publish stays open.
	os.symlink(home + '/unchanged', marker + '.new')!
	os.write_file(marker + '.new.OLD123', 'interrupted write')!
	os.mkdir(marker)!
	mut state := FirstRunReleaseState{}
	state.handle_action(action_first_run_release_skip, home)
	assert state.choice == .pending && state.save_failed
	assert desktop_app_selection_pending(home) && !first_run_release_decided(home)
	assert os.read_file(home + '/unchanged')! == 'personal file'
	os.rmdir(marker)!
	state.handle_action(action_first_run_release_skip, home)
	assert state.choice == .skip && first_run_release_decided(home)
	assert os.read_file(marker)! == 'skip\n'
	assert os.read_file(marker + '.new.OLD123')! == 'interrupted write'
	assert os.read_file(home + '/unchanged')! == 'personal file'
	assert !desktop_app_selection_pending(home)
	assert !first_run_release_pending(home, 1000, declaration)
	assert os.read_file(declaration)! == '{}'
	state.handle_action(action_first_run_release_review, home)
	assert os.read_file(marker)! == 'skip\n'
}

fn release_choice_test_action(root ui2.Element, action string) ?ui2.Element {
	if root.action_id == action || root.id == action { return root }
	for child in root.children {
		if found := release_choice_test_action(child, action) { return found }
	}
	return none
}

fn test_release_choice_explicit_buttons_and_keyboard_require_a_saved_decision() {
	home := release_choice_test_home('input')
	defer { os.rmdir_all(home) or {} }
	desktop := Desktop{ canvas: Canvas{ width: 1024, height: 768, scale: 1 } }
	mut state := FirstRunReleaseState{}
	begin_frame_elements()
	tree := state.element(&desktop)
	defer { free_tree(tree) }
	review := release_choice_test_action(tree, action_first_run_release_review) or { panic('missing review') }
	skip := release_choice_test_action(tree, action_first_run_release_skip) or { panic('missing skip') }
	assert review.text == 'Review release applications' && review.kind == .button && review.id == action_first_run_release_review
	assert skip.text == 'Skip for now' && skip.kind == .button && skip.id == action_first_run_release_skip
	assert !first_run_release_decided(home)
	state.key_input('\t\r', home)
	assert state.choice == .skip && first_run_release_decided(home)
	os.rm(home + '/' + first_run_release_decision_name)!
	state = FirstRunReleaseState{}
	state.handle_action(review.id, home)
	assert state.choice == .review
	assert os.read_file(home + '/' + first_run_release_decision_name)! == 'review\n'
}

fn test_release_choice_compact_buttons_and_warnings_fit_the_screen() {
	mut fonts := load_fonts()
	defer { free_fonts(mut fonts); set_desktop_language(.en) }
	for size in [[320, 240]!, [320, 768]!, [640, 480]!, [1024, 768]!] {
		desktop := Desktop{ canvas: Canvas{ width: size[0], height: size[1], scale: 1 }, fonts: fonts }
		for language in desktop_languages {
			set_desktop_language(language)
			for failed in [false, true]! {
			begin_frame_elements()
			tree := FirstRunReleaseState{save_failed: failed}.element(&desktop)
			card := release_choice_test_action(tree, 'apps.release.window') or { panic('missing card') }
			review := release_choice_test_action(tree, action_first_run_release_review) or { panic('missing review') }
			for action in [action_first_run_release_review, action_first_run_release_skip]! {
				button := release_choice_test_action(tree, action) or { panic('missing button') }
				assert button.frame.x >= 0 && button.frame.x + button.frame.width <= card.frame.width
				assert button.frame.y >= 0 && button.frame.y + button.frame.height <= card.frame.height
				assert card.frame.y + button.frame.y + button.frame.height <= size[1]
				assert desktop.face_for(button.text_style).text_width(button.text) <= button.frame.width
			}
			mut warnings := ''
			for child in card.children {
				if child.kind != .label || child.id != '' { continue }
				assert child.frame.y + child.frame.height <= review.frame.y, '${language.code()} warning overlaps Review'
				assert desktop.face_for(child.text_style).text_width(child.text) <= child.frame.width
				warnings += child.text
			}
			for suffix in ['removals', 'confirm']! {
				assert warnings.replace(' ', '').contains(tr('app_selection.release.' + suffix).replace(' ', ''))
			}
			free_tree(tree)
			}
		}
	}
}
