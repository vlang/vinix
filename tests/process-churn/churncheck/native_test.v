// SPDX-License-Identifier: GPL-2.0-or-later
module churncheck

import hosttest
import os

fn fixture(mode string) string {
	names := match mode {
		'exec' { ['true', 'sleep', 'curl', 'awk'] }
		'slabinfo' { ['slabinfo'] }
		'waits' { ['idle_control', 'nanosleep', 'clock_nanosleep', 'fork_reap'] }
		'directories' { ['mkdir_tmpfs', 'mkdir_ext2'] }
		'pipes' { ['pipe'] }
		'sampling' { ['sampling'] }
		else { ['select_ready', 'pselect_ready'] }
	}
	mut result := 'guest console noise\nPROCESS CHURN: START\n'
	if mode == 'directories' {
		result += 'CHURN FILESYSTEM program=mkdir_tmpfs type=1021994\nCHURN FILESYSTEM program=mkdir_ext2 type=0xef53\n'
	}
	for name in names {
		result += 'CHURN GRACE program=${name} cohort=0 elapsed_ns=6100000000\n'
		for cohort in 1 .. 4 {
			result += 'CHURN GRACE program=${name} cohort=${cohort} elapsed_ns=6100000000\n'
			result += 'CHURN MEASURE program=${name} cohort=${cohort} runs=${if mode == 'directories' {
				200
			} else {
				300
			}} used_delta_kib=-7 cumulative_used_kib=99 slab_delta_kib=0 cumulative_slab_kib=3 cached_delta_kib=18 large_pages_delta=0\n'
			result += 'PERF-SITE program=${name} cohort=${cohort} count=2 size=64 0xffff 0xfaaa\n'
			result += 'PERF-SITE program=${name} cohort=${cohort} live 2 dropped 0\n'
			if mode == 'waits' {
				result += 'CHURN WORK program=${name} cohort=${cohort} calls=300 elapsed_ns=400000000\n'
			}
		}
	}
	if mode == 'waits' { result += 'CHURN SEMANTICS: fork executable path preserved\n' }
	if mode == 'select' {
		result += 'CHURN SEMANTICS: pselect pointers, masks, timeout, interruption, wake\n'
	}
	return result + 'PROCESS CHURN: DONE failures=0\n'
}

fn failure(source string, mode string, slab bool, small bool, message string) {
	inspect(source, mode, slab, small) or {
		assert err.msg() == message
		return
	}
	assert false, 'accepted invalid ${mode} report: ${message}'
}

fn remove_line(source string, prefix string) string {
	return source.split('\n').filter(!it.starts_with(prefix)).join('\n')
}

fn test_all_modes_output_order_numeric_canonicalization_and_unrelated_growth() {
	for mode, count in {
		'exec':        12
		'slabinfo':    3
		'waits':       12
		'directories': 6
		'pipes':       3
		'sampling':    3
		'select':      6
	} {
		for separator in ['\n', '\r\n', '\r', '\v', '\f', '\x1c', '\x1d', '\x1e', '\u0085', '\u2028',
			'\u2029'] {
			source := '\u3000' + fixture(mode).replace('\n', separator + '\u2003')
			report := inspect(source, mode, mode == 'slabinfo', mode in ['waits', 'select'])!
			assert report.measurements.len == count && report.live.len == count
			output := report.output(mode == 'slabinfo')
			assert output.count('\n') == count + 1
			assert output.contains('cohort=1: used=-7 KiB, slab=0 KiB, tracked_live=2\n')
		}
	}
	// Reports follow the first-seen measurement order, rather than sorting keys.
	source := fixture('pipes').split('\n').reverse().join('\n')
	output := inspect(source, 'pipes', false, false)!.output(false)
	assert output.starts_with('pipe cohort=3: used=-7 KiB, slab=0 KiB, tracked_live=2\n')
	huge := '1234567890'.repeat(100)
	large := fixture('pipes').replace('used_delta_kib=-7', 'used_delta_kib=-${huge}').replace('live 2 dropped 0', 'live ${huge} dropped ٠')
	assert inspect(large, 'pipes', false, false)!.output(false).contains('used=-${huge} KiB, slab=0 KiB, tracked_live=${huge}')
	canonical := fixture('pipes').replace('cohort=1', 'cohort=٠١').replace('runs=300', 'runs=+3_00')
	assert inspect(canonical, 'pipes', false, false)!.output(false) == inspect(fixture('pipes'), 'pipes', false, false)!.output(false)
}

fn test_fields_integer_grammar_unicode_and_replacement_decoding() {
	assert fields('prefix :猫٢=value a=1,b=2 blank= trailing')! == {
		'猫٢': 'value'
		'a':   '1,b=2'
	}
	assert fields('combining e\u0301x=1 sup²=2')! == {
		'x':    '1'
		'sup²': '2'
	}
	for separator in [' ', '\t', '\x1f', '\u0085', '\u00a0', '\u2003', '\u3000'] {
		assert fields('a=1${separator}b=2')! == {
			'a': '1'
			'b': '2'
		}
	}
	mut refused := false
	fields('a=1 a=2') or {
		assert err.msg() == 'duplicate a: a=1 a=2'
		refused = true
	}
	assert refused, 'accepted duplicate fields'
	for input, expected in {
		'٠١٢':     '12'
		'-００７': '-7'
		'+1_000':  '1000'
		'-0':      '0'
		'0000':    '0'
	} {
		assert integer(input, 10)!.str() == expected
	}
	for input, expected in {
		'0x_Ff':     '255'
		'+０Xef_53': '61267'
		'-0x00':     '0'
		'1021994':   '16914836'
	} {
		assert integer(input, 16)!.str() == expected
	}
	for input in ['', '+', '-', '_1', '1_', '1__0', '²', '1.0', '0x10', '١__٢'] {
		integer(input, 10) or {
			assert err.msg() == 'invalid literal for int() with base 10: ${quoted(input)}'
			continue
		}
		assert false, 'accepted invalid decimal ${input}'
	}
	for input in ['0x', '0x_', '0x__ff', '0xfg', '--ff'] {
		integer(input, 16) or { continue }
		assert false, 'accepted invalid hexadecimal ${input}'
	}
	for zero in decimal_zeros {
		assert integer((rune(zero + 3)).str(), 10)!.str() == '3'
	}
	for raw, expected in {
		'\xff':             '�'
		'\xe2\x82':         '�'
		'\xe2\x82a':        '�a'
		'\xed\xa0\x80':     '���'
		'\xe0\x80\x80':     '���'
		'\xf4\x90\x80\x80': '����'
		'\xf0\x9f\x92':     '�'
		'猫💩\r\nx\ry':     '猫💩\nx\ny'
	} {
		assert log_text(raw) == expected
	}
	assert inspect('\xff\xe2\x82\n' + fixture('pipes'), 'pipes', false, false)!.measurements.len == 3
}

fn test_coverage_failure_markers_duplicates_grace_and_tracking() {
	source := fixture('pipes')
	for marker in ['PROCESS CHURN: FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'ERROR:'] {
		failure('noise ${marker} details\n' + source, 'pipes', false, false, 'noise ${marker} details')
	}
	failure(source.replace('PROCESS CHURN: START', ''), 'pipes', false, false, 'expected one START/DONE, got 0/1')
	failure(source + 'PROCESS CHURN: START\n', 'pipes', false, false, 'expected one START/DONE, got 2/1')
	failure(source.replace('DONE failures=0', 'DONE failures=1'), 'pipes', false, false, 'expected one START/DONE, got 1/0')
	for prefix in ['CHURN MEASURE program=pipe cohort=2 ', 'CHURN GRACE program=pipe cohort=0 ',
		'PERF-SITE program=pipe cohort=3 live '] {
		failure(remove_line(source, prefix), 'pipes', false, false, 'incomplete or unexpected measurement/grace/allocation coverage')
	}
	for prefix, diagnostic in {
		'CHURN MEASURE ': 'duplicate measurement'
		'CHURN GRACE ':   'duplicate grace'
		'PERF-SITE ':     'duplicate allocation summary'
	} {
		line := source.split('\n').filter(it.starts_with(prefix) && it.contains('cohort=1') && (prefix != 'PERF-SITE ' || it.contains(' live ')))[0]
		failure(source + line + '\n', 'pipes', false, false, "${diagnostic}: ('pipe', 1)")
	}
	failure(source.replace('runs=300', 'runs=299'), 'pipes', false, false, "wrong cohort size: ('pipe', 1)")
	failure(source.replace('elapsed_ns=6100000000', 'elapsed_ns=5999999999'), 'pipes', false, false, "short grace: ('pipe', 0): 5999999999")
	assert inspect(source.replace('elapsed_ns=6100000000', 'elapsed_ns=6000000000'), 'pipes', false, false)!.measurements.len == 3
	failure(source.replace('dropped 0', 'dropped 1'), 'pipes', false, false, "tracking overflow: ('pipe', 1)")
	failure(source.replace('program=pipe', 'program=other'), 'pipes', false, false, "unexpected program: ('other', 0)")
	failure(source + 'CHURN MEASURE program=pipe cohort=4 runs=300\n', 'pipes', false, false, "'used_delta_kib'")
	for key in measurement_fields {
		failure(source.replace('${key}=', 'missing_${key}='), 'pipes', false, false, "'${key}'")
	}
	for tail in ['live -2 dropped 0', 'live 2 dropped -1', 'live 2_0 dropped 0',
		'live 2 dropped 0 extra'] {
		failure(source.replace('live 2 dropped 0', tail), 'pipes', false, false, 'incomplete or unexpected measurement/grace/allocation coverage')
	}
	failure(source + 'CHURN CLASS program=pipe cohort=0 size=16 objects_delta=0\n', 'pipes', false, false, 'class report outside measured cohorts')
	failure(source + 'CHURN CLASS program=pipe cohort=1 size=0 objects_delta=0\n', 'pipes', false, false, "invalid class: ('pipe', 1, 0)")
	class := 'CHURN CLASS program=pipe cohort=1 size=16 objects_delta=0\n'
	failure(source + class + class, 'pipes', false, false, "invalid class: ('pipe', 1, 16)")
}

fn test_timed_work_and_filesystem_identity() {
	waits := fixture('waits')
	failure(remove_line(waits, 'CHURN WORK program=fork_reap cohort=3 '), 'waits', false, false, 'missing timed-workload coverage')
	failure(waits.replace('elapsed_ns=400000000', 'elapsed_ns=299999999'), 'waits', false, false, '300 one-millisecond sleeps consumed less than 300 ms')
	assert inspect(waits.replace('elapsed_ns=400000000', 'elapsed_ns=300000000'), 'waits', false, false)!.measurements.len == 12
	for before, after in {
		'calls=300':            'calls=299'
		'elapsed_ns=400000000': 'elapsed_ns=-1'
	} {
		failure(waits.replace(before, after), 'waits', false, false, "invalid workload evidence: ('idle_control', 1)")
	}
	work := 'CHURN WORK program=idle_control cohort=1 calls=300 elapsed_ns=400000000\n'
	failure(waits + work, 'waits', false, false, "duplicate workload evidence: ('idle_control', 1)")
	failure(fixture('pipes') + work.replace('idle_control', 'pipe'), 'pipes', false, false, 'unexpected timed-workload report')
	directories := fixture('directories')
	for changed in [directories.replace('type=0xef53', 'type=0xef54'),
		remove_line(directories, 'CHURN FILESYSTEM program=mkdir_tmpfs ')] {
		failure(changed, 'directories', false, false, 'missing or incorrect tmpfs/ext2 identity')
	}
	failure(directories + 'CHURN FILESYSTEM program=mkdir_ext2 type=0xef53\n', 'directories', false, false, 'duplicate filesystem evidence')
	failure(fixture('pipes') + 'CHURN FILESYSTEM program=pipe type=0xef53\n', 'pipes', false, false, 'unexpected filesystem report')
}

fn test_flat_checks_preserve_exact_size_thresholds_and_semantics() {
	slab := fixture('slabinfo')
	for delta in ['1', '-1', '999999999999999999999999999999999'] {
		failure(slab + 'CHURN CLASS program=slabinfo cohort=2 size=48 objects_delta=${delta}\n', 'slabinfo', true, false, 'slabinfo retains 48-byte descriptors in cohort 2')
	}
	assert inspect(slab + 'CHURN CLASS program=slabinfo cohort=2 size=48 objects_delta=0\n', 'slabinfo', true, false)!.measurements.len == 3
	for field in ['slab_delta_kib', 'large_pages_delta'] {
		failure(slab.replace('${field}=0', '${field}=1'), 'slabinfo', true, false, 'last slabinfo cohort has not settled')
	}
	failure(fixture('pipes'), 'pipes', true, false, 'flat slabinfo check requires --mode slabinfo')
	failure(slab, 'slabinfo', false, true, 'small-object check requires --mode waits or select')
	for mode, name in {
		'waits':  'fork_reap'
		'select': 'select_ready'
	} {
		source := fixture(mode)
		for cohort in 1 .. 4 {
			maximum := if cohort == 1 { 2 } else { 0 }
			for allowed in [maximum.str(), '-99'] {
				assert inspect(source + 'CHURN CLASS program=${name} cohort=${cohort} size=16 objects_delta=${allowed}\n', mode, false, true)!.measurements.len > 0
			}
			failure(source + 'CHURN CLASS program=${name} cohort=${cohort} size=16 objects_delta=${maximum + 1}\n', mode, false, true, '16-byte operation objects do not settle: ${name}/${cohort}')
		}
		marker := source.split('\n').filter(it.starts_with('CHURN SEMANTICS:'))[0]
		failure(source + marker + '\n', mode, false, true, 'missing or duplicate lifetime/ABI semantics evidence')
		failure(source.replace(marker, ''), mode, false, true, 'missing or duplicate lifetime/ABI semantics evidence')
		assert inspect(source + 'CHURN CLASS program=${name} cohort=2 size=32 objects_delta=999\n', mode, false, true)!.measurements.len > 0
	}
	assert inspect(fixture('waits') + 'CHURN CLASS program=nanosleep cohort=2 size=16 objects_delta=999\n', 'waits', false, true)!.measurements.len == 12
}

fn test_native_cli_modes_options_error_streams_and_no_partial_reports() {
	tool := os.getenv('VINIX_CHURN_CHECK_TOOL')
	if tool == '' { return }
	work := hosttest.work_dir('', 'vinix-churn-check-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	path := work + '/guest log.txt'
	for mode in modes {
		os.write_file(path, fixture(mode))!
		artifacts := os.getenv('VINIX_CHURN_FIXTURE_DIR')
		if artifacts != '' {
			os.mkdir_all(artifacts)!
			os.write_file(artifacts + '/' + mode + '.log', fixture(mode))!
			os.write_file(artifacts + '/' + mode + '.expected', inspect(fixture(mode), mode, mode == 'slabinfo', mode in [
				'waits',
				'select',
			])!.output(mode == 'slabinfo'))!
		}
		mut argv := [tool, path, '--mode=' + mode]
		if mode == 'slabinfo' { argv << '--expect-flat-slabinfo' }
		if mode in ['waits', 'select'] { argv << '--expect-flat-small' }
		result := hosttest.capture(argv, '', 30, os.environ())!
		assert result.code == 0 && result.stderr == ''
		assert result.stdout == inspect(fixture(mode), mode, mode == 'slabinfo', mode in [
			'waits',
			'select',
		])!.output(mode == 'slabinfo')
	}
	os.write_file(path, fixture('pipes'))!
	for argv in [['--mo', 'pipes', '--', path], [path, '--mode', 'exec', '--mode', 'pipes']] {
		mut command := [tool]
		command << argv
		assert hosttest.capture(command, '', 30, os.environ())!.code == 0
	}
	for argv in [[]string{}, ['--unknown'], [path, '--mode', 'bad'], [path, '--mode'],
		[path, '--expect-flat'], [path, '--expect-flat-small=yes'], [path, path]] {
		mut command := [tool]
		command << argv
		result := hosttest.capture(command, '', 30, os.environ())!
		assert result.code == 2 && result.stdout == '' && result.stderr != ''
	}
	assert hosttest.capture([tool, '--help'], '', 30, os.environ())!.code == 0
	missing := hosttest.capture([tool, path + '.missing'], '', 30, os.environ())!
	assert missing.code == 1 && missing.stdout == '' && missing.stderr.starts_with('FAIL:')
	os.write_file(path, fixture('pipes').replace('dropped 0', 'dropped 1'))!
	bad := hosttest.capture([tool, path, '--mode=pipes'], '', 30, os.environ())!
	assert bad.code == 1 && bad.stdout == '' && bad.stderr == "FAIL: tracking overflow: ('pipe', 1)\n"
	os.write_file(path, '\xff\xed\xa0\x80\n' + fixture('pipes'))!
	assert hosttest.capture([tool, path, '--mode=pipes'], '', 30, os.environ())!.code == 0
	assert os.ls(work)! == ['guest log.txt']
}

fn test_integer_aliases_do_not_bypass_duplicate_or_class_coverage() {
	source := fixture('pipes')
	line := source.split('\n').filter(it.starts_with('CHURN MEASURE ') && it.contains('cohort=1 '))[0]
	failure(source + line.replace('cohort=1 ', 'cohort=+٠١ ') + '\n', 'pipes', false, false, "duplicate measurement: ('pipe', 1)")
	class := 'CHURN CLASS program=pipe cohort=1 size=16 objects_delta=0\n'
	failure(source + class + class.replace('size=16', 'size=٠١٦'), 'pipes', false, false, "invalid class: ('pipe', 1, 16)")
	for cohort in ['4', '-1', '9999999999999999999999999999999999'] {
		changed := source.replace('cohort=3 ', 'cohort=${cohort} ')
		failure(changed, 'pipes', false, false, 'incomplete or unexpected measurement/grace/allocation coverage')
	}
}
