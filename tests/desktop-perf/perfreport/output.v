// SPDX-License-Identifier: GPL-2.0-or-later
module perfreport

import json2
import math
import os

fn align(text string, width int, right bool) string {
	count := width - text.runes().len
	if count <= 0 { return text }
	return if right { ' '.repeat(count) + text } else { text + ' '.repeat(count) }
}

struct Group {
	scenario string
	variant  string
mut:
	rows []map[string]Value
}

// Preserve input order for equal samples (including the sign of zero).
// Short runs use the same stable binary insertion policy as the original
// median helper, so unordered floating samples retain their run order too.
fn sort_samples(mut values []f64) {
	if values.len < 2 { return }
	if values.len >= 64 && !values.any(math.is_nan(it)) {
		merge_samples(mut values)
		return
	}
	mut run := 2
	if values[1] < values[0] {
		for run < values.len && values[run] < values[run - 1] { run++ }
		for index in 0 .. run / 2 {
			values[index], values[run - index - 1] = values[run - index - 1], values[index]
		}
	} else {
		for run < values.len && !(values[run] < values[run - 1]) { run++ }
	}
	for index in run .. values.len {
		pivot := values[index]
		mut low := 0
		mut high := index
		for low < high {
			middle := (low + high) / 2
			if pivot < values[middle] { high = middle } else { low = middle + 1 }
		}
		for target := index; target > low; target-- { values[target] = values[target - 1] }
		values[low] = pivot
	}
}

fn merge_samples(mut values []f64) {
	mut scratch := []f64{len: values.len}
	mut width := 1
	for width < values.len {
		for start := 0; start < values.len; start += 2 * width {
			middle := if start + width < values.len { start + width } else { values.len }
			end := if middle + width < values.len { middle + width } else { values.len }
			mut left := start
			mut right := middle
			for target in start .. end {
				if left < middle && (right == end || !(values[right] < values[left])) {
					scratch[target] = values[left]
					left++
				} else {
					scratch[target] = values[right]
					right++
				}
			}
		}
		for index in 0 .. values.len { values[index] = scratch[index] }
		width *= 2
	}
}

pub fn summarize(rows []map[string]Value) !string {
	mut groups := map[string]Group{}
	for row in rows {
		for key in ['scenario', 'variant'] { if key !in row { return error('KeyError: ' + key) } }
		scenario := string_value(value(row, 'scenario'))
		variant := string_value(value(row, 'variant'))
		key := json2.encode([scenario, variant])
		mut group := groups[key] or { Group{ scenario: scenario, variant: variant } }
		group.rows << row
		groups[key] = group
	}
	mut ordered := groups.values()
	ordered.sort_with_compare(fn (a &Group, b &Group) int {
		if a.scenario != b.scenario { return if a.scenario < b.scenario { -1 } else { 1 } }
		return if a.variant < b.variant {
			-1
		} else if a.variant == b.variant {
			0
		} else {
			1
		}
	})
	mut lines := [
		"median of each scenario's runs; cpu is % of one CPU, mb is megabytes",
		'scenario  variant   runs  ' + metrics.map(align(it, 14, true)).join('  '),
	]
	for group in ordered {
		mut medians := []string{}
		for key in metrics {
			mut values := []f64{}
			for row in group.rows {
				if key !in row { return error('KeyError: ' + key) }
				values << metric(value(row, key))!
			}
			sort_samples(mut values)
			middle := values.len / 2
			median := if values.len % 2 != 0 {
				values[middle]
			} else {
				(values[middle - 1] + values[middle]) / 2
			}
			medians << float_format(median, '%14.2f')
		}
		lines << align(group.scenario, 9, false) + ' ' + align(group.variant, 9, false) + ' ' + align(group.rows.len.str(), 4, true) + '  ' + medians.join('  ')
	}
	return lines.join('\n')
}

pub struct Output {
pub:
	verdict Verdict
	stdout  string
	stderr  string
	status  int
}

pub fn finish(transcript []u8, variants []string, selected []string, rounds int, json_path ?string, timed_out bool, exit_code ?Value) !Output {
	verdict := inspect(transcript, variants, selected, rounds, timed_out, exit_code)
	if path := json_path {
		os.write_file(path, encode(Value(verdict.rows.map(Value(it))), true) + '\n')!
	}
	mut results := []map[string]Value{}
	for row in verdict.rows { if 'report' !in row && valid_desktop_result(row)! { results << row } }
	mut output := ''
	if results.len != 0 { output += summarize(results)! + '\n' }
	for line in verdict.reports { output += line + '\n' }
	return Output{verdict, output, verdict.errors.map('ERROR: ' + it + '\n').join(''), if verdict.errors.len == 0 {
		0
	} else {
		1
	}}
}
