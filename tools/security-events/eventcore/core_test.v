// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module eventcore

const boot_a = '00112233445566778899aabbccddeeff'
const boot_b = 'ffeeddccbbaa99887766554433221100'

fn record(sequence u64) string {
	return '${sequence} ${sequence * 1000} 1 1 42 42 1001 1001 1001 3 0 system/hostname/set'
}

fn snapshot(boot string, total u64, retained u64) string {
	mut lines := ['version=1 capacity=256 total=${total} retained=${retained} dropped=${if total > 256 {
		total - 256
	} else {
		u64(0)
	}} boot=${boot}', '# sequence ns kind denied pid tid uid euid loginuid session arg label']
	for i in 0 .. retained {
		lines << record(total - retained + 1 + i)
	}
	lines << ''
	return lines.join('\n')
}

fn test_parse() ! {
	s := parse_snapshot(snapshot(boot_a, 3, 3))!
	assert s.total == 3 && s.events.len == 3 && s.boot == boot_a
	e := s.events[1]
	assert e.sequence == 2 && e.kind == 1 && e.denied && e.pid == 42 && e.uid == 1001
		&& e.login_uid == 1001 && e.session == 3 && e.label == 'system/hostname/set'
	empty := parse_snapshot(snapshot(boot_a, 0, 0))!
	assert empty.events.len == 0
	// A system process: no login.
	system := parse_snapshot('version=1 capacity=256 total=1 retained=1 dropped=0 boot=${boot_a}\n# x\n1 5 4 0 7 7 0 0 4294967295 0 1000 login\n')!
	assert format_event(boot_a, system.events[0], 99) == 'event boot=${boot_a} seq=1 ns=5 collected=99 kind=login result=allowed pid=7 tid=7 uid=0 euid=0 login=none session=0 arg=1000 label=login'
}

fn test_parse_refuses() {
	good := snapshot(boot_a, 3, 3)
	for bad in [
		'',
		good[..good.len - 1], // no final line break
		good.replace('version=1', 'version=2'),
		good.replace('retained=3', 'retained=2'), // header and records disagree
		good.replace('total=3', 'total=2'),
		good.replace(boot_a, 'short'),
		good.replace(boot_a, boot_a.to_upper()),
		good.replace('\n2 2000', '\n5 2000'), // out of order
		good.replace(' 1 1 42', ' 1 2 42'), // denied is 0 or 1
		good.replace('system/hostname/set\n', 'two words\n'),
		good.replace(' 1001 3 0 ', ' 1001 3 '), // a field short
		good.replace('2000', '99999999999999999999999'),
		good.replace(' 42 42 ', ' 4x 42 '),
	] {
		parse_snapshot(bad) or { continue }
		assert false, 'accepted: ${bad}'
	}
}

fn test_advance_writes_each_record_once() ! {
	mut cursor := Cursor{}
	mut lines := []string{}
	lines, cursor = advance(cursor, parse_snapshot(snapshot(boot_a, 3, 3))!, 10)
	assert lines.len == 4 && lines[0] == 'boundary boot=${boot_a} previous=none collected=10'
	assert lines[3].contains(' seq=3 ')
	assert cursor.last == 3
	// The same snapshot again: nothing.
	lines, cursor = advance(cursor, parse_snapshot(snapshot(boot_a, 3, 3))!, 11)
	assert lines.len == 0
	// Two more, with the old ones still in the ring.
	lines, cursor = advance(cursor, parse_snapshot(snapshot(boot_a, 5, 5))!, 12)
	assert lines.len == 2 && lines[0].contains(' seq=4 ') && lines[1].contains(' seq=5 ')
	assert cursor.last == 5
}

fn test_advance_reports_loss_exactly() ! {
	mut cursor := Cursor{
		boot: boot_a
		last: 5
	}
	mut lines := []string{}
	// 400 more happened; the ring kept the last 256.
	lines, cursor = advance(cursor, parse_snapshot(snapshot(boot_a, 405, 256))!, 20)
	assert lines.len == 257
	assert lines[0] == 'loss boot=${boot_a} first=6 last=149 count=144 collected=20'
	assert lines[1].contains(' seq=150 ') && lines[256].contains(' seq=405 ')
	assert cursor.last == 405
	// A collector that starts late on a full ring says what it never saw.
	lines, cursor = advance(Cursor{}, parse_snapshot(snapshot(boot_a, 300, 256))!, 21)
	assert lines[0].starts_with('boundary ') && lines[1] == 'loss boot=${boot_a} first=1 last=44 count=44 collected=21'
	assert lines.len == 258
}

fn test_advance_across_a_reboot() ! {
	cursor := Cursor{
		boot: boot_a
		last: 900
	}
	lines, next := advance(cursor, parse_snapshot(snapshot(boot_b, 2, 2))!, 30)
	assert lines.len == 3
	assert lines[0] == 'boundary boot=${boot_b} previous=${boot_a} collected=30'
	assert lines[1].contains('boot=${boot_b} seq=1 ')
	assert next.boot == boot_b && next.last == 2
}

fn test_cursor_from_log() ! {
	mut cursor := Cursor{}
	mut lines := []string{}
	lines, cursor = advance(cursor, parse_snapshot(snapshot(boot_a, 300, 256))!, 1)
	// A collector that restarts picks up from its own log and repeats
	// nothing, wherever the log ended.
	for cut in [lines.len, 2, 1] {
		found := cursor_from_log(lines[..cut].join('\n') + '\n')
		again, _ := advance(found, parse_snapshot(snapshot(boot_a, 300, 256))!, 2)
		assert again.len == lines.len - cut, 'cut at ${cut}: ${again.len} lines'
		for index, line in again {
			// A log that ended before the gap was written gets the gap
			// written now.
			assert line.starts_with('event ') || (cut == 1 && index == 0 && line.starts_with('loss '))
		}
	}
	assert cursor_from_log('').boot == ''
	assert cursor_from_log('garbage\nevent boot=x\nevent seq=7 boot=${boot_a}\n').last == 7
	assert cursor_from_log('event boot=${boot_a} seq=many\n').boot == ''
}

fn test_retention_settings() ! {
	assert parse_retention('')! == Retention{}
	r := parse_retention('# keep less\nmax_bytes = 65536\nkeep_files=2\nmax_age_days = 0\n')!
	assert r.max_bytes == 65536 && r.keep_files == 2 && r.max_age_days == 0
	for bad in ['max_bytes = 10', 'keep_files = 0', 'keep_files = 65', 'max_age_days = 99999',
		'max_bytes = lots', 'compress = yes', 'max_bytes 4096', 'max_bytes = 4096 = 1'] {
		parse_retention(bad) or { continue }
		assert false, bad
	}
}

// Bytes nobody chose: refuse or accept, never crash, and never accept a
// snapshot whose records do not count up as the header says.
fn test_fuzz_parse() {
	good := snapshot(boot_a, 300, 40)
	mut state := u64(0x243f6a8885a308d3)
	for _ in 0 .. 30000 {
		mut data := good.bytes()
		state ^= state << 13
		state ^= state >> 7
		state ^= state << 17
		for _ in 0 .. int(state % 3) + 1 {
			state ^= state << 13
			state ^= state >> 7
			state ^= state << 17
			data[int(state % u64(data.len))] = u8(state >> 24)
		}
		parsed := parse_snapshot(data.bytestr()) or { continue }
		assert parsed.events.len == int(parsed.retained)
		for i, event in parsed.events {
			assert event.sequence == parsed.total - parsed.retained + 1 + u64(i)
		}
	}
}
