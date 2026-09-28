// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

// 1970-01-01 13:05:09 UTC, a Thursday.
const i18n_time_thursday = i64(47_109)
// 2026-09-28 00:00:00 UTC, a Monday.
const i18n_time_monday = i64(1_790_553_600)

fn i18n_time_texts(el ui2.Element, mut out []string) {
	if el.text.len > 0 {
		out << el.text
	}
	for child in el.children {
		i18n_time_texts(child, mut out)
	}
}

fn i18n_time_element(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		found := i18n_time_element(child, id) or { continue }
		return found
	}
	return none
}

fn test_taskbar_clock_in_russian_and_spanish() {
	defer {
		set_desktop_language(.en)
	}
	mut desktop := Desktop{}
	set_desktop_language(.en)
	_, english := desktop.taskbar_clock_strings_at(i18n_time_monday)
	assert english == 'Mon 28 Sep'

	set_desktop_language(.ru)
	time_24, date_24 := desktop.taskbar_clock_strings_at(i18n_time_thursday)
	assert time_24 == '13:05:09'
	assert date_24 == 'чт 1 янв.'
	_, monday := desktop.taskbar_clock_strings_at(i18n_time_monday)
	assert monday == 'пн 28 сент.'
	desktop.settings.clock_24_hour = false
	time_12, _ := desktop.taskbar_clock_strings_at(i18n_time_thursday)
	assert time_12 == '1:05:09 PM'
	midnight, _ := desktop.taskbar_clock_strings_at(0)
	assert midnight == '12:00:00 AM'
	desktop.settings.clock_show_weekday = false
	_, date_only := desktop.taskbar_clock_strings_at(i18n_time_thursday)
	assert date_only == '1 янв.'
	desktop.settings.clock_show_date = false
	desktop.settings.clock_show_weekday = true
	_, weekday_only := desktop.taskbar_clock_strings_at(i18n_time_thursday)
	assert weekday_only == 'чт'
	_, unavailable := desktop.taskbar_clock_strings_at(-1)
	assert unavailable == 'Часы недоступны'

	set_desktop_language(.es)
	desktop.settings.clock_show_date = true
	_, spanish := desktop.taskbar_clock_strings_at(i18n_time_monday)
	assert spanish == 'lun 28 sept'
	afternoon, _ := desktop.taskbar_clock_strings_at(i18n_time_thursday)
	assert afternoon == '1:05:09 p. m.'
	morning, _ := desktop.taskbar_clock_strings_at(0)
	assert morning == '12:00:00 a. m.'
	desktop.settings.clock_show_seconds = false
	short, _ := desktop.taskbar_clock_strings_at(i18n_time_thursday)
	assert short == '1:05 p. m.'
}

fn test_taskbar_build_stamp_follows_the_language() {
	defer {
		set_desktop_language(.en)
	}
	mut desktop := Desktop{}
	set_desktop_language(.ru)
	build_time, build_date := desktop.taskbar_build_strings_at(i18n_time_thursday, false)
	assert build_time == 'Сборка 13:05'
	assert build_date == '01 янв.'
	missing_time, missing_date := desktop.taskbar_build_strings_at(0, false)
	assert missing_time == 'Сборка --:--'
	assert missing_date == 'Дата недоступна'
	set_desktop_language(.es)
	gpu_time, gpu_date := desktop.taskbar_build_strings_at(i18n_time_thursday, true)
	assert gpu_time == 'Compilado 13:05'
	assert gpu_date == '01 ene gpu+'
}

fn test_a_language_change_reformats_the_taskbar_clock() {
	defer {
		set_desktop_language(.en)
	}
	mut desktop := Desktop{}
	set_desktop_language(.en)
	desktop.update_taskbar_clock_at(i18n_time_monday)
	assert desktop.taskbar_clock_date == 'Mon 28 Sep'
	assert desktop.taskbar_build_time.starts_with('Built ')
	desktop.settings.language = .ru
	desktop.language_changed()
	desktop.update_taskbar_clock_at(i18n_time_monday)
	assert desktop.taskbar_clock_date == 'пн 28 сент.'
	assert desktop.taskbar_build_time.starts_with('Сборка ')
}

fn test_long_dates_use_each_languages_grammar() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	assert date_long_text(2026, 9, 28, 1) == 'Mon, Sep 28, 2026'
	set_desktop_language(.ru)
	assert date_long_text(2026, 9, 28, 1) == 'понедельник, 28 сентября 2026 г.'
	// The genitive after a day number, the nominative in a heading.
	assert date_long_text(2026, 5, 1, 5) == 'пятница, 1 мая 2026 г.'
	assert calendar_heading_month(5) == 'Май'
	assert date_month_short(5) == 'мая'
	set_desktop_language(.es)
	assert date_long_text(2026, 9, 28, 1) == 'lunes, 28 de septiembre de 2026'
	assert date_long_text(2026, 3, 4, 3) == 'miércoles, 4 de marzo de 2026'
}

fn test_calendar_retranslates_and_starts_the_week_on_monday() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	size := ui2.rect(0, 0, 640, 500)
	inner := 640 - 2 * calendar_padding
	cell_width := inner / 7
	mut calendar := CalendarApp{
		year:         2026
		month:        9
		selected_day: 28
	}
	calendar.refresh_labels()
	assert calendar.month_title == 'Sep 2026'
	assert calendar.selection == 'Mon, Sep 28, 2026'
	english := calendar.build(size)!
	mut texts := []string{}
	i18n_time_texts(english, mut texts)
	// The previous button, the heading and the next button, then the week.
	assert texts[3] == 'Sun' && texts[4] == 'Mon' && texts[9] == 'Sat'
	assert 'Today' in texts
	// 1 September 2026 is a Tuesday: the third column from Sunday.
	first := i18n_time_element(english, 'calendar.day.1') or { panic('missing day 1') }
	assert int(first.frame.x) == calendar_padding + 2 * cell_width + 2
	free_tree(english)

	set_desktop_language(.ru)
	russian := calendar.build(size)!
	assert calendar.month_title == 'Сентябрь 2026'
	assert calendar.selection == 'понедельник, 28 сентября 2026 г.'
	texts.clear()
	i18n_time_texts(russian, mut texts)
	assert 'Сегодня' in texts
	// The week runs from Monday to Sunday.
	assert texts[3] == 'пн' && texts[4] == 'вт' && texts[8] == 'сб' && texts[9] == 'вс'
	tuesday := i18n_time_element(russian, 'calendar.day.1') or { panic('missing day 1') }
	assert int(tuesday.frame.x) == calendar_padding + cell_width + 2
	monday := i18n_time_element(russian, 'calendar.day.28') or { panic('missing day 28') }
	assert int(monday.frame.x) == calendar_padding + 2
	free_tree(russian)

	// March 2026 begins on a Sunday, the last column of a Monday week, and its
	// 31st day still falls inside the six rows.
	calendar.handle('calendar.previous')!
	for calendar.month != 3 {
		calendar.handle('calendar.previous')!
	}
	march := calendar.build(size)!
	sunday := i18n_time_element(march, 'calendar.day.1') or { panic('missing day 1') }
	assert int(sunday.frame.x) == calendar_padding + 6 * cell_width + 2
	last := i18n_time_element(march, 'calendar.day.31') or { panic('missing day 31') }
	assert int(last.frame.x) == calendar_padding + 1 * cell_width + 2
	footer_y := 500 - calendar_footer_height
	assert int(last.frame.y + last.frame.height) <= footer_y
	free_tree(march)

	set_desktop_language(.es)
	spanish := calendar.build(size)!
	assert calendar.month_title == 'marzo de 2026'
	texts.clear()
	i18n_time_texts(spanish, mut texts)
	assert 'Hoy' in texts
	assert texts[1] == 'marzo de 2026'
	assert texts[3] == 'lun' && texts[5] == 'mié' && texts[9] == 'dom'
	free_tree(spanish)
}

fn test_clock_app_retranslates_its_labels() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	mut clock := ClockApp{}
	clock.refresh()
	english := clock.build(ui2.rect(0, 0, 560, 410))!
	mut texts := []string{}
	i18n_time_texts(english, mut texts)
	assert 'STOPWATCH' in texts && 'Start' in texts && 'Reset' in texts
	free_tree(english)
	english_date := clock.date_text.clone()

	set_desktop_language(.ru)
	russian := clock.build(ui2.rect(0, 0, 560, 410))!
	texts.clear()
	i18n_time_texts(russian, mut texts)
	assert 'СЕКУНДОМЕР' in texts && 'Старт' in texts && 'Сброс' in texts
	assert clock.date_text != english_date
	assert clock.date_text.ends_with(' г.') || clock.date_text == 'Часы недоступны'
	free_tree(russian)

	set_desktop_language(.es)
	clock.toggle_stopwatch()
	spanish := clock.build(ui2.rect(0, 0, 560, 410))!
	texts.clear()
	i18n_time_texts(spanish, mut texts)
	assert 'CRONÓMETRO' in texts && 'Detener' in texts && 'Restablecer' in texts
	free_tree(spanish)
}

fn i18n_time_record(pid int, name string, memory u64, cpu_ns u64) ActivitySample {
	mut record := ActivitySample{
		pid:          i32(pid)
		memory_bytes: memory
		cpu_time_ns:  cpu_ns
	}
	for index := 0; index < name.len && index < activity_name_len - 1; index++ {
		record.name[index] = name[index]
	}
	return record
}

fn test_activity_monitor_follows_the_language() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	mut app := ActivityApp{}
	mut header := ActivityTable{
		total:        3
		total_memory: 256 * 1024 * 1024
		free_memory:  192 * 1024 * 1024
		sample_ns:    1_000_000_000
	}
	mut records := [
		i18n_time_record(7, '/usr/bin/vinix-activity[7]', 1_500_000, 0),
		i18n_time_record(8, '/usr/bin/vinix-files[8]', 12_000_000, 0),
		i18n_time_record(9, '', 1_000_000, 0),
	]
	app.monitor.apply_snapshot(&header, unsafe { &records[0] }, records.len)
	header.sample_ns += 1_000_000_000
	records[0].cpu_time_ns += 125_000_000
	app.monitor.apply_snapshot(&header, unsafe { &records[0] }, records.len)
	assert app.monitor.summary == '3 processes   64 MB of 256 MB used'
	assert app.monitor.rows[0].name == 'Activity Monitor'
	assert app.monitor.rows[0].cpu_text == '12.5'
	assert app.monitor.rows[0].mem_text == '1.5 MB'

	set_desktop_language(.ru)
	russian := app.build(ui2.rect(0, 0, 520, 400))!
	mut texts := []string{}
	i18n_time_texts(russian, mut texts)
	// The names stay English underneath and read in Russian on screen.
	assert app.monitor.rows[0].name == 'Activity Monitor'
	assert 'Мониторинг системы' in texts && 'Файлы' in texts && '(без имени)' in texts
	assert 'ЦП' in texts && 'Память' in texts && 'Имя' in texts
	assert '% ЦП' in texts && 'МБ' in texts && 'PID' in texts
	assert '12,5' in texts && '1,5 МБ' in texts && '12 МБ' in texts
	assert app.monitor.summary.starts_with('3 процесса   занято ')
	assert app.monitor.summary.contains(' из ')
	free_tree(russian)

	for count, expected in {
		u32(1): '1 процесс '
		5:      '5 процессов '
		21:     '21 процесс '
		22:     '22 процесса '
	} {
		app.monitor.process_total = count
		app.monitor.update_summary()
		assert app.monitor.summary.starts_with(expected + '  занято ')
	}

	// Sorting by name follows the names as they read.
	app.handle(activity_action_name)!
	assert activity_display_name(app.monitor.rows[0].name) == '(без имени)'
	assert activity_display_name(app.monitor.rows[1].name) == 'Мониторинг системы'

	set_desktop_language(.es)
	spanish := app.build(ui2.rect(0, 0, 520, 400))!
	texts.clear()
	i18n_time_texts(spanish, mut texts)
	assert 'Nombre' in texts && 'Memoria' in texts && '(sin nombre)' in texts
	assert '1,5 MB' in texts
	assert app.monitor.summary.starts_with('22 procesos   ')
	assert app.monitor.summary.contains(' en uso')
	free_tree(spanish)

	set_desktop_language(.en)
	english := app.build(ui2.rect(0, 0, 520, 400))!
	busiest := app.monitor.rows[app.monitor.process_row_index(7)]
	assert busiest.cpu_text == '12.5'
	assert busiest.mem_text == '1.5 MB'
	assert app.monitor.summary == '22 processes   64 MB of 256 MB used'
	free_tree(english)
	app.monitor.free_rows()
}

fn test_activity_errors_are_read_again_in_the_new_language() {
	defer {
		set_desktop_language(.en)
	}
	// The host has no /dev/processes, which is the error this reads.
	set_desktop_language(.ru)
	mut app := ActivityApp{}
	app.monitor.buffer = []u8{len: activity_buffer_size()}
	app.monitor.sample()
	assert app.monitor.error == '/dev/processes отсутствует.\nЭто ядро не сообщает о процессах.'
	set_desktop_language(.es)
	tree := app.build(ui2.rect(0, 0, 520, 400))!
	assert app.monitor.error == '/dev/processes no existe.\nEste núcleo no informa de los procesos.'
	free_tree(tree)
	set_desktop_language(.en)
	english := app.build(ui2.rect(0, 0, 520, 400))!
	assert app.monitor.error == '/dev/processes is not there.\nThis kernel does not report processes.'
	free_tree(english)
}
