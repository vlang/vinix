// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import ui2

// The Wi-Fi, Display and Battery panes in Russian and Spanish, driven by
// injected device readers the way settings_test.v drives them in English.
__global (
	devices_backlight        BacklightState
	devices_backlight_result BacklightResult
	devices_wifi             WifiState
	devices_wifi_result      WifiResult
	devices_battery_percent  int
)

fn devices_read_backlight(mut out BacklightState) BacklightResult {
	if devices_backlight_result == .ok {
		out = devices_backlight
	}
	return devices_backlight_result
}

fn devices_write_backlight(percent int) BacklightResult {
	return .permission
}

fn devices_read_wifi(mut out WifiState) WifiResult {
	if devices_wifi_result == .ok {
		out = devices_wifi
	}
	return devices_wifi_result
}

fn devices_wifi_radio(enabled bool) WifiResult {
	return .ok
}

fn devices_wifi_scan() WifiResult {
	return .ok
}

fn devices_read_battery(force bool) int {
	return devices_battery_percent
}

fn devices_battery_history() BatteryHistory {
	return BatteryHistory{}
}

fn devices_rect() ui2.Rect {
	return ui2.rect(0, 0, 620, 376)
}

// devices_networks is a strong secured network and a hidden open one, then
// enough weaker ones that the list pages at the default window size.
fn devices_networks(count int) WifiState {
	mut state := WifiState{
		driver_state: 3
		radio_on:     true
		writable:     true
		count:        count
	}
	state.networks[0] = WifiNetwork{
		ssid_len: 6
		secure:   true
		channel:  44
		rssi:     -38
	}
	for i, byte in 'Strong'.bytes() {
		state.networks[0].ssid[i] = byte
	}
	state.networks[1] = WifiNetwork{
		ssid_len: 0
		secure:   false
		channel:  6
		rssi:     -70
	}
	for index in 2 .. count {
		state.networks[index] = WifiNetwork{
			ssid_len: 2
			secure:   index % 2 == 0
			channel:  165
			rssi:     -80 - index
		}
		state.networks[index].ssid[0] = `N`
		state.networks[index].ssid[1] = u8(`0` + index)
	}
	return state
}

fn devices_app(category SettingsCategory) &SettingsApp {
	devices_backlight = BacklightState{
		requested_nits: 100
		actual_nits:    99
		min_nits:       2
		max_nits:       400
		online:         true
		writable:       true
	}
	devices_backlight_result = .ok
	devices_wifi = devices_networks(2)
	devices_wifi_result = .ok
	devices_battery_percent = 73
	mut app := &SettingsApp{
		read_state:      devices_read_backlight
		write_percent:   devices_write_backlight
		wifi_read:       devices_read_wifi
		wifi_radio:      devices_wifi_radio
		wifi_scan:       devices_wifi_scan
		battery_read:    devices_read_battery
		battery_history: devices_battery_history
	}
	app.handle('${settings_action_category}${settings_categories.index(category)}') or {
		panic(err)
	}
	return app
}

fn devices_find(root ui2.Element, id string) ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		if found := devices_find_in(child, id) {
			return found
		}
	}
	panic('missing ${id}')
}

fn devices_find_in(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		if found := devices_find_in(child, id) {
			return found
		}
	}
	return none
}

fn devices_texts(el ui2.Element, mut out []string) {
	if el.text.len > 0 {
		out << el.text
	}
	for child in el.children {
		devices_texts(child, mut out)
	}
}

fn devices_build_texts(mut app SettingsApp) []string {
	root := app.build(devices_rect()) or { panic(err) }
	mut texts := []string{}
	devices_texts(root, mut texts)
	return texts
}

fn test_display_pane_follows_the_language_without_a_new_readback() {
	defer {
		set_desktop_language(.en)
	}
	mut app := devices_app(.display)
	set_desktop_language(.ru)
	mut texts := devices_build_texts(mut app)
	for want in ['Дисплей', 'Масштаб', 'Встроенный дисплей',
		'Яркость', 'Обновить', 'Запрошено: 100 нит',
		'Фактически: 99 нит (по данным драйвера)',
		'2–400 нит; при 0% дисплей не выключается.',
		'Яркость считана из /dev/apple-panel-bl.',
		'Нажмите на шкалу, чтобы задать яркость с шагом 5%.'] {
		assert want in texts, want
	}
	assert app.labels_language == .ru
	root := app.build(devices_rect()) or { panic(err) }
	scale := devices_find(root, settings_scale_100_action)
	assert scale.text == '100%' && scale.accessibility_value == 'выбрано'

	set_desktop_language(.es)
	texts = devices_build_texts(mut app)
	assert app.requested_text == 'Solicitado: 100 nits'
	assert app.actual_text == 'Real: 99 nits (según el controlador)'
	assert 'Brillo' in texts && 'Pantalla' in texts && 'Actualizar' in texts

	set_desktop_language(.en)
	devices_build_texts(mut app)
	assert app.requested_text == 'Requested: 100 nits'
	assert app.actual_text == 'Actual: 99 nits (driver report)'
	assert app.range_text == '2 - 400 nits; 0% keeps the display on.'
	assert app.level_text == '${backlight_percent(&app.state)}%'
}

fn test_display_pane_failures_in_russian() {
	defer {
		set_desktop_language(.en)
	}
	mut app := devices_app(.display)
	set_desktop_language(.ru)
	devices_backlight_result = .unavailable
	app.handle('settings.refresh') or { panic(err) }
	texts := devices_build_texts(mut app)
	assert app.level_text == 'Недоступно'
	assert app.requested_text == 'Запрошено: неизвестно'
	assert 'Драйвер яркости недоступен.' in texts
	assert 'Ещё требуется интеграция с бэкендом DCP.' in texts
	devices_backlight_result = .ok
	devices_backlight.requested_nits = -1
	devices_backlight.actual_nits = -1
	app.handle('settings.refresh') or { panic(err) }
	assert app.level_text == 'Неизвестно'
	assert app.requested_text == 'Запрошено: без изменений с загрузки'
	assert app.actual_text == 'Фактически: ожидание данных драйвера'
	app.write_result = .io
	assert app.status_text() == 'Ошибка ввода-вывода яркости. Нажмите «Обновить».'
}

fn test_wifi_pane_follows_the_language_without_a_new_readback() {
	defer {
		set_desktop_language(.en)
	}
	mut app := devices_app(.wifi)
	set_desktop_language(.ru)
	mut root := app.build(devices_rect()) or { panic(err) }
	assert devices_find(root, 'settings.wifi.network.0').text == 'Strong'
	assert devices_find(root, 'settings.wifi.detail.0').text == 'Защищённая  |  кан. 44  |  -38 дБм'
	assert devices_find(root, 'settings.wifi.network.1').text == '<Скрытая сеть>'
	assert devices_find(root, 'settings.wifi.detail.1').text == 'Открытая  |  кан. 6  |  -70 дБм'
	assert devices_find(root, settings_wifi_toggle).text == 'Выключить'
	assert devices_find(root, settings_wifi_scan).text == 'Искать'
	mut texts := []string{}
	devices_texts(root, mut texts)
	assert 'Wi-Fi включён.' in texts && 'Доступные сети' in texts
	assert 'Беспроводной адаптер Broadcom BCM4378' in texts
	assert app.wifi_labels_language == .ru

	set_desktop_language(.es)
	root = app.build(devices_rect()) or { panic(err) }
	assert devices_find(root, 'settings.wifi.network.1').text == '<Red oculta>'
	assert devices_find(root, 'settings.wifi.detail.0').text == 'Protegida  |  canal 44  |  -38 dBm'
	assert devices_find(root, settings_wifi_toggle).text == 'Desactivar'

	set_desktop_language(.en)
	root = app.build(devices_rect()) or { panic(err) }
	assert devices_find(root, 'settings.wifi.network.1').text == '<Hidden network>'
	assert devices_find(root, 'settings.wifi.detail.0').text == 'Secured  |  ch 44  |  -38 dBm'
	assert devices_find(root, 'settings.wifi.detail.1').text == 'Open  |  ch 6  |  -70 dBm'
}

fn test_wifi_status_and_paging_in_russian() {
	defer {
		set_desktop_language(.en)
	}
	mut app := devices_app(.wifi)
	set_desktop_language(.ru)
	devices_wifi = devices_networks(9)
	app.handle(settings_wifi_refresh) or { panic(err) }
	texts := devices_build_texts(mut app)
	assert 'Назад' in texts && 'Далее' in texts
	assert texts.any(it.starts_with('1–') && it.ends_with(' из 9'))
	devices_wifi.scan_error = -5
	app.handle(settings_wifi_refresh) or { panic(err) }
	assert app.wifi_status_text() == 'Последний поиск сетей завершился ошибкой (-5).'
	devices_wifi_result = .unavailable
	app.handle(settings_wifi_refresh) or { panic(err) }
	assert app.wifi_status_text() == 'Устройство Wi-Fi недоступно. Загрузите систему с vinix.apple_wifi=1.'
	set_desktop_language(.es)
	assert app.wifi_status_text() == 'Dispositivo Wi-Fi no disponible. Arranca con vinix.apple_wifi=1.'
}

fn test_battery_estimates_take_each_language_plural() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.ru)
	assert battery_remaining_text(0) == 'Меньше часа'
	assert battery_remaining_text(1) == 'Около 1 часа'
	assert battery_remaining_text(2) == 'Около 2 часов'
	assert battery_remaining_text(5) == 'Около 5 часов'
	assert battery_remaining_text(21) == 'Около 21 часа'
	assert battery_remaining_text(battery_estimate_full) == 'Полностью заряжен'
	assert battery_remaining_text(battery_estimate_charging) == 'Заряжается'
	set_desktop_language(.es)
	assert battery_remaining_text(1) == 'Cerca de 1 hora'
	assert battery_remaining_text(7) == 'Cerca de 7 horas'
	assert battery_remaining_text(battery_estimate_calculating) == 'Calculando…'
	set_desktop_language(.en)
	assert battery_remaining_text(1) == 'About 1 hour'
	assert battery_remaining_text(7) == 'About 7 hours'
	assert battery_remaining_text(48) == 'About 48 hours'
	assert battery_remaining_text(49) == 'Calculating…'
	// Made once and kept: a frame asking again gets the same string back.
	assert battery_remaining_text(7).str == battery_remaining_text(7).str
}

fn test_battery_pane_in_russian_and_spanish() {
	defer {
		set_desktop_language(.en)
	}
	mut history := BatteryHistory{}
	history.observe(0, 80)
	history.observe(300_000, 80)
	history.observe(600_000, 79)
	history.observe(3_900_000, 70)
	set_desktop_language(.ru)
	mut root := ui2.screen(app_surface, battery_settings_elements(70, &history, 16, 455))
	assert devices_find(root, 'settings.battery.title').text == 'Аккумулятор'
	assert devices_find(root, 'settings.battery.estimate').text == 'Около 7 часов'
	mut texts := []string{}
	devices_texts(root, mut texts)
	for want in ['Встроенный аккумулятор', 'Текущий заряд',
		'Оставшееся время', 'Сейчас', '24 часа назад', 'Обновить',
		'Процент заряда по данным драйвера аккумулятора.'] {
		assert want in texts, want
	}
	root = ui2.screen(app_surface, battery_settings_elements(battery_unavailable, &history,
		16, 455))
	assert devices_find(root, 'settings.battery.percent').text == 'Недоступно'
	texts.clear()
	devices_texts(root, mut texts)
	assert 'Драйвер аккумулятора недоступен.' in texts
	assert 'Проверьте диагностику загрузки apple-smc.' in texts
	set_desktop_language(.es)
	root = ui2.screen(app_surface, battery_settings_elements(70, &history, 16, 455))
	assert devices_find(root, 'settings.battery.title').text == 'Batería'
	assert devices_find(root, 'settings.battery.estimate').text == 'Cerca de 7 horas'
}

// devices_assert_fits checks that every label and button in a tree shows its
// whole text in the frame the pane gives it, rather than an ellipsis.
fn devices_assert_fits(desktop &Desktop, el ui2.Element, context string) {
	if el.text.len > 0 && (el.kind == .label || el.kind == .button) {
		face := desktop.face_for(el.text_style)
		width := face.text_width(el.text)
		assert width <= int(el.frame.width), '${context}: «${el.text}» is ${width}px in ${int(el.frame.width)}px'
	}
	for child in el.children {
		devices_assert_fits(desktop, child, context)
	}
}

fn devices_assert_pane_fits(desktop &Desktop, mut app SettingsApp, context string) {
	root := app.build(devices_rect()) or { panic(err) }
	devices_assert_fits(desktop, root, '${desktop_language} ${context}')
}

fn test_every_device_pane_text_fits_its_frame() {
	mut desktop := Desktop{
		canvas: new_canvas(8, 8)
		fonts:  load_fonts()
	}
	defer {
		set_desktop_language(.en)
		unsafe { free(desktop.canvas.pixels) }
	}
	for language in desktop_languages {
		set_desktop_language(language)

		mut display := devices_app(.display)
		devices_assert_pane_fits(&desktop, mut display, 'display')
		for result in [BacklightResult.unavailable, .permission, .offline, .invalid, .io] {
			display.write_result = result
			devices_assert_pane_fits(&desktop, mut display, 'display write ${result}')
		}
		display.write_result = .ok
		devices_backlight.pending = true
		devices_backlight.requested_nits = -1
		devices_backlight.actual_nits = -1
		display.refresh()
		devices_assert_pane_fits(&desktop, mut display, 'display pending')
		devices_backlight.writable = false
		display.refresh()
		devices_assert_pane_fits(&desktop, mut display, 'display read-only')
		devices_backlight_result = .unavailable
		display.refresh()
		devices_assert_pane_fits(&desktop, mut display, 'display unavailable')

		mut wifi := devices_app(.wifi)
		devices_wifi = devices_networks(9)
		wifi.refresh_wifi()
		devices_assert_pane_fits(&desktop, mut wifi, 'wifi paged')
		for result in [WifiResult.unavailable, .permission, .not_ready, .disabled, .invalid, .io] {
			wifi.wifi_action_result = result
			devices_assert_pane_fits(&desktop, mut wifi, 'wifi action ${result}')
		}
		wifi.wifi_action_result = .ok
		for driver_state in 0 .. 7 {
			devices_wifi = devices_networks(0)
			devices_wifi.driver_state = driver_state
			wifi.refresh_wifi()
			devices_assert_pane_fits(&desktop, mut wifi, 'wifi driver ${driver_state}')
		}
		devices_wifi = devices_networks(0)
		devices_wifi.radio_on = false
		devices_wifi.scan_error = -110
		wifi.refresh_wifi()
		devices_assert_pane_fits(&desktop, mut wifi, 'wifi off')
		devices_wifi.radio_on = true
		devices_wifi.scanning = true
		devices_wifi.writable = false
		wifi.refresh_wifi()
		devices_assert_pane_fits(&desktop, mut wifi, 'wifi scanning')
		for result in [WifiResult.unavailable, .permission, .invalid, .io] {
			devices_wifi_result = result
			wifi.refresh_wifi()
			devices_assert_pane_fits(&desktop, mut wifi, 'wifi read ${result}')
		}

		mut battery := devices_app(.battery)
		for percent in [73, battery_unavailable, battery_permission, battery_invalid, battery_io] {
			devices_battery_percent = percent
			devices_assert_pane_fits(&desktop, mut battery, 'battery ${percent}')
		}
		// Every estimate the pane can show, in the estimate's own frame.
		estimate_face := desktop.face_for(ui2.TextStyle{
			size: 19
			bold: true
		})
		for estimate in -4 .. battery_estimate_maximum_hours + 2 {
			text := battery_remaining_text(estimate)
			assert estimate_face.text_width(text) <= (455 - 16) / 2, '${language} «${text}»'
		}
	}
}
