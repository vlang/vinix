// SPDX-License-Identifier: GPL-2.0-or-later
module transcriptcore

import math.big
import json2

pub struct EnvObservation {
pub:
	exit_code       big.Integer
	signal          big.Integer
	native_watchdog big.Integer
}

pub struct EnvCounts {
pub:
	rounds  int
	writes  big.Integer
	checks  big.Integer
	overlap big.Integer
}

pub struct EnvResult {
pub:
	passed                 bool
	pair_completed         bool
	old_failed_as_expected bool
	new_runtime_passed     bool
	observations           map[string]EnvObservation
	versions               map[string]json2.Any
	new_counts             EnvCounts
}

struct NumericMatch {
	start  int
	values []big.Integer
}

// Return the greedy Unicode decimal field and its first following byte.
fn env_number(text string, start int, signed bool) ?(big.Integer, int) {
	if start >= text.len { return none }
	negative := signed && text[start] == `-`
	begin := start + if negative { 1 } else { 0 }
	mut offset := begin
	mut digits := []u8{}
	for ch in text[begin..].runes() {
		digit := decimal_digit(ch)
		if digit < 0 { break }
		digits << u8(digit) + `0`
		offset += ch.str().len
	}
	if digits.len == 0 { return none }
	raw := if negative { '-' + digits.bytestr() } else { digits.bytestr() }
	number := big.integer_from_string(raw) or { return none }
	return number, offset
}

fn env_numbers(text string, prefix string, fields []string) []NumericMatch {
	mut result := []NumericMatch{}
	mut offset := 0
	for offset < text.len {
		found := text[offset..].index(prefix) or { break }
		start := offset + found
		mut position := start + prefix.len
		mut values := []big.Integer{}
		mut valid := true
		for index, field in fields {
			if !text[position..].starts_with(field) {
				valid = false
				break
			}
			position += field.len
			value, end := env_number(text, position, false) or {
				valid = false
				break
			}
			values << value
			position = end
			if index + 1 < fields.len {
				if position >= text.len || text[position] != ` ` {
					valid = false
					break
				}
				position++
			}
		}
		if valid {
			result << NumericMatch{start, values}
			offset = position
		} else {
			offset = start + 1
		}
	}
	return result
}

fn env_results(text string) ([]NumericMatch, []string) {
	prefix := 'VINIX-DOTA2-ENV-PAIR-RESULT: variant='
	mut matches := []NumericMatch{}
	mut labels := []string{}
	mut offset := 0
	for offset < text.len {
		found := text[offset..].index(prefix) or { break }
		start := offset + found
		mut position := start + prefix.len
		label := if text[position..].starts_with('old') {
			'old'
		} else if text[position..].starts_with('new') {
			'new'
		} else {
			''
		}
		position += label.len
		if label == '' || !text[position..].starts_with(' exit=') {
			offset = start + 1
			continue
		}
		position += 6
		code, next := env_number(text, position, true) or {
			offset = start + 1
			continue
		}
		position = next
		if !text[position..].starts_with(' signal=') {
			offset = start + 1
			continue
		}
		number, next_signal := env_number(text, position + 8, false) or {
			offset = start + 1
			continue
		}
		position = next_signal
		if !text[position..].starts_with(' watchdog=') {
			offset = start + 1
			continue
		}
		timeout, end := env_number(text, position + 10, false) or {
			offset = start + 1
			continue
		}
		matches << NumericMatch{start, [code, number, timeout]}
		labels << label
		offset = end
	}
	return matches, labels
}

fn env_version(text string) json2.Any {
	prefix := 'VINIX-DOTA2-ENV-LIBC: '
	mut versions := []string{}
	mut offset := 0
	for offset < text.len {
		found := text[offset..].index(prefix) or { break }
		begin := offset + found + prefix.len
		mut position := begin
		for position < text.len && text[position] >= `0` && text[position] <= `9` { position++ }
		if position == begin || position >= text.len || text[position] != `.` {
			offset = begin
			continue
		}
		position++
		fraction := position
		for position < text.len && text[position] >= `0` && text[position] <= `9` { position++ }
		if position > fraction { versions << text[begin..position].clone() }
		offset = position
	}
	return if versions.len == 1 { json2.Any(versions[0]) } else { json2.Any(json2.Null{}) }
}

pub fn environment_verdict(raw string, harness_zero bool) EnvResult {
	text := raw.replace('\r', '')
	result_lines, labels := env_results(text)
	mut observations := map[string]EnvObservation{}
	for index, item in result_lines {
		observations[labels[index]] = EnvObservation{item.values[0], item.values[1], item.values[2]}
	}
	start := text.index('VINIX-DOTA2-ENV-PAIR-BEGIN: old') or { -1 }
	split := text.index('VINIX-DOTA2-ENV-PAIR-BEGIN: new') or { -1 }
	end := text.index('VINIX-DOTA2-ENV-PAIR-END') or { -1 }
	ordered := 0 <= start && start < split && split < end
	old := if ordered { text[start..split] } else { '' }
	new := if ordered { text[split..end] } else { '' }
	old_version := env_version(old)
	new_version := env_version(new)
	versions := {
		'old': old_version
		'new': new_version
	}
	rows := env_numbers(new, 'VINIX-DOTA2-ENV-ROUND: ', ['round=', 'writes=', 'checks=', 'overlap='])
	mut complete := rows.len == 32
	mut checks := big.zero_int
	mut overlap := big.zero_int
	for index, row in rows {
		values := row.values
		round := big.integer_from_int(index + 1)
		complete = complete && values[0] == round && values[1] == round * big.integer_from_int(1000) && values[2] > big.zero_int && values[3] > big.zero_int && values[3] <= values[2]
		checks = checks + values[2]
		overlap = overlap + values[3]
	}
	summaries := env_numbers(new, 'VINIX-DOTA2-ENV-PASS: ', ['rounds=', 'writes=', 'checks=', 'overlap='])
	counts := EnvCounts{rows.len, if rows.len > 0 { rows.last().values[1] } else { big.zero_int }, checks, overlap}
	summary_matches := summaries.len == 1 && summaries[0].values == [
		big.integer_from_int(32),
		big.integer_from_int(32000),
		checks,
		overlap,
	]
	results_ordered := result_lines.len == 2 && labels[0] == 'old' && labels[1] == 'new' && start < result_lines[0].start && result_lines[0].start < split && split < result_lines[1].start && result_lines[1].start < end
	completed := harness_zero && ordered && results_ordered
	old_observation := observations['old'] or { EnvObservation{} }
	new_observation := observations['new'] or { EnvObservation{} }
	old_expected := 'old' in observations && old_observation == EnvObservation{big.integer_from_int(-1), big.integer_from_int(11), big.zero_int} && old.contains('VINIX-DOTA2-ENV-START') && old_version !is json2.Null
	new_passed := 'new' in observations && new_observation == EnvObservation{big.zero_int, big.zero_int, big.zero_int} && new.contains('VINIX-DOTA2-ENV-START') && new_version !is json2.Null && !new.contains('VINIX-DOTA2-ENV-FAIL:') && complete && summary_matches
	return EnvResult{completed && old_expected && new_passed, completed, old_expected, new_passed, observations, versions, counts}
}
