module kernelcompare

import comparecore as common
import json2
import os
import encoding.hex

fn C.mkdtemp(&char) &char

fn fixture_config() common.Value {
	return json2.decode[common.Value]('{"qemu_version":"QEMU emulator version 10.0.0","machine":"q35,vmport=off","accelerator":"tcg,thread=single,tb-size=1024","cpu":"Penryn","smp":"2,sockets=1,cores=2,threads=1","memory_mb":4096,"source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","compile_flags":["-std=c11","-O2","-Wall","-Wextra","-Werror","-fno-builtin","-ffreestanding","-fno-stack-protector","-mno-red-zone","-mno-80387","-mno-mmx","-mno-sse","-mno-sse2"]}') or { panic(err) }
}

fn config_change(key string, value common.Value) common.Value {
	mut config := config_object(fixture_config()) or { panic(err) }
	config[key] = value
	return common.Value(config)
}

fn fixture(platform string, scale u64) string {
	mut lines := ['Boot and kext loader diagnostics are outside benchmark records.',
		'KALLOC-META schema=3 platform=${platform} timer=x86-tsc samples=5 hot_pairs=100000 batch_rounds=48 batch_width=256 big_pairs=128 big_bytes=262144 operation=alloc_free_pair',
		'KALLOC-VALIDATION platform=${platform} sizes=16,32,48,64,96,128,192,256,384,512,768,1024,1536,2048 zero_validation=warmup_every_requested_byte payload_validation=endpoints timed_zero_validation=0',
		'KALLOC-COMPILER platform=${platform} compiler=gcc compiler_major=14 compiler_minor=2 compiler_patch=0']
	original := [[u64(1000000), 1200000, 1100000, 900000, 1300000],
		[u64(122880), 245760, 147456, 110592, 172032], [u64(256000), 384000, 320000, 192000, 448000]]
	for i, phase in phases {
		ticks := original[i].map(it * scale)
		for index, tick in ticks {
			lines << 'KALLOC-SAMPLE platform=${platform} phase=${phase.name} sample=${index + 1} pairs=${phase.pairs} ticks=${tick} ticks_per_pair=${tick / phase.pairs} checksum=${phase.checksum}'
		}
		mut ordered := ticks.clone()
		ordered.sort()
		lines << 'KALLOC-RESULT platform=${platform} phase=${phase.name} pairs=${phase.pairs} samples=5 warmup_pairs=${phase.pairs} median_ticks=${ordered[2]} min_ticks=${ordered[0]} max_ticks=${ordered[4]} median_ticks_per_pair=${ordered[2] / phase.pairs} checksum=${phase.checksum}'
	}
	lines << 'KALLOC-DONE platform=${platform} phases=3 checksum=27358432'
	return lines.join('\n') + '\n'
}

fn invalid(text string) {
	if _ := parse_log(text, 'vinix') {
		assert false, 'accepted invalid log'
	}
}

fn invalid_config(value common.Value) {
	if _ := check_configs(fixture_config(), value) {
		assert false, 'accepted invalid config'
	}
}

fn test_valid_raw_medians_and_ratio() {
	left := parse_log(fixture('vinix', 2), 'vinix') or { panic(err) }
	right := parse_log(fixture('xnu', 1), 'xnu') or { panic(err) }
	output := compare(left, right, fixture_config(), fixture_config()) or { panic(err) }
	for fragment in ['| hot64 | 100000 | 22.000 | 11.000 | 2.000× |',
		'| mixed256 | 12288 | 24.000 | 12.000 | 2.000× |',
		'| big262144 | 128 | 5000.000 | 2500.000 | 2.000× |', 'not native CPU cycles',
		'before its scheduler', 'loaded kext'] {
		assert output.contains(fragment)
	}
}

fn test_syslog_prefixes() {
	text := fixture('xnu', 1).split_into_lines().map('Oct 2 12:00:00 guest kernel[0]: ' + it).join('\n')
	run := parse_log(text, 'xnu') or { panic(err) }
	assert run.samples['hot64'].len == 5
}

fn test_firmware_ansi_prefix_without_whitespace() {
	text := fixture('vinix', 1).replace_once('KALLOC-META', '\x1b[2J\x1b[01;01HKALLOC-META')
	assert (parse_log(text, 'vinix') or { panic(err) }) == (parse_log(fixture('vinix', 1), 'vinix') or { panic(err) })
	invalid(text.replace_once('KALLOC-SAMPLE', 'KALLOC-SAMPLE-broken'))
}

fn test_non_csi_escapes_are_not_silently_stripped() {
	invalid(fixture('vinix', 1).replace_once('KALLOC-META', '\x1b]0;title\x07KALLOC-META'))
}

fn test_missing_completion() { invalid(fixture('vinix', 1).all_before_last('KALLOC-DONE')) }

fn test_missing_and_duplicate_metadata() {
	lines := fixture('vinix', 1).split_into_lines()
	for i in [1, 2, 3] {
		mut missing := lines.clone()
		missing.delete(i)
		invalid(missing.join('\n'))
		mut doubled := lines.clone()
		doubled.insert(i, lines[i])
		invalid(doubled.join('\n'))
	}
}

fn test_out_of_order_or_interleaved_metadata() {
	for pair in [[2, 3], [3, 4]] {
		mut lines := fixture('vinix', 1).split_into_lines()
		lines[pair[0]], lines[pair[1]] = lines[pair[1]], lines[pair[0]]
		invalid(lines.join('\n'))
	}
}

fn test_metadata_cannot_override_other_records() {
	invalid(fixture('vinix', 1).replace_once('KALLOC-VALIDATION platform=vinix', 'KALLOC-VALIDATION platform=vinix schema=2'))
	invalid(fixture('vinix', 1).replace_once('KALLOC-COMPILER platform=vinix', 'KALLOC-COMPILER platform=vinix timer=wall'))
}

fn test_metadata_record_lengths_fit_iolog() {
	source := os.read_file(os.join_path(@VMODROOT, '../../../kernel/heapbench/core.v')) or { panic(err) }
	block := source.all_after('pub fn run() i32 {')
	parts := block.split("C.vkb_log(c'")
	assert parts.len == 5
	arguments := [['vinix', '5', '100000', '48', '256', '128', '262144'], ['vinix'],
		['vinix', 'clang', (~u64(0)).str(), (~u64(0)).str(), (~u64(0)).str()]]
	for i, values in arguments {
		template := parts[i + 1].all_before("'").replace('\\n', '\n')
		mut record := template
		for value in values {
			mark := record.index('%') or { panic('missing format argument') }
			width := if record[mark..].starts_with('%llu') { 4 } else { 2 }
			record = record[..mark] + value + record[mark + width..]
		}
		assert record.ends_with('\n')
		assert record.len <= 240, record
	}
}

fn test_duplicate_missing_and_out_of_order_samples() {
	lines := fixture('vinix', 1).split_into_lines()
	mut doubled := lines.clone()
	doubled.insert(5, lines[4])
	invalid(doubled.join('\n'))
	mut missing := lines.clone()
	missing.delete(4)
	invalid(missing.join('\n'))
	invalid(fixture('vinix', 1).replace_once('phase=hot64 sample=2', 'phase=hot64 sample=1'))
}

fn test_interleaved_phases() {
	mut lines := fixture('vinix', 1).split_into_lines()
	lines[5], lines[10] = lines[10], lines[5]
	invalid(lines.join('\n'))
}

fn test_missing_and_duplicate_result() {
	lines := fixture('vinix', 1).split_into_lines()
	mut missing := lines.clone()
	missing.delete(9)
	invalid(missing.join('\n'))
	mut doubled := lines.clone()
	doubled.insert(10, lines[9])
	invalid(doubled.join('\n'))
}

fn test_unknown_phase_and_record() {
	for old, new in {
		'phase=hot64':   'phase=other'
		'KALLOC-SAMPLE': 'KALLOC-UNEXPECTED'
	} {
		invalid(fixture('vinix', 1).replace_once(old, new))
	}
	invalid(fixture('vinix', 1).replace_once('KALLOC-SAMPLE', 'KALLOC-SAMPLE-broken'))
}

fn test_metadata_contract() {
	for old, new in {
		'samples=5':               'samples=4'
		'timer=x86-tsc':           'timer=wall'
		'compiler=gcc':            'compiler=clang'
		'batch_width=256':         'batch_width=128'
		'schema=3':                'schema=2'
		'big_pairs=128':           'big_pairs=64'
		'big_bytes=262144':        'big_bytes=131072'
		'timed_zero_validation=0': 'timed_zero_validation=1'
	} {
		invalid(fixture('vinix', 1).replace_once(old, new))
	}
}

fn test_wrong_platform_pair_count_and_warmup() {
	for old, new in {
		'platform=vinix':        'platform=xnu'
		'sample=1 pairs=100000': 'sample=1 pairs=99999'
		'warmup_pairs=100000':   'warmup_pairs=1'
	} {
		invalid(fixture('vinix', 1).replace_once(old, new))
	}
}

fn test_invalid_tsc_measurements() {
	for ticks in ['0', '-1', '1.5', 'nan', '18446744073709551616'] {
		invalid(fixture('vinix', 1).replace_once('ticks=1000000', 'ticks=' + ticks))
	}
}

fn test_fabricated_summaries() {
	for old, new in {
		'median_ticks=1100000':     'median_ticks=1100001'
		'min_ticks=900000':         'min_ticks=1000000'
		'max_ticks=1300000':        'max_ticks=1200000'
		'median_ticks_per_pair=11': 'median_ticks_per_pair=12'
		'ticks_per_pair=10':        'ticks_per_pair=11'
	} {
		invalid(fixture('vinix', 1).replace_once(old, new))
	}
}

fn test_wrong_payload_and_completion_checksums() {
	invalid(fixture('vinix', 1).replace('25486688', '25486687'))
	invalid(fixture('vinix', 1).replace('checksum=27358432', 'checksum=0'))
}

fn test_missing_large_phase_or_schema_one_completion() {
	invalid(fixture('vinix', 1).split_into_lines().filter(!it.contains('phase=big262144')).join('\n'))
	invalid(fixture('vinix', 1).replace('phases=3 checksum=27358432', 'phases=2 checksum=27342176'))
	invalid(fixture('vinix', 1).replace('checksum=16256', 'checksum=16255'))
}

fn test_error_or_panic_before_or_after_completion() {
	for message in ['KALLOC-ERROR reason=allocation_failed', 'KERNEL PANIC', 'panic(cpu 0 caller)',
		'FATAL EXCEPTION'] {
		invalid(message + '\n' + fixture('vinix', 1))
		invalid(fixture('vinix', 1) + message)
	}
	invalid(fixture('vinix', 1) + 'KALLOC-DONE platform=vinix phases=3 checksum=27358432')
}

fn test_malformed_fields() {
	for value in ['sample=1 sample=1', 'sample=', 'sample'] {
		invalid(fixture('vinix', 1).replace_once('sample=1', value))
	}
}

fn test_config_mismatches() {
	for key, value in {
		'machine':       common.Value('pc')
		'cpu':           common.Value('max')
		'smp':           common.Value('1')
		'accelerator':   common.Value('tcg,thread=multi,tb-size=1024')
		'memory_mb':     common.Value(common.Number{'2048'})
		'source_sha256': common.Value('b'.repeat(64))
		'qemu_version':  common.Value('other')
	} {
		invalid_config(config_change(key, value))
	}
}

fn test_config_missing_invalid_values_and_extra_flags() {
	invalid_config(common.Value([]common.Value{}))
	invalid_config(common.Value(map[string]common.Value{}))
	for key, value in {
		'memory_mb':     common.Value(true)
		'accelerator':   common.Value('hvf')
		'arch':          common.Value('arm64')
		'source_sha256': common.Value('invalid')
	} {
		invalid_config(config_change(key, value))
	}
	for extra in ['-O3', '-O2'] {
		mut flags := compile_flags.map(common.Value(it))
		flags << common.Value(extra)
		invalid_config(config_change('compile_flags', common.Value(flags)))
	}
}

fn test_v_sampler_header_and_language_must_match() {
	mut config := config_object(fixture_config()) or { panic(err) }
	config['sampler_language'] = common.Value('V')
	config['sampler_header_sha256'] = common.Value('c'.repeat(64))
	check_configs(common.Value(config), common.Value(config)) or { panic(err) }
	if _ := check_configs(common.Value(config), fixture_config()) {
		assert false
	}
	for key, value in {
		'sampler_language':      'C'
		'sampler_header_sha256': 'invalid'
	} {
		mut other := config.clone()
		other[key] = common.Value(value)
		if _ := check_configs(common.Value(config), common.Value(other)) {
			assert false
		}
	}
	mut other := config.clone()
	other['sampler_header_sha256'] = common.Value('d'.repeat(64))
	if _ := check_configs(common.Value(config), common.Value(other)) {
		assert false
	}
}

fn test_compiler_versions_and_flag_order() {
	left := parse_log(fixture('vinix', 1), 'vinix') or { panic(err) }
	mut right := parse_log(fixture('xnu', 1).replace('compiler_minor=2', 'compiler_minor=3'), 'xnu') or { panic(err) }
	mut flags := compile_flags.clone()
	flags.reverse()
	output := compare(left, right, fixture_config(), config_change('compile_flags', common.Value(flags.map(common.Value(it))))) or { panic(err) }
	assert output.contains('minor/patch versions differ')
	right.meta['compiler_major'] = '15'
	if _ := compare(left, right, fixture_config(), fixture_config()) {
		assert false
	}
}

fn test_cli_valid_and_unmatched_runs() {
	mut template := os.join_path(os.temp_dir(), 'vinix-kernel-compare-XXXXXX').bytes()
	template << u8(0)
	pointer := C.mkdtemp(unsafe { &char(template.data) })
	assert pointer != unsafe { nil }
	root := unsafe { cstring_to_vstring(pointer).clone() }
	defer { os.rmdir_all(root) or { panic(err) } }
	os.write_file(os.join_path(root, 'vinix.log'), fixture('vinix', 1)) or { panic(err) }
	os.write_file(os.join_path(root, 'xnu.log'), fixture('xnu', 1)) or { panic(err) }
	os.write_file(os.join_path(root, 'config.json'), json2.encode(fixture_config())) or { panic(err) }
	os.write_file(os.join_path(root, 'bad.json'), json2.encode(config_change('memory_mb', common.Value(common.Number{'2048'})))) or { panic(err) }
	compiler := os.getenv('VEXE')
	assert compiler != ''
	binary := os.join_path(root, 'compare-kernel')
	mut build := os.new_process(compiler)
	build.set_args(['-o', binary, os.join_path(@VMODROOT, '../compare_kernel.v')])
	build.set_redirect_stdio()
	build.run()
	build.wait()
	assert build.code == 0, build.stderr_slurp()
	for invalid_pair in [false, true] {
		mut child := os.new_process(binary)
		mut args := [os.join_path(root, 'vinix.log'), os.join_path(root, 'xnu.log')]
		if invalid_pair { args << ['--xnu-config', os.join_path(root, 'bad.json')] }
		child.set_args(args)
		child.set_redirect_stdio()
		child.run()
		child.wait()
		assert child.code == if invalid_pair { 2 } else { 0 }
		output := child.stdout_slurp()
		errors := child.stderr_slurp()
		if invalid_pair {
			assert output == ''
			assert errors.contains('Kernel comparison rejected')
		} else {
			assert output.contains('Matched QEMU')
		}
	}
}

fn test_malformed_utf8_uses_maximal_valid_prefix_replacement() {
	for bytes, expected in {
		'e180':     '�'
		'e18041':   '�A'
		'eda080':   '���'
		'f09080':   '�'
		'f4908080': '����'
		'e228a1':   '�(�'
		'8081':     '��'
	} {
		mut input := []u8{}
		for i := 0; i < bytes.len; i += 2 {
			input << (hex.decode(bytes[i..i + 2]) or { panic(err) })[0]
		}
		assert log_text(input.bytestr()) == expected
	}
}
