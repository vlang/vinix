// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

import gpu.dcp.backlight.core as blcore

fn test_backlight_snapshot_parser() {
	s := parse_backlight(valid_backlight.bytes()) or { panic('valid snapshot') }
	assert s.requested_nits == 100 && s.actual_nits == 99
	assert s.min_nits == 2 && s.max_nits == 400 && s.online && !s.pending && !s.writable
	unknown := 'online=1\npending=1\nmin_nits=2\nmax_nits=400\nactual_nits=unknown\nrequested_nits=unknown\n'
	u := parse_backlight(unknown.bytes()) or { panic('unknown/order-independent') }
	assert u.requested_nits == -1 && u.actual_nits == -1 && backlight_percent(&u) == -1
	for n in 0 .. valid_backlight.len {
		assert parse_backlight(valid_backlight[..n].bytes()) == none
	}
	for bad in ['-1', '+1', ' 2', '2 ', '', '2147483648', '0', '401'] {
		assert parse_backlight(valid_backlight.replace('requested_nits=100', 'requested_nits=${bad}').bytes()) == none
	}
	for bad in [valid_backlight + 'online=1\n', valid_backlight + 'extra=1\n',
		valid_backlight.replace('pending=0', 'pending=2'),
		valid_backlight.replace('min_nits=2', 'min_nits=401'),
		valid_backlight.replace('online=1\n', ''), valid_backlight.replace('online', 'on\x00ine')] {
		assert parse_backlight(bad.bytes()) == none
	}
	out := parse_backlight(unknown.replace('actual_nits=unknown', 'actual_nits=900').bytes()) or { panic('actual may exceed limits') }
	assert out.actual_nits == 900 && backlight_percent(&out) == 100
}

fn test_backlight_percentage_bounds_and_overflow() {
	mut s := BacklightState{ min_nits: 2, max_nits: 400 }
	assert backlight_percent_to_nits(&s, 0)? == 2
	assert backlight_percent_to_nits(&s, 50)? == 201
	assert backlight_percent_to_nits(&s, 100)? == 400
	assert backlight_percent_to_nits(&s, -1) == none
	assert backlight_percent_to_nits(&s, 101) == none
	for maximum in 2 .. 510 {
		s.max_nits = maximum
		mut previous := 0
		for percent in 0 .. 101 {
			nits := backlight_percent_to_nits(&s, percent)?
			assert nits >= 2 && nits <= maximum && nits >= previous
			previous = nits
			s.requested_nits = nits
			assert backlight_percent(&s) >= 0 && backlight_percent(&s) <= 100
		}
	}
	s.max_nits = 0x7fffffff
	s.requested_nits = backlight_percent_to_nits(&s, 50)?
	assert backlight_percent(&s) == 50
	assert backlight_percent_to_nits(&s, 100)? == 0x7fffffff
	s = BacklightState{ requested_nits: 100, actual_nits: 300, min_nits: 2, max_nits: 400 }
	assert backlight_percent(&s) == 25
	s.requested_nits = -1
	assert backlight_percent(&s) == 75
}

fn test_backlight_reads_permissions_and_atomic_failure() {
	mut m := mock_backlight()
	mut s := BacklightState{}
	assert read_backlight_with(mut m, mut s) == .ok
	assert s.writable && s.actual_nits == 99
	assert m.opens == 1 && m.reads == 1 && m.closes == 1 && m.writes == 0 && !m.live
	m = mock_backlight()
	m.rw_error = .permission
	assert read_backlight_with(mut m, mut s) == .ok && !s.writable
	assert m.opens == 2 && m.closes == 1 && m.writes == 0
	assert set_backlight_percent_with(mut m, 50) == .permission && !m.live && m.writes == 0
	before := s
	m.reply = 'incomplete'.bytes()
	assert read_backlight_with(mut m, mut s) == .invalid
	assert s == before && !m.live
}

fn test_backlight_device_failures_close_exactly_once() {
	mut s := BacklightState{}
	for failure in [DeviceError.unavailable, .permission, .io, .interrupted] {
		mut m := mock_backlight()
		m.open_error = failure
		assert read_backlight_with(mut m, mut s) == backlight_io_result(failure)
		assert set_backlight_percent_with(mut m, 50) == backlight_io_result(failure)
		assert !m.live && m.writes == 0 && m.closes == 0
	}
	for kind in 0 .. 5 {
		mut m := mock_backlight()
		match kind {
			0 {
				m.character = false
			}
			1 {
				m.stat_error = .io
			}
			2 {
				m.read_error = .io
			}
			3 {
				m.chunk = 12
			}
			else {
				m.close_error = .interrupted
			}
		}
		assert read_backlight_with(mut m, mut s) != .ok
		assert !m.live && m.closes == 1 && m.writes == 0
		if kind == 3 {
			assert m.reads == 1
		} // never concatenate snapshots
	}
	mut offline := mock_backlight()
	offline.reply = valid_backlight.replace('online=1', 'online=0').bytes()
	assert set_backlight_percent_with(mut offline, 50) == .offline
	assert !offline.live && offline.writes == 0
}

fn test_backlight_whole_writes_and_fresh_bounds() {
	mut m := mock_backlight()
	assert set_backlight_percent_with(mut m, 50) == .ok
	assert m.written.bytestr() == '201\n' && m.writes == 1 && !m.live
	mut s := BacklightState{}
	assert read_backlight_with(mut m, mut s) == .ok
	assert s.requested_nits == 100 && s.actual_nits == 99 // no fabricated readback
	m.reply = valid_backlight.replace('min_nits=2', 'min_nits=10').replace('max_nits=400', 'max_nits=200').bytes()
	assert set_backlight_percent_with(mut m, 50) == .ok
	assert m.written.bytestr() == '105\n'
	m = mock_backlight()
	m.short_write = true
	assert set_backlight_percent_with(mut m, 50) == .io
	assert m.writes == 1 && !m.live
	m = mock_backlight()
	m.write_error = .io
	assert set_backlight_percent_with(mut m, 50) == .io && !m.live
	m = mock_backlight()
	assert set_backlight_percent_with(mut m, -1) == .invalid
	assert set_backlight_percent_with(mut m, 101) == .invalid && m.opens == 0
}

fn test_backlight_bounded_interrupts() {
	for interrupts in [2, 20] {
		mut m := mock_backlight()
		mut s := BacklightState{}
		m.interrupted_reads = interrupts
		result := read_backlight_with(mut m, mut s)
		assert result == if interrupts == 2 { BacklightResult.ok } else { BacklightResult.io }
		assert m.reads == if interrupts == 2 { 3 } else { 4 }
		assert !m.live
		m = mock_backlight()
		m.interrupted_writes = interrupts
		assert set_backlight_percent_with(mut m, 50) == result
		assert m.writes == if interrupts == 2 { 3 } else { 4 }
		assert !m.live
	}
}

fn test_backlight_round_trip_with_native_kernel_core() {
	mut core := blcore.State{}
	assert core.initialise(.v13_3, 400, 1000, 99000, true) == .ok
	assert core.set_online(true) == .ok
	mut text := [192]u8{}
	mut buffer := unsafe { (&text[0]).vbytes(text.len) }
	mut n := core.format(mut buffer)?
	mut m := MockDevice{ reply: buffer[..n].clone() }
	mut s := BacklightState{}
	assert read_backlight_with(mut m, mut s) == .ok
	assert s.requested_nits == -1 && s.actual_nits == 99
	assert set_backlight_percent_with(mut m, 75) == .ok
	assert core.write(m.written) == .ok
	n = core.format(mut buffer)?
	s = parse_backlight(buffer[..n])?
	assert s.pending && s.requested_nits == 301 && s.actual_nits == 99
	assert core.set_online(false) == .ok
	n = core.format(mut buffer)?
	s = parse_backlight(buffer[..n])?
	assert !s.online && s.actual_nits == -1
}
