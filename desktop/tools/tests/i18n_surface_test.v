// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The notification area, the desktop's context menus and DiskUsage in Russian
// and Spanish.
module main

import ui2

fn i18n_surface_has_text(el ui2.Element, text string) bool {
	if el.text == text {
		return true
	}
	for child in el.children {
		if i18n_surface_has_text(child, text) {
			return true
		}
	}
	return false
}

fn i18n_surface_sample(networks int) TraySample {
	return TraySample{
		ethernet:      .connected
		address:       0x0f02000a
		wifi_present:  true
		wifi_radio:    true
		wifi_networks: networks
		battery:       37
		charging:      true
	}
}

fn test_tray_text_follows_the_language_without_a_new_sample() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	mut d := Desktop{}
	d.tray.preferences_loaded = true
	d.apply_tray_sample(i18n_surface_sample(3))
	assert d.tray.network_tip == 'Ethernet: 10.0.2.15'
	assert d.tray.battery_tip == 'Battery: 37%, charging'
	assert d.tray.wifi_line == 'Wi-Fi: on, 3 networks nearby'
	assert d.tray.address_line == 'IPv4 address 10.0.2.15'
	assert d.tooltip_text(action_show_desktop) == 'Show desktop'

	// The retained text is reworded on the next poll, well before the devices
	// are due to be read again.
	set_desktop_language(.ru)
	d.tray.sampled_ms = monotonic_millis()
	d.update_tray_at(d.tray.sampled_ms, false)
	assert d.tray.language == .ru
	assert d.tray.battery_tip == 'Аккумулятор: 37%, заряжается'
	assert d.tray.wifi_line == 'Wi-Fi: включён, рядом 3 сети'
	assert d.tray.address_line == 'IPv4-адрес 10.0.2.15'
	assert d.tray.ethernet_line == 'Ethernet: подключено'
	assert d.tooltip_text(action_show_desktop) == 'Показать рабочий стол'
	assert d.tooltip_text(action_tray_overflow) == 'Показать скрытые значки'
	assert d.tooltip_text('tray.icon.capture') == 'Захват экрана'

	// An unchanged sample in another language is not skipped.
	set_desktop_language(.es)
	d.apply_tray_sample(i18n_surface_sample(3))
	assert d.tray.battery_tip == 'Batería: 37%, cargando'
	assert d.tray.wifi_line == 'Wi-Fi: activado, 3 redes cercanas'
	assert d.tooltip_text('tray.icon.battery') == 'Batería: 37%, cargando'
}

fn test_tray_wifi_counts_take_each_languages_plural() {
	defer {
		set_desktop_language(.en)
	}
	mut d := Desktop{}
	d.tray.preferences_loaded = true
	set_desktop_language(.en)
	d.apply_tray_sample(i18n_surface_sample(1))
	assert d.tray.wifi_line == 'Wi-Fi: on, 1 network nearby'
	set_desktop_language(.ru)
	for count, want in {
		1:  'Wi-Fi: включён, рядом 1 сеть'
		4:  'Wi-Fi: включён, рядом 4 сети'
		5:  'Wi-Fi: включён, рядом 5 сетей'
		21: 'Wi-Fi: включён, рядом 21 сеть'
	} {
		d.apply_tray_sample(i18n_surface_sample(count))
		assert d.tray.wifi_line == want
	}
	set_desktop_language(.es)
	d.apply_tray_sample(i18n_surface_sample(1))
	assert d.tray.wifi_line == 'Wi-Fi: activado, 1 red cercana'
	d.apply_tray_sample(TraySample{
		ethernet:          .absent
		backlight_present: true
		backlight_percent: 40
	})
	assert d.tray.network_tip == 'Sin conexión'
	assert d.tray.display_tip == 'Brillo: 40%'
	assert d.tray.display_line == 'Brillo 40%'
}

fn test_context_menu_rows_are_worded_when_drawn() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	assert context_entry_title(create_context_background_entries[0]) == 'New Folder'
	assert context_entry_title(create_context_files_item_entries[4]) == 'Tags…'
	assert context_entry_title(tray_context_hide_entries[0]) == 'Hide in overflow'
	set_desktop_language(.ru)
	assert context_entry_title(create_context_background_entries[0]) == 'Новая папка'
	assert context_entry_title(create_context_item_entries[0]) == 'Переименовать'
	assert context_entry_title(tray_context_show_entries[0]) == 'Показать значок'
	set_desktop_language(.es)
	assert context_entry_title(create_context_background_entries[1]) == 'Nuevo archivo'
	assert context_entry_title(create_context_item_entries[4]) == 'Mover a la Papelera'
	// A row built elsewhere keeps the words it was given.
	assert context_entry_title(ui2.MenuEntry{ id: start_context_open, title: 'Open' }) == 'Open'
}

fn test_disk_usage_formats_numbers_the_way_each_language_writes_them() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.ru)
	assert disk_usage_size_text(1023) == '1023 Б'
	assert disk_usage_size_text(1536) == '1,50 КБ'
	assert disk_usage_size_text(10 * 1024) == '10,0 КБ'
	assert disk_usage_size_text(100 * 1024) == '100 КБ'
	assert disk_usage_size_text(u64(3) * 1024 * 1024 * 1024) == '3,00 ГБ'
	assert disk_usage_count_text(1234567) == '1 234 567'
	assert disk_usage_duration_text(940) == '940 мс'
	assert disk_usage_duration_text(1500) == '1,5 с'
	assert disk_usage_duration_text(65000) == '1 мин 5 с'
	set_desktop_language(.es)
	assert disk_usage_size_text(1536) == '1,50 KB'
	assert disk_usage_count_text(1234567) == '1.234.567'
	assert disk_usage_duration_text(1500) == '1,5 s'
	set_desktop_language(.fr)
	assert disk_usage_size_text(1023) == '1023 o'
	assert disk_usage_size_text(1536) == '1,50 Ko'
	assert disk_usage_size_text(u64(3) * 1024 * 1024 * 1024) == '3,00 Go'
	assert disk_usage_count_text(1234567) == '1 234 567'
	assert disk_usage_duration_text(1500) == '1,5 s'
	set_desktop_language(.en)
	assert disk_usage_size_text(1536) == '1.50 KB'
	assert disk_usage_count_text(1234567) == '1,234,567'
}

fn test_disk_usage_status_counts_skipped_items_in_each_language() {
	defer {
		set_desktop_language(.en)
	}
	mut app := DiskUsageApp{}
	app.scanner.phase = .complete
	app.scanner.elapsed_ms = 1500
	app.scanner.unreadable = 1
	set_desktop_language(.en)
	assert app.status_text() == 'Scanned / in 1.5 sec. 1 protected or unreadable item was skipped.'
	app.scanner.unreadable = 3
	assert app.status_text() == 'Scanned / in 1.5 sec. 3 protected or unreadable items were skipped.'
	set_desktop_language(.ru)
	assert app.status_text() == 'Папка / просканирована за 1,5 с. Пропущено 3 защищённых или недоступных объекта.'
	app.scanner.unreadable = 1001
	assert app.status_text() == 'Папка / просканирована за 1,5 с. Пропущен 1 001 защищённый или недоступный объект.'
	set_desktop_language(.es)
	assert app.status_text() == 'Se analizó / en 1,5 s. Se omitieron 1.001 elementos protegidos o ilegibles.'
	app.scanner.unreadable = 0
	assert app.status_text() == 'Se analizó / en 1,5 s.'
}

fn test_disk_usage_rewords_a_failed_scan_after_the_language_changes() {
	defer {
		set_desktop_language(.en)
	}
	set_desktop_language(.en)
	mut app := DiskUsageApp{}
	defer {
		app.close_app()
	}
	app.scan('/vinix-disk-usage-does-not-exist')
	assert app.scanner.error == 'cannot open /vinix-disk-usage-does-not-exist'
	set_desktop_language(.ru)
	tree := app.build(ui2.rect(0, 0, 880, 546)) or { panic(err) }
	assert app.scanner.error == 'Не удалось открыть /vinix-disk-usage-does-not-exist'
	assert i18n_surface_has_text(tree, 'НЕДОСТУПНО')
	assert i18n_surface_has_text(tree, 'Не удалось открыть /vinix-disk-usage-does-not-exist')
	assert i18n_surface_has_text(tree, 'Самые большие папки')
	assert i18n_surface_has_text(tree, 'Весь диск')
	assert i18n_surface_has_text(tree, 'пока пусто')
	assert i18n_surface_has_text(tree, '0 Б')
	set_desktop_language(.es)
	spanish := app.build(ui2.rect(0, 0, 880, 546)) or { panic(err) }
	assert i18n_surface_has_text(spanish, 'No se puede abrir /vinix-disk-usage-does-not-exist')
	assert i18n_surface_has_text(spanish, 'SIN ACCESO')
}
