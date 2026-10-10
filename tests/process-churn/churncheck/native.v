// SPDX-License-Identifier: GPL-2.0-or-later
module churncheck

import math.big

pub const modes = ['exec', 'slabinfo', 'waits', 'directories', 'pipes', 'sampling', 'select']
pub const measurement_fields = ['runs', 'used_delta_kib', 'cumulative_used_kib', 'slab_delta_kib',
	'cumulative_slab_kib', 'cached_delta_kib', 'large_pages_delta']

pub fn programs(mode string) ![]string {
	return match mode {
		'exec' { ['true', 'sleep', 'curl', 'awk'] }
		'slabinfo' { ['slabinfo'] }
		'waits' { ['idle_control', 'nanosleep', 'clock_nanosleep', 'fork_reap'] }
		'directories' { ['mkdir_tmpfs', 'mkdir_ext2'] }
		'pipes' { ['pipe'] }
		'sampling' { ['sampling'] }
		'select' { ['select_ready', 'pselect_ready'] }
		else { return error('unknown mode: ${mode}') }
	}
}

pub struct Identity {
pub:
	program string
	cohort  big.Integer
}

fn (identity Identity) key() string { return identity.program + '\x00' + identity.cohort.str() }

fn (identity Identity) description() string {
	return '(${quoted(identity.program)}, ${identity.cohort})'
}

fn (identity Identity) class_key(size big.Integer) string {
	return identity.key() + '\x00' + size.str()
}

pub struct Measurement {
pub:
	identity Identity
	values   map[string]big.Integer
	fields   map[string]string
}

pub struct Report {
pub:
	measurements []Measurement
	live         map[string]big.Integer
}

fn coverage(actual map[string]big.Integer, expected map[string]bool) bool {
	return actual.len == expected.len && actual.keys().all(it in expected)
}

pub fn inspect(raw string, mode string, flat_slabinfo bool, flat_small bool) !Report {
	source := log_text(raw)
	names := programs(mode)!
	zero := big.integer_from_int(0)
	mut measurements := []Measurement{}
	mut measured := map[string]bool{}
	mut grace := map[string]big.Integer{}
	mut live := map[string]big.Integer{}
	mut classes := map[string]big.Integer{}
	mut class_ids := []string{}
	mut work := map[string]big.Integer{}
	mut filesystems := map[string]big.Integer{}
	mut starts := 0
	mut done := 0
	for raw_line in lines(source) {
		line := stripped(raw_line)
		if line == 'PROCESS CHURN: START' { starts++ }
		if line == 'PROCESS CHURN: DONE failures=0' { done++ }
		if ['PROCESS CHURN: FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'ERROR:'].any(line.contains(it)) {
			return error(line)
		}
		if line.starts_with('CHURN FILESYSTEM ') {
			row := fields(line)!
			program := required(row, 'program')!
			if program in filesystems { return error('duplicate filesystem evidence') }
			filesystems[program] = integer(required(row, 'type')!, 16)!
		}
		if !['CHURN MEASURE ', 'CHURN GRACE ', 'CHURN CLASS ', 'CHURN WORK ', 'PERF-SITE '].any(line.starts_with(it)) {
			continue
		}
		row := fields(line)!
		identity := Identity{required(row, 'program')!, integer_field(row, 'cohort')!}
		key := identity.key()
		if identity.program !in names {
			return error('unexpected program: ${identity.description()}')
		}
		if line.starts_with('CHURN MEASURE ') {
			if key in measured { return error('duplicate measurement: ${identity.description()}') }
			mut values := map[string]big.Integer{}
			for field in measurement_fields { values[field] = integer_field(row, field)! }
			count := big.integer_from_int(if mode == 'directories' { 200 } else { 300 })
			if values['runs'] != count {
				return error('wrong cohort size: ${identity.description()}')
			}
			measured[key] = true
			measurements << Measurement{identity, values, row}
		} else if line.starts_with('CHURN GRACE ') {
			if key in grace { return error('duplicate grace: ${identity.description()}') }
			elapsed := integer_field(row, 'elapsed_ns')!
			grace[key] = elapsed
			if elapsed < big.integer_from_i64(6000000000) {
				return error('short grace: ${identity.description()}: ${elapsed}')
			}
		} else if line.starts_with('CHURN CLASS ') {
			size := integer_field(row, 'size')!
			class_key := identity.class_key(size)
			if size <= zero || class_key in classes {
				return error('invalid class: (${quoted(identity.program)}, ${identity.cohort}, ${size})')
			}
			classes[class_key] = integer_field(row, 'objects_delta')!
			class_ids << key
		} else if line.starts_with('CHURN WORK ') {
			if key in work {
				return error('duplicate workload evidence: ${identity.description()}')
			}
			work[key] = integer_field(row, 'elapsed_ns')!
			if integer_field(row, 'calls')! != big.integer_from_int(300) || work[key] < zero {
				return error('invalid workload evidence: ${identity.description()}')
			}
		} else if total, dropped := summary(line) {
			if key in live {
				return error('duplicate allocation summary: ${identity.description()}')
			}
			live[key] = total
			if dropped != zero { return error('tracking overflow: ${identity.description()}') }
		}
	}
	mut expected := map[string]bool{}
	mut expected_grace := map[string]bool{}
	for name in names {
		for cohort in 0 .. 4 {
			key := Identity{name, big.integer_from_int(cohort)}.key()
			expected_grace[key] = true
			if cohort > 0 { expected[key] = true }
		}
	}
	if starts != 1 || done != 1 { return error('expected one START/DONE, got ${starts}/${done}') }
	if measured.len != expected.len || !measured.keys().all(it in expected) || !coverage(live, expected) || !coverage(grace, expected_grace) {
		return error('incomplete or unexpected measurement/grace/allocation coverage')
	}
	if class_ids.any(it !in expected) { return error('class report outside measured cohorts') }
	if mode == 'waits' {
		if !coverage(work, expected) { return error('missing timed-workload coverage') }
		for name in ['nanosleep', 'clock_nanosleep'] {
			for cohort in 1 .. 4 {
				if work[Identity{name, big.integer_from_int(cohort)}.key()] < big.integer_from_int(300000000) {
					return error('300 one-millisecond sleeps consumed less than 300 ms')
				}
			}
		}
	} else if work.len > 0 {
		return error('unexpected timed-workload report')
	}
	if mode == 'directories' {
		if filesystems.len != 2 || 'mkdir_tmpfs' !in filesystems || 'mkdir_ext2' !in filesystems || filesystems['mkdir_tmpfs'] != big.integer_from_int(0x01021994) || filesystems['mkdir_ext2'] != big.integer_from_int(0xef53) {
			return error('missing or incorrect tmpfs/ext2 identity')
		}
	} else if filesystems.len > 0 {
		return error('unexpected filesystem report')
	}
	if flat_slabinfo {
		if mode != 'slabinfo' { return error('flat slabinfo check requires --mode slabinfo') }
		for cohort in 1 .. 4 {
			identity := Identity{'slabinfo', big.integer_from_int(cohort)}
			value := classes[identity.class_key(big.integer_from_int(48))] or { zero }
			if value != zero {
				return error('slabinfo retains 48-byte descriptors in cohort ${cohort}')
			}
		}
		last := measurements.filter(it.identity.cohort == big.integer_from_int(3))[0]
		if last.values['slab_delta_kib'] != zero || last.values['large_pages_delta'] != zero {
			return error('last slabinfo cohort has not settled')
		}
	}
	if flat_small {
		if mode !in ['waits', 'select'] {
			return error('small-object check requires --mode waits or select')
		}
		checked := if mode == 'waits' { ['fork_reap'] } else { names }
		marker := if mode == 'waits' {
			'CHURN SEMANTICS: fork executable path preserved'
		} else {
			'CHURN SEMANTICS: pselect pointers, masks, timeout, interruption, wake'
		}
		for name in checked {
			for cohort in 1 .. 4 {
				maximum := big.integer_from_int(if cohort == 1 { 2 } else { 0 })
				key := Identity{name, big.integer_from_int(cohort)}.class_key(big.integer_from_int(16))
				value := classes[key] or { zero }
				if value > maximum {
					return error('16-byte operation objects do not settle: ${name}/${cohort}')
				}
			}
		}
		if source.count(marker) != 1 {
			return error('missing or duplicate lifetime/ABI semantics evidence')
		}
	}
	return Report{measurements, live}
}

pub fn (report Report) output(flat_slabinfo bool) string {
	mut output := ''
	for measurement in report.measurements {
		identity := measurement.identity
		output += '${identity.program} cohort=${identity.cohort}: used=${measurement.values['used_delta_kib']} KiB, slab=${measurement.values['slab_delta_kib']} KiB, tracked_live=${report.live[identity.key()]}\n'
	}
	return output + 'PASS: complete cohorts, real grace, intact tracking' + if flat_slabinfo {
		', slabinfo descriptor counts flat\n'
	} else {
		'\n'
	}
}
