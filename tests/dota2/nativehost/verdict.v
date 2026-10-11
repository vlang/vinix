// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import json2
import math.big
import transcriptcore

pub fn environment_json(result transcriptcore.EnvResult) string {
	mut observations := []string{}
	for label, row in result.observations {
		observations << json2.encode(label) + ':{"exit_code":' + row.exit_code.str() + ',"signal":' + row.signal.str() + ',"native_watchdog":' + row.native_watchdog.str() + '}'
	}
	counts := result.new_counts
	return '{"passed":' + result.passed.str() + ',"pair_completed":' + result.pair_completed.str() + ',"old_failed_as_expected":' + result.old_failed_as_expected.str() + ',"new_runtime_passed":' + result.new_runtime_passed.str() + ',"observations":{' + observations.join(',') + '},"versions":' + json2.encode(result.versions) + ',"new_counts":{"rounds":' + counts.rounds.str() + ',"writes":' + counts.writes.str() + ',"checks":' + counts.checks.str() + ',"overlap":' + counts.overlap.str() + '}}'
}

struct LavaBegin {
	start  int
	body   int
	driver string
	mode   string
}

pub struct LavaVerdict {
pub:
	passed              bool
	pair_completed      bool
	controls_reproduced bool
	fixed_passed        bool
	observations        []string
}

pub fn (verdict LavaVerdict) json() string {
	return '{"passed":' + verdict.passed.str() + ',"pair_completed":' + verdict.pair_completed.str() + ',"controls_reproduced":' + verdict.controls_reproduced.str() + ',"fixed_passed":' + verdict.fixed_passed.str() + ',"observations":[' + verdict.observations.join(',') + ']}'
}

// Decimal fields retain the original Unicode and arbitrary-integer semantics.
fn lava_number(text string, start int, signed bool) ?(string, int) {
	negative := signed && start < text.len && text[start] == `-`
	begin := start + if negative { 1 } else { 0 }
	mut at := begin
	mut digits := ''
	for ch in text[begin..].runes() {
		digit := transcriptcore.decimal_digit(ch)
		if digit < 0 { break }
		digits += u8(`0` + digit).ascii_str()
		at += ch.str().len
	}
	if digits == '' { return none }
	return (if negative { '-' } else { '' }) + digits, at
}

fn lava_numbers(section string, prefix string) ?[]string {
	mut offset := 0
	for offset < section.len {
		found := section[offset..].index(prefix) or { return none }
		mut at := offset + found + prefix.len
		mut numbers := []string{}
		mut valid := true
		for index, field in ['exit=', ' signal=', ' watchdog='] {
			if !section[at..].starts_with(field) {
				valid = false
				break
			}
			value, next := lava_number(section, at + field.len, index == 0) or {
				valid = false
				break
			}
			numbers << value
			at = next
		}
		if valid { return numbers }
		offset += found + 1
	}
	return none
}

pub fn lava_verdict(raw string, status int, drivers []string) !LavaVerdict {
	text := raw.replace('\r', '')
	prefix := 'VINIX-DOTA2-LVP-PAIR-BEGIN: driver='
	mut begins := []LavaBegin{}
	mut offset := 0
	for offset < text.len {
		found := text[offset..].index(prefix) or { break }
		start := offset + found
		mut at := start + prefix.len
		name_start := at
		for at < text.len && ((text[at] >= `a` && text[at] <= `z`) || text[at].is_digit() || text[at] == `-`) {
			at++
		}
		driver := text[name_start..at]
		offset = start + 1
		if driver == '' || !text[at..].starts_with(' mode=') { continue }
		at += 6
		mode_start := at
		for at < text.len && ((text[at] >= `a` && text[at] <= `z`) || text[at] == `-`) { at++ }
		mode := text[mode_start..at]
		if mode == '' || at >= text.len || text[at] != `\n` { continue }
		begins << LavaBegin{start, at + 1, driver, mode}
		offset = at + 1
	}
	end := text.index('VINIX-DOTA2-LVP-PAIR-END') or { -1 }
	mut planned := []string{}
	for driver in drivers {
		for mode in lava_modes { planned << driver + ':' + mode }
	}
	ordered := begins.map(it.driver + ':' + it.mode) == planned && end > 0
	mut controls := ordered
	mut fixed := ordered
	mut observations := []string{}
	for index, begin in begins {
		stop := if index + 1 < begins.len {
			begins[index + 1].start
		} else if end > 0 {
			end
		} else {
			text.len
		}
		section := if stop >= begin.body { text[begin.body..stop] } else { '' }
		result := lava_numbers(section, 'VINIX-DOTA2-LVP-PAIR-RESULT: driver=' + begin.driver + ' mode=' + begin.mode + ' ') or { []string{} }
		mut stored := []string{}
		value_prefix := 'VINIX-DOTA2-LVP-RESULT: mode=' + begin.mode + ' '
		mut search := 0
		for search < section.len {
			found := section[search..].index(value_prefix) or { break }
			mut at := search + found + value_prefix.len
			mut values := []string{}
			for field in ['set0=', ' set1=', ' set2='] {
				if !section[at..].starts_with(field) { break }
				at += field.len
				if at + 8 > section.len || !section[at..at + 8].bytes().all(it.is_digit() || (it >= `a` && it <= `f`)) {
					break
				}
				values << section[at..at + 8]
				at += 8
			}
			if values.len == 3 {
				stored = values.clone()
				break
			}
			search += found + 1
		}
		probe_passed := section.contains('VINIX-DOTA2-LVP-PASS: ' + begin.mode + '\n')
		passed := result.len == 3 && result.map(big.integer_from_string(it) or { big.one_int }) == [
			big.zero_int,
			big.zero_int,
			big.zero_int,
		] && probe_passed && stored == ['00000000', '00000000', '56494e58']
		crashed := result.len == 3 && result.map(big.integer_from_string(it) or { big.one_int }) == [
			big.integer_from_int(-1),
			big.integer_from_int(11),
			big.zero_int,
		] && !probe_passed
		if begin.driver == 'fixed' {
			fixed = fixed && passed
		} else {
			controls = controls && if begin.mode == 'bound' { passed } else { crashed }
		}
		mut row := {
			'driver':          json2.Any(begin.driver)
			'mode':            json2.Any(begin.mode)
			'exit_code':       json2.Any(json2.Null{})
			'signal':          json2.Any(json2.Null{})
			'native_watchdog': json2.Any(json2.Null{})
			'stored':          if stored.len == 3 {
				json2.Any(stored.map(json2.Any(it)))
			} else {
				json2.Any(json2.Null{})
			}
			'probe_passed':    json2.Any(probe_passed)
		}
		if result.len == 3 {
			for key in ['exit_code', 'signal', 'native_watchdog'] { row.delete(key) }
			encoded := json2.encode(json2.Any(row))
			observations << encoded[..encoded.len - 1] + ',"exit_code":' + big.integer_from_string(result[0])!.str() + ',"signal":' + big.integer_from_string(result[1])!.str() + ',"native_watchdog":' + big.integer_from_string(result[2])!.str() + '}'
		} else {
			observations << json2.encode(json2.Any(row))
		}
	}
	completed := status == 0 && ordered
	return LavaVerdict{completed && controls && fixed, completed, controls, fixed, observations}
}
