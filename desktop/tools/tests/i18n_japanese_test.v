// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn japanese_has_text(root ui2.Element, text string) bool {
	if root.text == text { return true }
	return root.children.any(japanese_has_text(it, text))
}

fn test_japanese_language_can_be_selected_and_saved() {
	defer { set_desktop_language(.en) }
	set_desktop_language(.en)
	mut desktop := Desktop{}
	mut app := SettingsApp{ desktop: unsafe { &desktop }, category: .language }
	english := app.build(ui2.rect(0, 0, 620, 376))!
	assert japanese_has_text(english, '日本語')
	free_tree(english)
	app.handle('${settings_action_language}${desktop_languages.index(DesktopLanguage.ja)}')!
	assert desktop.settings.language == .ja && desktop_language == .ja
	japanese := app.build(ui2.rect(0, 0, 620, 376))!
	assert japanese_has_text(japanese, 'システム言語')
	for language in desktop_languages {
		assert japanese_has_text(japanese, language.native_name())
	}
	free_tree(japanese)
	encoded := desktop_encode_preferences(DesktopPreferences{ settings: desktop.settings }) or {
		panic('could not encode Japanese preferences')
	}
	defer { unsafe { encoded.free() } }
	assert encoded.contains('language=ja\n')
	loaded := desktop_parse_preferences(encoded) or { panic('could not parse Japanese preferences') }
	assert loaded.settings.language == .ja
}

fn test_japanese_counts_use_the_same_form_for_zero_one_and_many() {
	defer { set_desktop_language(.en) }
	set_desktop_language(.ja)
	for count in [i64(0), 1, 2, 21, 100] {
		assert desktop_plural_index(.ja, count) == 0
		count_text := count.str()
		actual := tr_count('capture.status.frames', count)
		assert actual == '${count_text}フレーム'
		unsafe {
			count_text.free()
			actual.free()
		}
	}
	assert disk_usage_count_text(1234567) == '1,234,567'
	assert disk_usage_size_text(1536) == '1.50 KB'
}

fn test_japanese_dates_and_calendar_use_year_month_day_order() {
	defer { set_desktop_language(.en) }
	set_desktop_language(.ja)
	assert date_long_text(2026, 9, 28, 1) == '2026年9月28日（月曜日）'
	assert files_list_modified_text(0, 0) == '1970年1月01日 00:00'
	assert calendar_first_weekday() == 0
	mut desktop := Desktop{}
	_, short_date := desktop.taskbar_clock_strings_at(i64(1_790_553_600))
	assert short_date == '9月28日（月）'
	mut calendar := CalendarApp{ year: 2026, month: 9, selected_day: 28 }
	tree := calendar.build(ui2.rect(0, 0, 640, 500))!
	defer { free_tree(tree) }
	assert calendar.month_title == '2026年9月'
	assert calendar.selection == '2026年9月28日（月曜日）'
	assert japanese_has_text(tree, '今日')
}

fn test_japanese_apps_retranslate_existing_windows_and_search() {
	defer { set_desktop_language(.en) }
	set_desktop_language(.en)
	mut editor := TextEditorApp{}
	editor.set_path('/root/notes.txt')
	editor.set_file_status('editor.status.saved')
	set_desktop_language(.ja)
	tree := editor.build(ui2.rect(0, 0, 620, 376))!
	defer { free_tree(tree) }
	assert editor_bytes_text(editor.status).contains('/root/notes.txt')
	assert editor_bytes_text(editor.status) != 'Saved /root/notes.txt'
	assert app_title_text('Files') == 'ファイル'
	assert app_title_text('Calculator') == '電卓'
	assert app_title_text('Firefox') == 'Firefox'
	assert app_matches('Calculator', '電卓') && app_matches('Calculator', 'calc')
	assert files_list_kind_text('folder', true) == 'フォルダ'
	assert files_list_kind_text('image.png', false) == 'PNG画像'
}
