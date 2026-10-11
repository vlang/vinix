// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

fn test_disabled_provider_stops_consumers_before_provider() {
	mut s := Supervisor{ count: 3 }
	for i in 0 .. 3 {
		s.services[i] = Service{ name: text('test.${i}')!, executable: text('/bin/sleep')!, dependencies: if i == 0 {
			u32(0)
		} else {
			u32(1) << (i - 1)
		} }
	}
	s.validate() or { panic(err) }
	for i in 0 .. 3 {
		_ = s.tick(1000 + i)
		s.started(i, 10 + i, 1000 + i)
	}
	s.enable(0, false) or { panic(err) }
	assert s.tick(2000).items[0] == ServiceCommand{2, .terminate}
	s.exited(2, 0, 2001)
	assert s.tick(2002).items[0] == ServiceCommand{1, .terminate}
	s.exited(1, 0, 2003)
	assert s.tick(2004).items[0] == ServiceCommand{0, .terminate}
}

fn test_html_plain_fallback_and_binary_exchange_encoding() {
	text := html_text('<b>Hello &amp; world</b>')
	defer { unsafe { text.free() } }
	assert text == 'Hello & world'
	bytes := decode_data('00017fff') or { panic(err) }
	defer { unsafe { bytes.free() } }
	assert bytes.len == 4 && bytes[0] == 0 && bytes[3] == 255
	mut status := SettingsStatus{}
	status.line('Printer service unavailable.')
	status.control('printers.list', 'List', false, false)
	record := status.encode()
	defer { unsafe { record.free() } }
	assert decode_settings_status(record)! == status
}
