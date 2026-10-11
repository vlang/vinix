// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the collector of security events knows that is not a file
// operation: the kernel's snapshot format, what counts as new, what was
// lost, and how long records are kept.
//
// The kernel keeps the newest 256 decisions (kernel/security/events.v) and
// numbers them from 1 for as long as the machine is up. A snapshot is
// everything it still has. The collector's whole state is two things, the
// boot it is following and the last number it wrote down; from those and a
// snapshot this module says which lines to append, including a line for
// every gap, so that a log never implies that nothing happened where
// something was missed.
module eventcore

pub const max_snapshot = 256 * 1024
pub const max_events = 4096

pub struct Event {
pub:
	sequence  u64
	ns        u64
	kind      u32
	denied    bool
	pid       i64
	tid       i64
	uid       u32
	euid      u32
	login_uid u32
	session   u32
	arg       u64
	label     string
}

pub struct Snapshot {
pub:
	total    u64
	retained u64
	dropped  u64
	boot     string
	events   []Event
}

// Where a collector is in the stream.
pub struct Cursor {
pub mut:
	boot string
	last u64
}

const kind_names = ['unknown', 'policy', 'mac', 'seat', 'login', 'identity', 'signal', 'network',
	'file', 'service']

pub fn kind_name(kind u32) string {
	return if kind < u32(kind_names.len) { kind_names[kind] } else { 'kind-${kind}' }
}

fn number(text string) !u64 {
	if text.len == 0 || text.len > 20 {
		return error('not a number')
	}
	mut value := u64(0)
	for i in 0 .. text.len {
		ch := text[i]
		if ch < `0` || ch > `9` {
			return error('not a number')
		}
		digit := u64(ch - `0`)
		if value > (u64(0xffffffffffffffff) - digit) / 10 {
			return error('number out of range')
		}
		value = value * 10 + digit
	}
	return value
}

fn small(text string) !u32 {
	value := number(text)!
	if value > u64(0xffffffff) {
		return error('number out of range')
	}
	return u32(value)
}

fn signed(text string) !i64 {
	if text.starts_with('-') {
		return -i64(number(text[1..])!)
	}
	return i64(number(text)!)
}

fn header_value(fields []string, name string) !string {
	for field in fields {
		if field.starts_with(name + '=') {
			return field[name.len + 1..]
		}
	}
	return error('the header has no ${name}')
}

// A label as the kernel writes one: printable, no space.
fn valid_label(text string) bool {
	if text.len == 0 || text.len > 64 {
		return false
	}
	for i in 0 .. text.len {
		if text[i] <= 0x20 || text[i] >= 0x7f {
			return false
		}
	}
	return true
}

// A whole snapshot or an error: half a snapshot would be reported as loss
// that did not happen.
pub fn parse_snapshot(text string) !Snapshot {
	if text.len == 0 || text.len > max_snapshot {
		return error('snapshot of ${text.len} bytes')
	}
	if text[text.len - 1] != `\n` {
		return error('snapshot does not end with a line')
	}
	lines := text[..text.len - 1].split('\n')
	if lines.len < 2 || !lines[0].starts_with('version=1 ') || !lines[1].starts_with('# ') {
		return error('not a version 1 snapshot')
	}
	header := lines[0].split(' ')
	total := number(header_value(header, 'total')!)!
	retained := number(header_value(header, 'retained')!)!
	dropped := number(header_value(header, 'dropped')!)!
	boot := header_value(header, 'boot')!
	if boot.len != 32 || retained > total || retained > u64(max_events)
		|| u64(lines.len - 2) != retained {
		return error('snapshot header does not match its records')
	}
	for i in 0 .. boot.len {
		ch := boot[i]
		if !((ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `f`)) {
			return error('snapshot has no boot identity')
		}
	}
	mut events := []Event{cap: int(retained)}
	mut expected := total - retained + 1
	for line in lines[2..] {
		fields := line.split(' ')
		if fields.len != 12 {
			return error('record with ${fields.len} fields')
		}
		sequence := number(fields[0])!
		if sequence != expected {
			return error('record ${sequence} where ${expected} was expected')
		}
		expected++
		if fields[3] != '0' && fields[3] != '1' {
			return error('record ${sequence}: neither allowed nor denied')
		}
		if !valid_label(fields[11]) {
			return error('record ${sequence}: invalid label')
		}
		events << Event{
			sequence:  sequence
			ns:        number(fields[1])!
			kind:      small(fields[2])!
			denied:    fields[3] == '1'
			pid:       signed(fields[4])!
			tid:       signed(fields[5])!
			uid:       small(fields[6])!
			euid:      small(fields[7])!
			login_uid: small(fields[8])!
			session:   small(fields[9])!
			arg:       number(fields[10])!
			label:     fields[11]
		}
	}
	return Snapshot{
		total:    total
		retained: retained
		dropped:  dropped
		boot:     boot
		events:   events
	}
}

// One record as a line of the log. `wall` is the collector's clock when it
// read the record: when it was collected, not when it happened, and not a
// time anyone should trust more than the machine's clock.
pub fn format_event(boot string, event Event, wall i64) string {
	login := if event.login_uid == u32(0xffffffff) { 'none' } else { event.login_uid.str() }
	return 'event boot=${boot} seq=${event.sequence} ns=${event.ns} collected=${wall} kind=${kind_name(event.kind)} result=${if event.denied {
		'denied'
	} else {
		'allowed'
	}} pid=${event.pid} tid=${event.tid} uid=${event.uid} euid=${event.euid} login=${login} session=${event.session} arg=${event.arg} label=${event.label}'
}

// The lines to append for a snapshot, and where the collector is after
// them. Nothing is returned twice: what `cursor` already covers is skipped.
pub fn advance(cursor Cursor, snapshot Snapshot, wall i64) ([]string, Cursor) {
	mut lines := []string{}
	mut last := cursor.last
	if cursor.boot != snapshot.boot || snapshot.total < cursor.last {
		// Another boot, or the same one counting from the start again:
		// either way the numbers begin anew.
		lines << 'boundary boot=${snapshot.boot} previous=${if cursor.boot == '' {
			'none'
		} else {
			cursor.boot
		}} collected=${wall}'
		last = 0
	}
	first := snapshot.total - snapshot.retained + 1
	if snapshot.total > last && first > last + 1 {
		// Overwritten in the kernel before this collector saw them.
		lines << 'loss boot=${snapshot.boot} first=${last + 1} last=${first - 1} count=${first - 1 - last} collected=${wall}'
	}
	for event in snapshot.events {
		if event.sequence > last {
			lines << format_event(snapshot.boot, event, wall)
		}
	}
	return lines, Cursor{
		boot: snapshot.boot
		last: if snapshot.total > last { snapshot.total } else { last }
	}
}

// Where a log left off, from its last lines: the boot and number of the
// last record or the end of the last gap, whichever comes later in the text.
pub fn cursor_from_log(tail string) Cursor {
	mut cursor := Cursor{}
	mut lines := tail.split('\n')
	// What follows the last line break is a line that was never finished:
	// its record was not kept and must be written again.
	lines.delete_last()
	for line in lines {
		fields := line.split(' ')
		if fields.len < 3 {
			continue
		}
		boot := header_value(fields, 'boot') or { continue }
		match fields[0] {
			'event' {
				sequence := number(header_value(fields, 'seq') or { continue }) or { continue }
				cursor = Cursor{
					boot: boot
					last: sequence
				}
			}
			'loss' {
				sequence := number(header_value(fields, 'last') or { continue }) or { continue }
				cursor = Cursor{
					boot: boot
					last: sequence
				}
			}
			'boundary' {
				cursor = Cursor{
					boot: boot
				}
			}
			else {}
		}
	}
	return cursor
}

// How much is kept. A log that grows past `max_bytes` is set aside under
// the next number; more than `keep_files` set aside, or one older than
// `max_age_days`, is deleted. Deleting evidence is a decision: it is made
// here, by numbers an administrator can read and change, and nowhere else.
pub struct Retention {
pub:
	max_bytes    i64 = 4 * 1024 * 1024
	keep_files   int = 8
	max_age_days int = 90
}

pub fn parse_retention(text string) !Retention {
	mut max_bytes := Retention{}.max_bytes
	mut keep_files := Retention{}.keep_files
	mut max_age_days := Retention{}.max_age_days
	if text.len > 4096 {
		return error('settings file too large')
	}
	for raw in text.split('\n') {
		line := raw.trim_space()
		if line == '' || line.starts_with('#') {
			continue
		}
		parts := line.split('=')
		if parts.len != 2 {
			return error('expected key = value: ${line}')
		}
		value := number(parts[1].trim_space()) or { return error('${parts[0].trim_space()} is not a number') }
		match parts[0].trim_space() {
			'max_bytes' {
				if value < 4096 || value > u64(1) << 32 {
					return error('max_bytes must be between 4096 and 4294967296')
				}
				max_bytes = i64(value)
			}
			'keep_files' {
				if value < 1 || value > 64 {
					return error('keep_files must be between 1 and 64')
				}
				keep_files = int(value)
			}
			'max_age_days' {
				// 0 keeps set-aside logs until keep_files pushes them out.
				if value > 3650 {
					return error('max_age_days must be at most 3650')
				}
				max_age_days = int(value)
			}
			else {
				return error('unknown setting ${parts[0].trim_space()}')
			}
		}
	}
	return Retention{
		max_bytes:    max_bytes
		keep_files:   keep_files
		max_age_days: max_age_days
	}
}
