// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import comparecore
import guesthost
import hosttest
import json2
import os
import strconv

struct HotBatch {
pub mut:
	invocation i64
	linkage string
	phase string
	rows []json2.Any
}

fn fields(line string) !map[string]json2.Any {
	mut result := map[string]json2.Any{}
	for item in line.fields()[1..] {
		index := item.index('=') or { return error('diagnostic field lacks =') }
		result[item[..index]] = item[index + 1..]
	}
	return result
}

fn integer_field(row map[string]json2.Any, key string) !i64 {
	value := row[key] or { return error('diagnostic field missing: ' + key) }
	return strconv.parse_int(value.str(), 10, 64)!
}

fn median(values []f64) !f64 {
	if values.len == 0 { return error('empty diagnostic sample set') }
	mut sorted := values.clone()
	sorted.sort()
	return if sorted.len & 1 == 1 { sorted[sorted.len / 2] } else { (sorted[sorted.len / 2 - 1] + sorted[sorted.len / 2]) / 2 }
}

pub fn diagnostic_report(serials [][]u8, serial_hashes []string, config_hashes []string) !map[string]json2.Any {
	if serials.len != 2 || serial_hashes.len != 2 || config_hashes.len != 2 { return error('diagnostic requires two boots') }
	mut records := []json2.Any{}
	mut state_rows := []json2.Any{}
	mut probe_rows := []json2.Any{}
	mut boot_records := []json2.Any{}
	mut all_deltas := []f64{}
	mut all_ratios := []f64{}
	for index, raw in serials {
		ordinal := u64(index + 1)
		output := guesthost.replacement_text(raw).replace('\r\n', '\n').replace('\r', '\n')
		if output.count('DIAG-GUEST-BEGIN') != 1 || output.count('DIAG-GUEST-DONE') != 1 || output.count('DIAG-SAMPLER-DONE') != 6 || output.count('DIAG-HOT ') != 84 || ['DIAG-FAIL', 'ALLOC-ERROR', 'KERNEL PANIC', 'FATAL EXCEPTION'].any(output.contains(it)) {
			return error('incomplete or failed private diagnostic boot')
		}
		mut invocation := i64(0)
		mut linkage := ''
		mut starts := []string{}
		mut ends := []string{}
		mut batches := []HotBatch{}
		for line in comparecore.lines(output) {
			if line.starts_with('DIAG-EXEC-BEGIN ') {
				row := fields(line)!
				invocation = integer_field(row, 'invocation')!
				linkage = row['linkage']!.str()
				starts << invocation.str() + ' ' + linkage
			} else if line.starts_with('DIAG-EXEC-END ') {
				row := fields(line)!
				if integer_field(row, 'exit_code')! != 0 { return error('diagnostic executable failed') }
				ends << integer_field(row, 'invocation')!.str() + ' ' + row['linkage']!.str()
			} else if line.starts_with('DIAG-HOT ') {
				row := fields(line)!
				if integer_field(row, 'pairs')! != 200000 || integer_field(row, 'checksum')! != 51000000 { return error('diagnostic workload or checksum differs') }
				phase := row['phase']!.str()
				mut position := -1
				for i, batch in batches { if batch.invocation == invocation && batch.linkage == linkage && batch.phase == phase { position = i; break } }
				if position < 0 {
					batches << HotBatch{invocation: invocation, linkage: linkage, phase: phase}
					position = batches.len - 1
				}
				batches[position].rows << json2.Any(row)
			} else if line.starts_with('DIAG-STATE ') || line.starts_with('DIAG-PROBE ') {
				mut row := fields(line)!
				row['boot'] = ordinal
				row['invocation'] = if invocation == 0 { json2.Any(json2.Null{}) } else { json2.Any(invocation) }
				row['linkage'] = nullable(linkage)
				if line.starts_with('DIAG-STATE ') { state_rows << json2.Any(row.clone()) } else { probe_rows << json2.Any(row.clone()) }
			}
		}
		expected := ['1 dynamic', '1 static', '2 dynamic', '2 static', '3 dynamic', '3 static']
		if starts != expected || ends != expected || batches.len != 12 { return error('diagnostic fresh execution coverage differs') }
		for batch in batches {
			if batch.rows.len != 7 { return error('diagnostic batch must retain seven samples') }
			mut ns := []f64{}
			mut delta := []f64{}
			mut ratio := []f64{}
			for sample, value in batch.rows {
				row := value.as_map()
				if integer_field(row, 'sample')! != sample + 1 { return error('diagnostic sample order differs') }
				elapsed := integer_field(row, 'elapsed_ns')!
				cpu := integer_field(row, 'cpu_ns')!
				if elapsed == 0 { return error('diagnostic sample has zero elapsed time') }
				ns << f64(elapsed) / 200000
				delta << f64(cpu - elapsed)
				ratio << f64(cpu) / f64(elapsed)
			}
			all_deltas << delta
			all_ratios << ratio
			records << json2.Any({
				'boot': json2.Any(ordinal)
				'invocation': json2.Any(batch.invocation)
				'linkage': json2.Any(batch.linkage)
				'phase': json2.Any(batch.phase)
				'samples': json2.Any(batch.rows)
				'median_ns_per_pair': json2.Any(median(ns)!)
				'min_ns_per_pair': json2.Any(minimum(ns)!)
				'max_ns_per_pair': json2.Any(maximum(ns)!)
				'median_cpu_minus_wall_ns': json2.Any(median(delta)!)
				'min_cpu_to_wall_ratio': json2.Any(minimum(ratio)!)
				'max_cpu_to_wall_ratio': json2.Any(maximum(ratio)!)
			})
		}
		boot_records << json2.Any({'boot': json2.Any(ordinal), 'serial_sha256': json2.Any(serial_hashes[index]), 'config_sha256': json2.Any(config_hashes[index])})
	}
	for value in state_rows {
		row := value.as_map()
		if row['phase']!.str() == 'after-metadata' {
			if row['group']!.str() != 'none' || row['need_locks']!.str() != '0' || row['lock']!.str() != '0' { return error('metadata-only diagnostic state differs') }
			continue
		}
		for key, expected in {'class': 4, 'slots': 8, 'maplen': 0, 'nested': 1, 'sole': 1, 'group_count': 1, 'active_idx': 7, 'stride': 80, 'full_stride': 1, 'usage': 8, 'need_locks': 0, 'lock': 0, 'mem_page_offset': 16, 'meta_cacheline_offset': 24} {
			if integer_field(row, key)! != expected { return error('diagnostic state differs: ' + key) }
		}
		avail := integer_field(row, 'avail')!
		freed := integer_field(row, 'freed')!
		if (avail | freed) != 255 || (avail & freed) != 0 { return error('diagnostic state masks overlap or omit slots') }
	}
	for value in probe_rows {
		row := value.as_map()
		for key in ['pairs', 'class4', 'sole', 'nested', 'full_stride', 'eligible', 'lock_zero', 'need_zero'] { if integer_field(row, key)! != 32 { return error('diagnostic probe differs: ' + key) } }
		for key in ['need_negative', 'group_changes', 'offset_min'] { if integer_field(row, key)! != 0 { return error('diagnostic probe differs: ' + key) } }
		if row['slots']!.str() != '0:4,1:4,2:4,3:4,4:4,5:4,6:4,7:4,' || integer_field(row, 'offset_max')! != 35 || integer_field(row, 'reserved_min')! != 5 || integer_field(row, 'reserved_max')! != 5 { return error('diagnostic probe rotation differs') }
	}
	mut report := hosttest.decode_json($embed_file('hot-template.json').to_string())!.as_map().clone()
	report['boots'] = boot_records
	report['cpu_accounting'] = {
		'median_cpu_minus_wall_ns': json2.Any(median(all_deltas)!)
		'min_cpu_minus_wall_ns': json2.Any(minimum(all_deltas)!)
		'max_cpu_minus_wall_ns': json2.Any(maximum(all_deltas)!)
		'min_cpu_to_wall_ratio': json2.Any(minimum(all_ratios)!)
		'max_cpu_to_wall_ratio': json2.Any(maximum(all_ratios)!)
	}
	report['state_rows'] = state_rows
	report['probe_rows'] = probe_rows
	report['sample_batches'] = records
	return report
}

fn minimum(values []f64) !f64 {
	if values.len == 0 { return error('empty diagnostic sample set') }
	mut value := values[0]
	for next in values[1..] { if next < value { value = next } }
	return value
}

fn maximum(values []f64) !f64 {
	if values.len == 0 { return error('empty diagnostic sample set') }
	mut value := values[0]
	for next in values[1..] { if next > value { value = next } }
	return value
}

pub fn summarize_diagnostic(context Context) !int {
	mut serials := [][]u8{}
	mut serial_hashes := []string{}
	mut config_hashes := []string{}
	for ordinal in [1, 2] {
		base := context.state + '/boot-' + ordinal.str()
		serials << os.read_bytes(base + '/serial.log')!
		serial_hashes << digest(base + '/serial.log')!
		config_hashes << digest(base + '/config.json')!
	}
	report := diagnostic_report(serials, serial_hashes, config_hashes)!
	write_json(context.state + '/summary.json', report)!
	mut summary := report.clone()
	for key in ['state_rows', 'probe_rows', 'sample_batches'] { summary.delete(key) }
	println(json2.encode(summary, prettify: true))
	return 0
}
