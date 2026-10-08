// SPDX-License-Identifier: GPL-2.0-or-later
module perfreport

import os
import json2

fn case_lines(variant string, scenario string, round int) []string {
	label := 'variant=${variant} scenario=${scenario} round=${round}'
	mut lines := []string{}
	match scenario {
		'ops' {
			for op in general_ops {
				lines << 'PERF-OPS ${label} op=${op} dir=/tmp count=200 bytes_per_op=0'
			}
			for directory in ['/tmp', '/root'] {
				for op in file_ops {
					lines << 'PERF-OPS ${label} op=${op} dir=${directory} count=200 bytes_per_op=0'
				}
			}
		}
		'churn' {
			for program in churn_programs {
				lines << 'PERF-CHURN ${label} program="${program}" runs=300 retained_kb=0 per_run_bytes=0'
			}
		}
		'wakeups' {
			for via in ['nanosleep', 'poll'] {
				lines << 'PERF-WAKEUPS ${label} via=${via} interval_ms=16 wakeups=100 per_second=62.5 cpu=0.10 us_per_wakeup=16'
			}
		}
		'cache' {
			lines << 'PERF-CACHE ${label} written_mb=32 used_mb=33 cached_kb=32768 slab_kb=1024'
		}
		else {
			processes := if scenario == 'workflows' {
				5
			} else if scenario in ['utilities', 'storage', 'productivity', 'tools'] {
				4
			} else {
				1
			}
			lines << 'PERF-RESULT ${label} seconds=1.0 processes=${processes} desktop_cpu=1.0 apps_cpu=0.0 total_cpu=1.0 desktop_mb=2.0 apps_mb=0.0 total_mb=2.0 system_used_mb=20.0 physical_mb=2.0'
		}
	}
	return lines
}

fn complete_lines(variants []string, selected []string, rounds int) []string {
	mut lines := []string{}
	for number in 1 .. rounds + 1 {
		for scenario in selected {
			for variant in variants { lines << case_lines(variant, scenario, number) }
		}
	}
	lines << done
	return lines
}

fn checked_verdict(lines []string, selected []string) Verdict {
	return inspect(lines.join('\n').bytes(), ['new'], selected, 1, false, none)
}

fn has_error(result Verdict, text string) bool { return result.errors.any(it.contains(text)) }

fn test_complete_all_scenarios_variants_and_rounds() {
	result := inspect(complete_lines(['before', 'after'], scenarios, 2).join('\n').bytes(), [
		'before',
		'after',
	], scenarios, 2, false, none)
	assert result.errors == []string{}
	assert result.rows.len == 208
	assert result.rows.filter('report' !in it).len == 36
}

fn test_native_utility_scenarios_require_three_client_processes() {
	shell := os.read_file(os.join_path(os.dir(@FILE), '../perf-init.sh'))!
	aliases := shell.all_after('if [ "$scenario" = tools ]; then').all_before('\n\tfi')
	launch := shell.all_after('\t\ttools)\n').all_before('\t\t\t;;')
	arguments := shell_split(launch)!
	for scenario in ['utilities', 'storage', 'productivity', 'tools'] {
		for processes in [0, 1, 3] {
			line := case_lines('new', scenario, 1)[0].replace('processes=4', 'processes=${processes}')
			assert has_error(checked_verdict([line, done], [scenario]), 'invalid desktop metrics')
		}
	}
	for executable in ['vinix-color-meter', 'vinix-calculator', 'vinix-notes'] {
		assert aliases.contains(executable)
	}
	assert aliases.contains('ln -sf vinix-desktop "/usr/bin/$app"')
	for title in ['Color Meter', 'Calculator', 'Notes'] {
		assert '--open=${title}' in arguments
	}
}

fn test_workflows_require_four_native_clients_and_cached_image_aliases() {
	for processes in [0, 1, 4, 5] {
		line := case_lines('new', 'workflows', 1)[0].replace('processes=5', 'processes=${processes}')
		result := checked_verdict([line, done], ['workflows'])
		assert (result.errors.len == 0) == (processes == 5)
		if processes < 5 {
			assert has_error(result, 'invalid desktop metrics')
		}
	}
	shell := os.read_file(os.join_path(os.dir(@FILE), '../perf-init.sh'))!
	aliases := shell.all_after('if [ "$scenario" = workflows ]; then').all_before('\n\tfi')
	for executable in ['vinix-dictionary', 'vinix-editor', 'vinix-calendar', 'vinix-files'] {
		assert aliases.contains(executable)
	}
	for text in ['ln -sf vinix-desktop "/usr/bin/$app"', '/usr/share/vinix/dictionary/dictionary.vnd',
		'/usr/share/vinix/dictionary/LICENSE.WordNet', 'PERF-ERROR'] {
		assert aliases.contains(text)
	}
	arguments := shell_split(shell.all_after('\t\tworkflows)\n').all_before('\t\t\t;;'))!
	for title in ['Dictionary', 'Text Editor', 'Calendar', 'Files'] {
		assert '--open=${title}' in arguments
	}
}

fn test_partial_ops_timeout_keeps_json_but_fails() {
	path := os.join_path(os.temp_dir(), 'vinix-perf-report-' + os.getpid().str())
	os.mkdir(path)!
	defer { os.rmdir_all(path) or { panic(err) } }
	report_path := os.join_path(path, 'report.json')
	absent := ?Value(none)
	output := finish(case_lines('new', 'ops', 1)[..2].join('\n').bytes(), ['new'], ['ops'], 1, report_path, true, absent)!
	rows := json2.decode[[]map[string]Value](os.read_file(report_path)!)!
	assert output.status == 1 && rows.len == 2
	assert string_value(value(rows[0], 'report')) == 'PERF-OPS'
	assert string_value(value(rows[0], 'op')) == 'stat'
	assert output.stderr.contains('timeout') && output.stderr.contains('DONE')
}

fn test_all_measurements_without_done_still_fail() {
	result := checked_verdict(case_lines('new', 'ops', 1), ['ops'])
	assert has_error(result, 'DONE') && !has_error(result, 'measurements missing')
}

fn test_done_after_overall_timeout_does_not_rescue_run() {
	result := inspect(complete_lines(['new'], ['cache'], 1).join('\n').bytes(), ['new'], ['cache'], 1, true, none)
	assert has_error(result, 'timeout')
}

fn test_error_or_panic_after_complete_results_fails() {
	for failure in ['*** Vinix KERNEL PANIC on CPU 2 ***', 'FATAL EXCEPTION',
		'PERF-ERROR variant=new scenario=cache round=1 cannot read sample'] {
		mut lines := complete_lines(['new'], ['cache'], 1)
		lines << failure
		result := checked_verdict(lines, ['cache'])
		assert result.rows.len == 1 && has_error(result, failure)
	}
}

fn test_nonzero_guest_exit_after_done_fails() {
	result := inspect(complete_lines(['new'], ['cache'], 1).join('\n').bytes(), ['new'], ['cache'], 1, false, Value(Number{'7'}))
	assert has_error(result, 'status 7')
}

struct MissingPlan {
	variants []string
	selected []string
	rounds   int
}

fn test_missing_variant_scenario_or_round() {
	for plan in [MissingPlan{['new', 'old'], ['cache'], 1}, MissingPlan{['new'], ['cache', 'idle'], 1},
		MissingPlan{['new'], ['cache'], 2}] {
		result := inspect(complete_lines(['new'], ['cache'], 1).join('\n').bytes(), plan.variants, plan.selected, plan.rounds, false, none)
		assert has_error(result, 'measurements missing')
	}
}

fn test_each_report_subcase_is_required() {
	for scenario in ['ops', 'churn', 'wakeups'] {
		mut lines := case_lines('new', scenario, 1)
		lines.delete_last()
		lines << done
		assert has_error(checked_verdict(lines, [scenario]), '1 of')
	}
}

fn test_duplicate_does_not_replace_missing_coverage() {
	for scenario in ['ops', 'churn', 'wakeups', 'idle'] {
		mut lines := case_lines('new', scenario, 1)
		first := lines[0]
		lines.delete_last()
		lines << [first, first, done]
		assert has_error(checked_verdict(lines, [scenario]), 'duplicate measurement')
	}
}

fn test_unrequested_identity_is_rejected() {
	for item in [['old', 'cache', '1'], ['new', 'idle', '1'], ['new', 'cache', '0'],
		['new', 'cache', '2']] {
		mut lines := complete_lines(['new'], ['cache'], 1)
		lines << case_lines(item[0], item[1], item[2].int())
		assert has_error(checked_verdict(lines, ['cache']), 'unexpected measurement')
	}
}

fn test_auxiliary_slab_site_and_meminfo_do_not_count_as_measurements() {
	auxiliary := [
		'PERF-SLAB variant=new scenario=churn round=1 program="/bin/true" class=64 objects=0 pages=0',
		'PERF-SITE variant=new scenario=ops round=1 op=stat dir=/tmp site=0 bytes=0',
		'PERF-MEMINFO variant=new scenario=cache round=1 Cached: 32768 kB',
	]
	mut lines := auxiliary.clone()
	lines << done
	result := checked_verdict(lines, ['churn', 'ops', 'cache'])
	assert result.errors.len != 0 && result.rows.len == 0
	mut complete := complete_lines(['new'], ['churn', 'ops', 'cache'], 1)
	complete << auxiliary
	complete << auxiliary
	assert checked_verdict(complete, ['churn', 'ops', 'cache']).errors.len == 0
}

fn test_invalid_metrics_or_fields_fail_without_losing_partial_json() {
	lines := [
		case_lines('new', 'idle', 1)[0].replace('desktop_cpu=1.0', 'desktop_cpu=nan'),
		case_lines('new', 'cache', 1)[0].replace('cached_kb=32768', 'cached_kb=unknown'),
		case_lines('new', 'ops', 1)[0].replace('count=200', 'count=2'),
		'PERF-CHURN variant=new scenario=churn round=1 program="unterminated',
		case_lines('new', 'cache', 1)[0] + ' round=2',
		case_lines('new', 'idle', 1)[0] + ' report=PERF-CACHE',
	]
	for line in lines {
		scenario := line.all_after('scenario=').all_before(' ')
		result := checked_verdict([line, done], [scenario])
		assert result.rows.len == 1
		assert has_error(result, 'invalid') || has_error(result, 'malformed')
	}
}

fn test_duplicate_or_quoted_done_is_not_completion() {
	for tail in [[done, done], ['an earlier log said ' + done]] {
		mut lines := case_lines('new', 'cache', 1)
		lines << tail
		assert has_error(checked_verdict(lines, ['cache']), 'DONE')
	}
}

fn test_desktop_sample_time_process_count_and_system_memory_must_be_valid() {
	original := case_lines('new', 'idle', 1)[0]
	for line in [original.replace('seconds=1.0', 'seconds=nan'),
		original.replace('seconds=1.0', 'seconds=0'),
		original.replace('processes=1', 'processes=garbage'),
		original.replace('processes=1', 'processes=-1'), original.replace(' system_used_mb=20.0', '')] {
		result := checked_verdict([line, done], ['idle'])
		assert result.rows.len == 1 && has_error(result, 'invalid desktop metrics')
	}
}

fn test_expected_ops_match_actual_guest_workload() {
	source := os.read_file(os.join_path(os.dir(@FILE), '../measure.c'))!
	for index, table in ['table', 'files'] {
		body := source.all_after('static const struct op ${table}[] = {').all_before('};')
		mut actual := []string{}
		for piece in body.split('{"')[1..] { actual << piece.all_before('"') }
		assert actual == if index == 0 { general_ops } else { file_ops }
	}
	shell := os.read_file(os.join_path(os.dir(@FILE), '../perf-init.sh'))!
	for program in churn_programs {
		assert shell.contains(program)
	}
	assert expected(['new'], ['ops'], 1).len == 36
}

fn test_numeric_decimal_separators_and_unicode_digits() {
	mut row := map[string]Value{}
	for key in [...metrics, 'system_used_mb', 'seconds', 'processes'] { row[key] = '1' }
	for field in ['seconds', 'processes'] {
		for text in ['1__0', '_1', '1_', '0x1p2', '1e_2'] {
			row[field] = text
			assert !valid_desktop_result(row)!
		}
		for text in ['٣', '１２', '१_२', ' 1 ', '\u00a01\u00a0'] {
			row[field] = text
			assert valid_desktop_result(row)!
		}
		row[field] = '1'
	}
}

fn test_regex_search_retries_invalid_markers() {
	valid := case_lines('new', 'cache', 1)[0]
	line := 'PERF-CACHE variant= scenario=cache round=1 x=1 ' + valid
	verdict := checked_verdict([line, done], ['cache'])
	assert verdict.rows.len == 1 && verdict.errors.len == 0
}

fn test_unprintable_identity_diagnostic_and_wide_exit() {
	line := case_lines('new', 'cache', 1)[0].replace('variant=new', 'variant=\u200b')
	code := Value(Number{'1267650600228229401496703205376'})
	result := inspect([line, done].join('\n').bytes(), ['new'], ['cache'], 1, false, code)
	assert result.errors[0] == "unexpected measurement: ('\\u200b', 'cache', 1, 'PERF-CACHE')"
	assert has_error(result, 'status 1267650600228229401496703205376')
}

fn test_detail_preserves_values_at_the_import_boundary() {
	row := map[string]Value{
		'report': Value('PERF-OPS')
		'op':     Value(Number{'1267650600228229401496703205376'})
		'dir':    Value(false)
	}
	assert encode(detail_values(row), false) == '["PERF-OPS",1267650600228229401496703205376,false]'
}

fn test_summary_zero_ties_are_stable_in_large_batches() {
	mut rows := []map[string]Value{}
	for index in 0 .. 128 {
		mut row := map[string]Value{
			'scenario': Value('idle')
			'variant':  Value('new')
		}
		for key in metrics { row[key] = if index % 2 == 0 { Value('-0.0') } else { Value('0.0') } }
		rows << row
	}
	result := summarize(rows)!
	assert result.contains('idle      new        128            0.00')
	assert !result.contains('-0.00')
}

fn test_literal_transport_marker_dictionaries_remain_dictionaries() {
	wire := Value(map[string]Value{
		'$escaped_map': Value(map[string]Value{
			'$nonfinite_number': Value('inf')
		})
	})
	assert encode(from_wire(wire), false) == '{"$nonfinite_number":"inf"}'
	nested := Value(map[string]Value{
		'$escaped_map': Value(map[string]Value{
			'$escaped_map': wire
		})
	})
	assert encode(from_wire(nested), false) == '{"$escaped_map":{"$nonfinite_number":"inf"}}'
}
