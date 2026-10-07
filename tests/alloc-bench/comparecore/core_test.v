module comparecore

import math
import os

fn C.mkdtemp(&char) &char

fn fixture_config() Config {
	return decode_config('{"qemu_version":"QEMU emulator version 11.1.1","machine":"q35,vmport=off","accelerator":"tcg,thread=single,tb-size=1024","cpu":"Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt","smp":"2,sockets=1,cores=2,threads=1","memory_mb":4096,"source_sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","compile_flags":["-std=c11","-O2","-Wall","-Wextra","-Werror","-fno-builtin"]}') or { panic(err) }
}

fn fixture(platform string, durations []u64, iterations u64) string {
	count := durations.len
	mut output := ['serial: boot is ready',
		'ALLOC-META schema=1 label=test platform=${platform} release=test arch=x86_64 compiler=gcc compiler_major=14 compiler_minor=2 compiler_patch=0 compiler_version=14.2.0 pointer_bits=64 page_size=4096 clock=CLOCK_MONOTONIC clock_resolution_ns=1 threads=1 iterations=${iterations} samples=${count} touch_stride=4096 large_bytes=262144 mixed_sizes=16,32,64,96,128,256,512,1024,2048,4096,8192,16384']
	mut sorted := durations.clone()
	sorted.sort()
	middle := if count % 2 != 0 {
		f64(sorted[count / 2])
	} else {
		f64(sorted[count / 2 - 1] + sorted[count / 2]) / 2
	}
	for w in workloads {
		pairs := (iterations + w.divisor - 1) / w.divisor
		for index, ns in durations {
			output << 'ALLOC-SAMPLE label=test workload=${w.name} sample=${index + 1} pairs=${pairs} elapsed_ns=${ns * pairs + 1} ns_per_pair=${fixed(f64(ns) + 1 / f64(pairs))} checksum=123'
		}
		output << 'ALLOC-RESULT label=test workload=${w.name} category=${w.category} operation=${w.operation} pairs=${pairs} samples=${count} warmup_pairs=${pairs} bytes=${w.size} batch=${w.batch} touch_stride=${w.stride} median_ns_per_pair=${fixed(middle + 1 / f64(pairs))} min_ns_per_pair=${fixed(f64(sorted[0]) + 1 / f64(pairs))} max_ns_per_pair=${fixed(f64(sorted.last()) + 1 / f64(pairs))}'
	}
	output << ['ALLOC-DONE label=test workloads=6 checksum=0', 'serial: shutdown']
	return output.join('\n') + '\n'
}

fn log_fixture() string { return fixture('Vinix', [u64(100), 200, 250, 300, 900], 2000) }

fn fixture_run(text string, name string) Run {
	return parse_log(text, name, fixture_config()) or { panic(err) }
}

fn invalid(text string, reason string) {
	if _ := parse_log(text, 'Vinix', fixture_config()) {
		assert false, 'accepted invalid log: ${reason}'
	} else {
		assert err.msg().contains(reason), '${err} does not contain ${reason}'
	}
}

fn paired() (Run, Run) {
	return fixture_run(log_fixture(), 'Vinix'), fixture_run(fixture('Darwin', [
		u64(100),
		200,
		250,
		300,
		900,
	], 2000), 'macOS')
}

fn test_complete_log_uses_raw_median_with_outliers() {
	run := fixture_run(log_fixture(), 'Vinix')
	assert math.abs(run.median('malloc_hot_64') - 250.0005) < 0.0000001
	assert math.abs(run.median('mmap_anon_4096') - 250.01) < 0.0000001
	assert run.median('malloc_hot_64') != run.results['malloc_hot_64']['median_ns_per_pair'].f64()
}

fn test_even_sample_median_and_serial_prefix() {
	run := fixture_run(fixture('Vinix', [u64(100), 200, 250, 300, 500, 900], 2000).replace('ALLOC-', 'console: ALLOC-'), 'Vinix')
	assert math.abs(run.median('malloc_hot_64') - 275.0005) < 0.0000001
}

fn test_success_marker_and_error_records() {
	invalid(log_fixture().replace('ALLOC-DONE', 'MISSING-DONE'), 'ALLOC-DONE required')
	invalid(log_fixture().replace('ALLOC-DONE', 'ALLOC-ERROR action=failed\nALLOC-DONE'), 'reported an error')
	invalid(log_fixture() + 'ALLOC-ERROR action=late\n', 'after ALLOC-DONE')
	invalid(log_fixture().replace('workloads=6', 'workloads=5'), 'workload count')
	invalid(log_fixture().replace('workloads=6 checksum=0', 'workloads=6 checksum=1'), 'DONE checksum')
}

fn test_missing_workload_is_rejected_even_if_both_runs_omit_it() {
	invalid(log_fixture().split_into_lines().filter(!it.contains('workload=pipe_create_close')).join('\n'), 'missing workloads pipe_create_close')
}

fn test_missing_duplicate_and_out_of_range_samples() {
	invalid(log_fixture().replace('sample=5', 'sample=4'), 'duplicate sample')
	invalid(log_fixture().replace('sample=5', 'sample=0'), 'outside')
	invalid(log_fixture().split_into_lines().filter(!(it.contains('malloc_hot_64') && it.contains('sample=5'))).join('\n'), 'expected 5 samples, found 4')
	invalid(fixture('Vinix', [u64(100), 200, 300, 400], 2000), 'samples is outside')
}

fn test_duplicate_metadata_and_results() {
	text := log_fixture()
	meta := text.split_into_lines().filter(it.starts_with('ALLOC-META'))[0]
	invalid(meta + '\n' + text, 'duplicate or misplaced metadata')
	result := text.split_into_lines().filter(it.starts_with('ALLOC-RESULT'))[0]
	invalid(text.replace(result, result + '\n' + result), 'duplicate result')
}

fn test_sample_pairs_elapsed_checksum_and_labels() {
	for old, replacement in {
		'sample=1 pairs=2000':                                                    'sample=1 pairs=1999'
		'elapsed_ns=200001':                                                      'elapsed_ns=0'
		'sample=1 pairs=2000 elapsed_ns=200001 ns_per_pair=100.001 checksum=123': 'sample=1 pairs=2000 elapsed_ns=200001 ns_per_pair=100.001 checksum=124'
		'ALLOC-SAMPLE label=test':                                                'ALLOC-SAMPLE label=other'
	} {
		reason := if replacement.contains('elapsed_ns=0') {
			'outside'
		} else if replacement.ends_with('checksum=124') {
			'checksum differs'
		} else {
			'sample label or pair count differs'
		}
		invalid(log_fixture().replace_once(old, replacement), reason)
	}
}

fn test_result_parameters_are_validated_against_workload() {
	for old, replacement in {
		'bytes=64 batch=1':       'bytes=65 batch=1'
		'warmup_pairs=2000':      'warmup_pairs=1999'
		'category=userspace':     'category=kernel_syscall'
		'samples=5 warmup_pairs': 'samples=6 warmup_pairs'
	} {
		invalid(log_fixture().replace_once(old, replacement), 'inconsistent')
	}
}

fn test_forged_or_nonfinite_timing_summary_is_rejected() {
	for replacement in ['10.000', 'nan'] {
		invalid(log_fixture().replace('median_ns_per_pair=250.000', 'median_ns_per_pair=' + replacement), 'disagrees with raw')
	}
	invalid(log_fixture().replace_once('ns_per_pair=100.001', 'ns_per_pair=100.010'), 'disagrees with raw')
}

fn test_bad_schema_or_record_fields() {
	invalid(log_fixture().replace('schema=1', 'schema=2'), 'unsupported schema')
	invalid(log_fixture().replace('samples=5 touch_stride', 'samples=5 samples=5 touch_stride'), 'duplicate field')
	invalid(log_fixture().replace('compiler_major=14 ', ''), 'missing fields compiler_major')
	invalid(log_fixture().replace_once('sample=1', 'sample=NaN'), 'unsigned integer')
	invalid(log_fixture().replace('workload=malloc_hot_64', 'workload=unknown'), 'unknown workload')
}

fn test_matching_guest_runs_and_real_ratio() {
	left := fixture_run(fixture('Vinix', [u64(200), 400, 500, 600, 1800], 2000), 'Vinix')
	_, right := paired()
	mismatches, notes := comparability(left, right)
	assert mismatches.len == 0 && notes.len == 0
	report := render(left, right, mismatches, notes)
	assert report.contains('500.000 | 250.000 | 2.000×')
	assert report.contains('userspace allocators and libc')
	assert report.contains('do not directly compare')
}

fn test_platform_architecture_and_actual_gcc() {
	for key, change in {
		'platform':       'Darwin'
		'arch':           'aarch64'
		'compiler':       'clang'
		'compiler_major': '15'
	} {
		mut left, right := paired()
		left.meta[key] = change
		mismatches, _ := comparability(left, right)
		reason := match key {
			'platform' { 'expected Vinix or Linux' }
			'arch' { 'guest arch x86_64' }
			'compiler' { 'actual GCC required' }
			else { 'GCC major versions differ' }
		}
		assert mismatches.any(it.contains(reason))
	}
	mut left, right := paired()
	left.meta['platform'] = 'Linux'
	mismatches, _ := comparability(left, right)
	assert mismatches.len == 0
}

fn test_gcc_minor_difference_is_an_explicit_caveat() {
	left, mut right := paired()
	right.meta['compiler_minor'] = '3'
	right.meta['compiler_version'] = '14.3.0'
	mismatches, notes := comparability(left, right)
	assert mismatches.len == 0 && notes.any(it.contains('minor/patch versions differ'))
	assert render(left, right, mismatches, notes).contains('GCC 14.3.0')
}

fn test_every_common_qemu_parameter_and_source_must_match() {
	changes := decode_config('{"qemu_version":"QEMU emulator version 10.0.0","machine":"pc","accelerator":"tcg,thread=multi","cpu":"max","smp":"1","memory_mb":2048,"source_sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}') or { panic(err) }
	for key, change in changes {
		left, mut right := paired()
		right.config[key] = change
		mismatches, _ := comparability(left, right)
		assert mismatches.any(it.contains('QEMU config ' + key))
	}
}

fn test_native_acceleration_missing_manifest_and_flags_are_rejected() {
	changes := decode_config('{"accelerator":"hvf","source_sha256":"","memory_mb":true,"compile_flags":["-O2"]}') or { panic(err) }
	for key, change in changes {
		mut left, mut right := paired()
		left.config[key] = change
		right.config[key] = change
		mismatches, _ := comparability(left, right)
		reason := match key {
			'accelerator' { 'TCG acceleration required' }
			'memory_mb' { 'positive integer' }
			else { key }
		}
		assert mismatches.any(it.contains(reason))
	}
	mut left, mut right := paired()
	left.config.delete('cpu')
	mismatches, _ := comparability(left, right)
	assert mismatches.any(it.contains('missing config field cpu'))
	left.config['cpu'] = right.config['cpu'] or { panic('missing CPU') }
	flags := value(right.config, 'compile_flags')
	if flags is []Value { right.config['compile_flags'] = Value(flags.reverse()) }
	reversed_mismatches, _ := comparability(left, right)
	assert reversed_mismatches.len == 0
	mut extra := compile_flags.map(Value(it))
	extra << Value('-ffast-math')
	left.config['compile_flags'] = Value(extra)
	right.config['compile_flags'] = Value(extra)
	extra_mismatches, _ := comparability(left, right)
	assert extra_mismatches.any(it.contains('compile_flags'))
}

fn test_workload_counts_and_page_sizes_must_match() {
	left, mut right := paired()
	short := fixture_run(fixture('Darwin', [u64(100), 200, 250, 300, 900], 1000), 'macOS')
	mismatches, _ := comparability(left, short)
	assert mismatches.any(it.contains('benchmark iterations'))
	right.meta['page_size'] = '16384'
	page_mismatches, _ := comparability(left, right)
	assert page_mismatches.any(it.contains('benchmark page_size'))
	right.meta['page_size'] = '4096'
	right.meta['clock_resolution_ns'] = '1000'
	clock_mismatches, _ := comparability(left, right)
	assert clock_mismatches.len == 0
}

fn test_v_artifacts_require_matching_native_header_and_manifest() {
	mut left, mut right := paired()
	header := 'a'.repeat(64)
	mut runs := [&left, &right]
	for mut run in runs {
		run.config['native_header_sha256'] = Value(header)
		run.config['v_generation'] = Value(map[string]Value{
			'source_sha256':        value(run.config, 'source_sha256')
			'native_header_sha256': Value(header)
		})
	}
	mismatches, _ := comparability(left, right)
	assert mismatches.len == 0
	right.config['native_header_sha256'] = Value('b'.repeat(64))
	header_mismatches, _ := comparability(left, right)
	assert header_mismatches.any(it.contains('header differs'))
	right.config['native_header_sha256'] = Value(header)
	right.config['v_generation'] = Value(map[string]Value{
		'source_sha256':        Value('c'.repeat(64))
		'native_header_sha256': Value(header)
	})
	generation_mismatches, _ := comparability(left, right)
	assert generation_mismatches.any(it.contains('manifest differs'))
	right.config.delete('v_generation')
	missing_mismatches, _ := comparability(left, right)
	assert missing_mismatches.any(it.contains('manifest required'))
	right.config.delete('native_header_sha256')
	invalid_mismatches, _ := comparability(left, right)
	assert invalid_mismatches.any(it.contains('valid native_header_sha256'))
}

fn test_unsigned_and_binary64_boundaries() {
	assert number({
		'n': '18446744073709551615'
	}, 'n', 'test', 0, ~u64(0)) or { panic(err) } == ~u64(0)
	if _ := number({
		'n': '18446744073709551616'
	}, 'n', 'test', 0, ~u64(0)) {
		assert false
	}
	assert ratio(1000001, 2000) == 500.0005
	assert fixed(500.0005) == '500.000'
	assert !equal(Value(Number{'9007199254740993'}), Value(Number{'9007199254740992.0'}))
	assert equal(Value(Number{'2048'}), Value(Number{'2048.0'}))
	assert equal(Value(true), Value(Number{'1'}))
}

fn test_unicode_record_whitespace_and_lines() {
	for separator in ['\u00a0', '\u2003', '\x1f'] {
		assert fixture_run(log_fixture().replace(' ', separator), 'Vinix').meta['schema'] == '1'
	}
	for separator in ['\r\n', '\r', '\v', '\f', '\u0085', '\u2028', '\u2029', '\x1c'] {
		assert fixture_run(log_fixture().replace('\n', separator), 'Vinix').done['workloads'] == '6'
	}
}

struct CommandResult {
	status int
	stdout string
	stderr string
}

fn invoke(mismatch bool, diagnostic bool) CommandResult {
	mut pattern := os.join_path(os.temp_dir(), 'vinix-allocation-compare-XXXXXX').bytes()
	pattern << u8(0)
	if unsafe { C.mkdtemp(&char(&pattern[0])) } == unsafe { nil } {
		panic('cannot create test directory')
	}
	directory := pattern[..pattern.len - 1].bytestr()
	defer { os.rmdir_all(directory) or { panic(err) } }
	mut argv := []string{}
	for name, platform in {
		'vinix': 'Vinix'
		'macos': 'Darwin'
	} {
		path := os.join_path(directory, name)
		os.mkdir_all(path) or { panic(err) }
		log := os.join_path(path, 'serial.log')
		os.write_file(log, fixture(platform, [u64(100), 200, 250, 300, 900], 2000)) or { panic(err) }
		mut config_text := '{"qemu_version":"QEMU emulator version 11.1.1","machine":"q35,vmport=off","accelerator":"tcg,thread=single,tb-size=1024","cpu":"Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt","smp":"2,sockets=1,cores=2,threads=1","memory_mb":4096,"source_sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","compile_flags":["-std=c11","-O2","-Wall","-Wextra","-Werror","-fno-builtin"]}'
		if mismatch && name == 'macos' {
			config_text = config_text.replace('Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt', 'max')
		}
		os.write_file(os.join_path(path, 'config.json'), config_text) or { panic(err) }
		argv << log
	}
	if diagnostic { argv << '--allow-mismatch' }
	tool_dir := os.dir(os.dir(@FILE))
	mut child := os.new_process('sh')
	defer { child.close() }
	child.set_args([os.join_path(tool_dir, 'compare'), ...argv])
	child.set_redirect_stdio()
	child.run()
	if child.pid <= 0 { panic('cannot spawn comparator') }
	stdout := child.stdout_slurp()
	stderr := child.stderr_slurp()
	child.wait()
	return CommandResult{child.code, stdout, stderr}
}

fn test_config_defaults_and_success() {
	result := invoke(false, false)
	assert result.status == 0
	assert result.stdout.contains('Matched QEMU')
	assert result.stderr == ''
}

fn test_mismatch_never_passes_as_matched() {
	result := invoke(true, false)
	assert result.status == 1 && result.stdout == ''
	assert result.stderr.contains('runs are not comparable')
	diagnostic := invoke(true, true)
	assert diagnostic.status == 2
	assert diagnostic.stdout.contains('Unmatched runs')
	assert diagnostic.stdout.contains('not a fair matched comparison')
	assert !diagnostic.stdout.contains('Matched QEMU')
	assert diagnostic.stdout.contains('Vinix/macOS')
	assert diagnostic.stderr == ''
}
