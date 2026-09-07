// SPDX-License-Identifier: GPL-2.0-or-later
// Wi-Fi Settings pane over the bounded /dev/wlan0 ioctl interface.
module main

import ui2

const settings_wifi_toggle = 'settings.wifi.toggle'
const settings_wifi_scan = 'settings.wifi.scan'
const settings_wifi_refresh = 'settings.wifi.refresh'
const settings_wifi_previous = 'settings.wifi.previous'
const settings_wifi_next = 'settings.wifi.next'
// Move one row at a time so resized panes with a different row capacity never
// skip an entry between pages.
const settings_wifi_page_size = 1

fn wifi_same_network(a &WifiNetwork, b &WifiNetwork) bool {
	if a.ssid_len != b.ssid_len || a.secure != b.secure || a.channel != b.channel
		|| a.rssi != b.rssi {
		return false
	}
	for i in 0 .. 32 {
		if a.ssid[i] != b.ssid[i] {
			return false
		}
	}
	return true
}

fn wifi_same_state(a &WifiState, b &WifiState) bool {
	if a.driver_state != b.driver_state || a.driver_error != b.driver_error
		|| a.radio_on != b.radio_on || a.scanning != b.scanning
		|| a.scan_error != b.scan_error || a.writable != b.writable || a.count != b.count {
		return false
	}
	for i in 0 .. a.count {
		if !wifi_same_network(&a.networks[i], &b.networks[i]) {
			return false
		}
	}
	return true
}

fn wifi_network_name(network &WifiNetwork) string {
	if network.ssid_len == 0 {
		return '<Hidden network>'.clone()
	}
	mut printable := []u8{cap: network.ssid_len}
	for i in 0 .. network.ssid_len {
		byte := network.ssid[i]
		printable << if byte >= 32 && byte <= 126 { byte } else { `?` }
	}
	return printable.bytestr()
}

fn wifi_network_detail(network &WifiNetwork) string {
	security := if network.secure { 'Secured' } else { 'Open' }
	return '${security}  |  ch ${network.channel}  |  ${network.rssi} dBm'
}

fn sort_wifi_networks(mut state WifiState) {
	// Strongest first makes a rescan stable and useful even when access points
	// report in a different order.
	for i in 0 .. state.count {
		for j in i + 1 .. state.count {
			if state.networks[j].rssi > state.networks[i].rssi {
				tmp := state.networks[i]
				state.networks[i] = state.networks[j]
				state.networks[j] = tmp
			}
		}
	}
}

fn (mut a SettingsApp) replace_wifi_labels() {
	for i in 0 .. a.wifi_state.count {
		a.wifi_names[i] = wifi_network_name(&a.wifi_state.networks[i])
		a.wifi_details[i] = wifi_network_detail(&a.wifi_state.networks[i])
	}
}

fn (mut a SettingsApp) refresh_wifi() {
	mut next := WifiState{}
	result := a.wifi_read(mut next)
	if result == .ok {
		sort_wifi_networks(mut next)
	}
	a.wifi_last_poll_ms = desktop_monotonic_ms()
	if a.wifi_initialized && result == a.wifi_read_result && wifi_same_state(&a.wifi_state, &next) {
		return
	}
	old_count := a.wifi_state.count
	if a.wifi_initialized {
		for i in 0 .. old_count {
			unsafe {
				a.wifi_names[i].free()
				a.wifi_details[i].free()
			}
		}
	}
	a.wifi_initialized = true
	a.wifi_read_result = result
	a.wifi_state = next
	if a.wifi_offset >= a.wifi_state.count {
		a.wifi_offset = if a.wifi_state.count > 0 { a.wifi_state.count - 1 } else { 0 }
	}
	// Clear the slots whose old strings were released before assigning fresh
	// cached labels for this snapshot.
	for i in 0 .. a.wifi_state.count {
		a.wifi_names[i] = ''
		a.wifi_details[i] = ''
	}
	if result == .ok {
		a.replace_wifi_labels()
	}
}

fn wifi_result_text(result WifiResult) string {
	return match result {
		.unavailable { 'Wi-Fi device not available. Boot with vinix.apple_wifi=1.' }
		.permission { 'Permission denied. Wi-Fi controls require write access.' }
		.not_ready { 'Load the matching BCM4378 firmware before turning Wi-Fi on.' }
		.disabled { 'Turn Wi-Fi on before scanning.' }
		.invalid { 'Invalid Wi-Fi driver response.' }
		.io { 'Wi-Fi I/O failed. Refresh to try again.' }
		else { '' }
	}
}

fn (a &SettingsApp) wifi_status_text() string {
	if a.wifi_read_result != .ok {
		return wifi_result_text(a.wifi_read_result)
	}
	if a.wifi_action_result != .ok {
		return wifi_result_text(a.wifi_action_result)
	}
	if a.wifi_state.driver_state >= 3 && !a.wifi_state.writable {
		return 'Read-only access; Wi-Fi controls are disabled.'
	}
	if a.wifi_state.scan_error != 0 {
		return 'The last network scan failed (${a.wifi_state.scan_error}).'
	}
	return match a.wifi_state.driver_state {
		0 { 'Wi-Fi hardware is off.' }
		1 { 'BCM4378 detected; load its matching firmware with wifi-ctl.' }
		2 { 'Wi-Fi firmware is starting.' }
		3 {
			if a.wifi_state.radio_on { 'Wi-Fi is on.' } else { 'Wi-Fi is off.' }
		}
		4 { 'Connecting to a Wi-Fi network...' }
		5 { 'Wi-Fi link authenticated.' }
		else { 'Wi-Fi stopped after a driver error (${a.wifi_state.driver_error}).' }
	}
}

fn (a &SettingsApp) wifi_can_toggle() bool {
	return a.wifi_read_result == .ok && a.wifi_state.writable && a.wifi_state.driver_state >= 3
		&& a.wifi_state.driver_state <= 5
}

fn (a &SettingsApp) wifi_can_scan() bool {
	return a.wifi_can_toggle() && a.wifi_state.radio_on && !a.wifi_state.scanning
		&& a.wifi_state.driver_state != 4
}

fn (a &SettingsApp) wifi_pane(width int, height int) []ui2.Element {
	x := settings_padding
	inner := width - 2 * settings_padding
	if inner < 300 || height < 266 {
		return [
			settings_label('Enlarge Settings to show its controls.', x, settings_padding, if inner > 0 {
				inner
			} else {
				1
			}, body_text),
		]
	}
	mut out := [
		ui2.label('', 'Wi-Fi', ui2.rect(f64(x), 16, f64(inner), 28), ui2.TextStyle{
			color: body_heading
			size: 20
			bold: true
		}),
		settings_label('Broadcom BCM4378 wireless', x, 46, inner, body_muted),
		ui2.view('', ui2.rect(f64(x), 76, f64(inner), 1), ui2.BoxStyle{ bg: body_rule }, []),
		settings_label('Wi-Fi', x, 92, inner - 100, body_heading),
		settings_button(settings_wifi_toggle, if a.wifi_state.radio_on {
			'Turn off'
		} else {
			'Turn on'
		}, ui2.rect(f64(x + inner - 86), 86, 86, 30), a.wifi_can_toggle()),
		settings_label(a.wifi_status_text(), x, 126, inner, if a.wifi_read_result != .ok
			|| a.wifi_action_result != .ok || a.wifi_state.scan_error != 0 {
			files_error
		} else {
			body_muted
		}),
		settings_label('Available networks', x, 164, inner - 180, body_heading),
		settings_button(settings_wifi_refresh, 'Refresh', ui2.rect(f64(x + inner - 158), 158, 72, 30), true),
		settings_button(settings_wifi_scan, if a.wifi_state.scanning {
			'Scanning...'
		} else {
			'Scan'
		}, ui2.rect(f64(x + inner - 80), 158, 80, 30), a.wifi_can_scan()),
	]
	if a.wifi_read_result != .ok || a.wifi_state.count == 0 {
		message := if a.wifi_read_result != .ok {
			'Network scanning is unavailable until the Wi-Fi device is present.'
		} else if a.wifi_state.driver_state < 3 {
			'Load the matching Wi-Fi firmware to scan for networks.'
		} else if a.wifi_state.driver_state > 5 {
			'Wi-Fi stopped after a driver error; reboot to retry.'
		} else if a.wifi_state.scanning {
			'Searching for wireless networks...'
		} else if !a.wifi_state.radio_on {
			'Turn Wi-Fi on to scan for networks.'
		} else {
			'No wireless networks found. Select Scan to search.'
		}
		out << settings_label(message, x, 204, inner, body_muted)
		return out
	}
	mut row_capacity := (height - 204) / 28
	if row_capacity < 0 {
		row_capacity = 0
	}
	paged := a.wifi_state.count > row_capacity
	if paged {
		row_capacity = (height - 238) / 28
		if row_capacity < 1 {
			row_capacity = 1
		}
	}
	mut offset := a.wifi_offset
	max_offset := if a.wifi_state.count > row_capacity {
		a.wifi_state.count - row_capacity
	} else {
		0
	}
	if offset > max_offset {
		offset = max_offset
	}
	mut shown := row_capacity
	if shown > a.wifi_state.count - offset {
		shown = a.wifi_state.count - offset
	}
	for i in 0 .. shown {
		y := 202 + i * 28
		index := offset + i
		out << ui2.view('', ui2.rect(f64(x), f64(y), f64(inner), 1), ui2.BoxStyle{ bg: body_rule }, [])
		out << ui2.label('settings.wifi.network.${index}', a.wifi_names[index], ui2.rect(f64(x), f64(y + 4), f64(inner - 205), 22), ui2.TextStyle{ color: body_text, size: 13 })
		out << ui2.label('settings.wifi.detail.${index}', a.wifi_details[index], ui2.rect(f64(x + inner - 200), f64(y + 4), 200, 22), ui2.TextStyle{ color: body_muted, size: 11, align: .right })
	}
	if paged {
		footer_y := height - 30
		out << settings_button(settings_wifi_previous, 'Previous', ui2.rect(f64(x), f64(footer_y), 80, 28), offset > 0)
		out << settings_label('${offset + 1}-${offset + shown} of ${a.wifi_state.count}', x + 88, footer_y + 3, inner - 176, body_muted)
		out << settings_button(settings_wifi_next, 'Next', ui2.rect(f64(x + inner - 80), f64(footer_y), 80, 28), offset < max_offset)
	}
	return out
}

fn (mut a SettingsApp) handle_wifi(event_id string) {
	if event_id == settings_wifi_previous {
		a.wifi_offset = if a.wifi_offset > settings_wifi_page_size {
			a.wifi_offset - settings_wifi_page_size
		} else {
			0
		}
		return
	}
	if event_id == settings_wifi_next {
		if a.wifi_offset + 1 < a.wifi_state.count {
			a.wifi_offset += settings_wifi_page_size
			if a.wifi_offset >= a.wifi_state.count {
				a.wifi_offset = a.wifi_state.count - 1
			}
		}
		return
	}
	if event_id == settings_wifi_refresh {
		a.wifi_action_result = WifiResult.ok
		a.refresh_wifi()
		return
	}
	if event_id != settings_wifi_toggle && event_id != settings_wifi_scan {
		return
	}
	// Revalidate on the device before every write, including stale targets from
	// a frame drawn before the radio or device state changed.
	a.refresh_wifi()
	if event_id == settings_wifi_toggle {
		if !a.wifi_can_toggle() {
			return
		}
		a.wifi_action_result = a.wifi_radio(!a.wifi_state.radio_on)
	} else {
		if !a.wifi_can_scan() {
			return
		}
		a.wifi_offset = 0
		a.wifi_action_result = a.wifi_scan()
	}
	a.refresh_wifi()
}
