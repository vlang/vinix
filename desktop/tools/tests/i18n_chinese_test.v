// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn chinese_has_text(root ui2.Element, text string) bool {
	if root.text == text {
		return true
	}
	return root.children.any(chinese_has_text(it, text))
}

fn test_chinese_language_picker_switches_and_preserves_native_names() {
	defer { set_desktop_language(.en) }
	mut desktop := Desktop{}
	mut app := SettingsApp{ desktop: &desktop, category: .language }
	begin_frame_elements()
	english := app.build(ui2.rect(0, 0, 620, 376))!
	assert chinese_has_text(english, '中文（简体）')
	free_tree(english)
	app.handle('${settings_action_language}${desktop_languages.index(DesktopLanguage.zh)}')!
	assert desktop.settings.language == .zh
	assert desktop_language == .zh
	begin_frame_elements()
	chinese := app.build(ui2.rect(0, 0, 620, 376))!
	assert chinese_has_text(chinese, '系统语言')
	for language in desktop_languages {
		assert chinese_has_text(chinese, language.native_name())
	}
	free_tree(chinese)
	app.handle('${settings_action_language}${desktop_languages.len}')!
	assert desktop.settings.language == .zh
}

fn test_chinese_counts_use_the_single_translated_form() {
	defer { set_desktop_language(.en) }
	set_desktop_language(.zh)
	for count in [i64(-21), 0, 1, 2, 5, 11, 21, 100, 101, 1_000_000] {
		assert desktop_plural_index(.zh, count) == 0
		text := tr_count('capture.status.frames', count)
		assert text == '${count} 帧'
		unsafe { text.free() }
	}
	text := tr_fill3('activity.summary', '2', '64 MB', '256 MB')
	assert text == '2 个进程   已使用 64 MB，共 256 MB'
	unsafe { text.free() }
	assert tr_plural_form('app.files', 2) == '文件'
}

fn test_chinese_dates_follow_year_month_day_order_and_monday_weeks() {
	defer { set_desktop_language(.en) }
	set_desktop_language(.zh)
	assert date_long_text(2026, 9, 28, 1) == '2026年9月28日 星期一'
	assert calendar_first_weekday() == 1
	mut calendar := CalendarApp{ year: 2026, month: 9, selected_day: 28 }
	calendar.refresh_labels()
	assert calendar.month_title == '2026年9月'
	assert calendar.selection == '2026年9月28日 星期一'
	mut desktop := Desktop{}
	_, date := desktop.taskbar_clock_strings_at(1_790_553_600)
	assert date == '9月28日 周一'
	assert disk_usage_count_text(1_234_567) == '1,234,567'
}

fn test_chinese_settings_and_program_search_accept_utf8() {
	defer { set_desktop_language(.en) }
	set_desktop_language(.zh)
	assert app_title_text('Files') == '文件'
	assert app_title_text('Activity Monitor') == '活动监视器'
	assert app_matches('Calculator', '计算')
	assert app_matches('Calculator', 'calc')
	assert !app_matches('Calculator', '日历')
	mut app := &SettingsApp{}
	defer {
		app.close_app()
		unsafe { free(app) }
	}
	app.key_input('\x06')
	// A three-byte rune can arrive one byte at a time from the console.
	word := '亮度'
	for index in 0 .. word.len {
		app.key_input(console_borrow(word, index, index + 1))
	}
	assert editor_bytes_text(app.search) == '亮度'
	assert app.search_count > 0
	mut found := false
	for index in 0 .. app.search_count {
		if settings_search_entries[app.search_results[index]].title == 'settings.display.brightness' {
			found = true
		}
	}
	assert found
	set_desktop_language(.en)
	app.key_input('\x06')
	app.paste_input('中文')
	assert app.search_count > 0
}

fn test_chinese_preference_and_application_launch_round_trip() {
	parsed := desktop_parse_preferences('version=1\nlanguage=zh\n') or { panic('Chinese rejected') }
	assert parsed.settings.language == .zh
	options := app_process_options(['--vinix-app=vinix-settings', '--request-fd=3',
		'--response-fd=4', '--app-lang=zh']) or { panic('Chinese app launch rejected') }
	assert options.language == .zh
	assert DesktopLanguage.zh.code() == 'zh'
}

fn test_fonts_render_the_chinese_language_name_at_both_scales() {
	mut fonts := load_fonts()
	defer { free_fonts(mut fonts) }
	for face in fonts {
		for r in DesktopLanguage.zh.native_name().runes() {
			glyph := face.glyph_for(u32(r))
			assert glyph.width > 0 && glyph.height > 0
			assert glyph.advance > 0
			assert glyph.bearing_y >= 0
		}
	}
}
