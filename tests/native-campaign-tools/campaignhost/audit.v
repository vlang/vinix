// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import comparecore
import guesthost
import json2
import os
import hosttest

pub struct AllocationReport {
pub:
	counts        map[string]int
	architectures []json2.Any
	warnings      []json2.Any
}

pub fn allocation_report(raw []u8) AllocationReport {
	contents := guesthost.replacement_text(raw)
	mut counts := map[string]int{}
	mut architectures := []json2.Any{}
	mut warnings := []json2.Any{}
	for line in comparecore.lines(contents) {
		if line.starts_with('NEW: ') { warnings << json2.Any(line) }
		for arch in ['aarch64', 'x86_64'] {
			if line.starts_with(arch + ': ') && line.len > arch.len + 2 {
				architectures << json2.Any([json2.Any(arch), json2.Any(line[arch.len + 2..])])
			}
		}
		filename_end := line.index(':') or { continue }
		name := line[..filename_end]
		if name.len <= 2 || !name.ends_with('.v') || name.contains(' ') { continue }
		tail := line[filename_end + 1..]
		row_end := tail.index(':') or { continue }
		row := tail[..row_end]
		column_end := tail[row_end + 1..].index(' ') or { continue }
		column := tail[row_end + 1..row_end + 1 + column_end]
		kind := tail[row_end + 2 + column_end..]
		if row == '' || column == '' || kind == '' || !row.bytes().all(it.is_digit()) || !column.bytes().all(it.is_digit()) {
			continue
		}
		counts[name + ' ' + kind]++
	}
	return AllocationReport{counts, architectures, warnings}
}

pub fn allocation_deltas(base map[string]int, candidate map[string]int) map[string]json2.Any {
	mut keys := base.keys()
	for key in candidate.keys() { if key !in base { keys << key } }
	keys.sort()
	mut result := map[string]json2.Any{}
	for key in keys {
		delta := (candidate[key] or { 0 }) - (base[key] or { 0 })
		if delta != 0 { result[key] = delta }
	}
	return result
}

fn allocation_total(values map[string]int) int {
	mut count := 0
	for _, value in values { count += value }
	return count
}

pub fn audit_final(context Context) !int {
	mut preparation := read_json(context.state + '/preparation.json')!
	compiler := preparation['compiler']!.str()
	mut results := map[string]json2.Any{}
	mut sets := map[string]map[string]int{}
	for kind in ['baseline', 'candidate'] {
		root := preparation[kind + '_tree']!.str()
		command := [hosttest.root() + '/tests/kernel-allocs/run.sh']
		before := digest(compiler)!
		mut env := os.environ()
		env['V'] = compiler
		env['VINIX_KERNEL_ALLOCS_ROOT'] = root
		status := if kind == 'baseline' {
			1
		} else {
			logged(command, context.state + '/' + kind + '.log', env, root, '')!
		}
		path := context.state + '/' + kind + '.log'
		report := allocation_report(os.read_bytes(path)!)
		after := digest(compiler)!
		if before != after || after != preparation['compiler_sha256']!.str() {
			return error('allocation audit compiler changed')
		}
		results[kind] = json2.Any({
			'command':                json2.Any(command.map(json2.Any(it)))
			'environment':            json2.Any({
				'V': json2.Any(compiler)
			})
			'exit_code':              json2.Any(status)
			'reported_architectures': json2.Any(report.architectures)
			'unique_reported_sites':  json2.Any(allocation_total(report.counts))
			'serial_sha256':          json2.Any(digest(path)!)
			'compiler_sha256':        json2.Any(after)
			'new_allowlist_warnings': json2.Any(report.warnings)
		})
		sets[kind] = report.counts
		println(kind + ' exit ' + status.str() + ' sites ' + allocation_total(report.counts).str())
		flush_stdout()
	}
	deltas := allocation_deltas(sets['baseline']!, sets['candidate']!)
	mut summary := preparation.clone()
	summary['results'] = results
	summary['path_kind_deltas'] = deltas.clone()
	summary['allocation_site_regression'] = deltas.values().any(it.int() > 0)
	summary['notes'] = 'The unchanged repository allowlist is evaluated literally. Baseline/candidate warning counts are additionally compared with line numbers ignored. Any V architecture compile error is retained in raw logs; no allowlist update or false PASS.'
	write_json(context.state + '/comparison.json', summary)!
	println(json2.encode({
		'deltas':                     json2.Any(deltas)
		'allocation_site_regression': summary['allocation_site_regression']!
	},
		prettify: true
	))
	return 0
}
