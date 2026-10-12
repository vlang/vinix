// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import crypto.sha256
import json2
import os
import sourcecommand

pub struct Case {
pub:
	name  string
	args  []string
	mode  string = 'none'
	index int    = 1
}

pub fn benchmark_cases() []Case {
	mut cases := []Case{}
	for pair in [[1, 5], [63, 6], [64, 5], [65, 6], [257, 31], [2000, 5]] {
		cases << Case{'success-' + pair[0].str() + '-' + pair[1].str(), ['--iterations', pair[0].str(),
			'--samples', pair[1].str(), '--label', 'a_Z-0.1'], 'none', 1}
	}
	for entry in [['ordered', '--quick', '--iterations', '65', '--samples', '6'], ['help', '--help'],
		['help_after_quick', '--quick', '--help']] {
		cases << Case{entry[0], entry[1..], 'none', 1}
	}
	mut invalid := [['--unknown'], ['--unknown', 'value'], ['--samples'], ['--iterations'],
		['--label']]
	for value in ['', '0', '-1', '+1', ' 1', '1x', '1000000001', '18446744073709551616'] {
		invalid << ['--iterations', value]
	}
	for value in ['', '4', '32', '6x', '18446744073709551616'] {
		invalid << ['--samples', value]
	}
	for value in ['', 'a'.repeat(65), 'a b', 'a=b', '\u00ff'] { invalid << ['--label', value] }
	for index, args in invalid { cases << Case{'invalid-' + index.str(), args, 'none', 1} }
	base := ['--iterations', '65', '--samples', '6']
	mut malloc_positions := [1, 2, 65, 66, 130, 455]
	for index in 456 .. 520 { malloc_positions << index }
	malloc_positions << [520, 521, 910, 911, 912, 914, 915]
	for index in malloc_positions { cases << Case{'malloc-' + index.str(), base, 'malloc', index} }
	modes := ['mmap', 'munmap', 'pipe', 'close', 'clock', 'close_both', 'constant_clock', 'uname',
		'resolution', 'pagesize']
	positions := [[1, 2, 28, 29, 30], [1, 28, 29], [1, 2, 5], [1, 2, 3, 4], [1, 2, 3, 13, 24, 36,
		72], [1], [1], [1], [1], [1]]
	for i, mode in modes {
		for index in positions[i] { cases << Case{mode + '-' + index.str(), base, mode, index} }
	}
	return cases
}

pub fn invoke_benchmark(executable string, args []string, mode string, index int) !sourcecommand.Output {
	mut env := environment()
	env['VAB_FAIL'] = mode
	env['VAB_FAIL_INDEX'] = index.str()
	return capture([executable, ...args], env, 180)!
}

pub fn normalize(contents string, help_text bool) string {
	mut result := contents
	for pair in [
		['Usage: ', 'Usage: PROGRAM [--iterations N] [--samples N] [--quick] [--label NAME]'],
		['Build: ', 'Build: generated benchmark'],
	] {
		if pair[0] == 'Build: ' && !help_text { continue }
		mut start := 0
		for start < result.len {
			offset := result[start..].index(pair[0]) or { break }
			position := start + offset
			end := position + (result[position..].index('\n') or { result.len - position })
			result = result[..position] + pair[1] + result[end..]
			start = position + pair[1].len
		}
	}
	return result
}

pub fn compare_benchmark(translated string, original string, work string) ! {
	mut proofs := []json2.Any{}
	cases := benchmark_cases()
	for record in cases {
		c := invoke_benchmark(original, record.args, record.mode, record.index)!
		v := invoke_benchmark(translated, record.args, record.mode, record.index)!
		help := record.name.starts_with('help')
		c_out := normalize(c.stdout, help)
		v_out := normalize(v.stdout, help)
		if v.status != c.status || v_out != c_out || v.stderr != c.stderr {
			return error('C/V differential mismatch ' + record.name + '\n' + c.str() + '\n' + v.str())
		}
		if !clean_diagnostics(v.stderr + c.stderr) {
			return error('sanitizer diagnostics in ' + record.name)
		}
		if record.name.starts_with('success') || record.name == 'ordered' {
			if v.status != 0 || !v_out.contains('ALLOC-DONE') || v_out.split_into_lines().filter(it.starts_with('ALLOC-RESULT ')).len != 6 {
				return error('benchmark success oracle failed: ' + record.name)
			}
		} else if record.name.starts_with('invalid') {
			if v.status != 2 { return error('invalid argument oracle failed: ' + record.name) }
		} else if !help && (v.status != 1 || !v.stderr.contains('ALLOC-ERROR')) {
			return error('fault oracle failed: ' + record.name)
		}
		os.write_file(work + '/' + record.name + '.stdout', v_out)!
		os.write_file(work + '/' + record.name + '.stderr', v.stderr)!
		proofs << json2.Any({
			'case':          json2.Any(record.name)
			'argv':          json2.Any(record.args.map(json2.Any(it)))
			'fault':         json2.Any(record.mode)
			'index':         json2.Any(record.index)
			'returncode':    json2.Any(v.status)
			'stdout_sha256': json2.Any(sha256.sum(v_out.bytes()).hex())
			'stderr_sha256': json2.Any(sha256.sum(v.stderr.bytes()).hex())
		})
	}
	write_json(work + '/differential.json', proofs)!
	println('Portable allocation benchmark: ' + cases.len.str() + ' C/V differential cases passed, including all 64 mixed-batch OOM prefixes')
}
