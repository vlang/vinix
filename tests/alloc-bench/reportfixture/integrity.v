// SPDX-License-Identifier: BSD-2-Clause
module reportfixture

import comparecore as b
import evidencearchive as archive
import json2
import os
import reportcore as r

#include <stdlib.h>

fn C.mkdtemp(&char) &char

pub fn temporary(prefix string) !string {
	requested := os.getenv('TMPDIR')
	parent := if requested != '' && os.is_dir(requested) { requested } else { os.temp_dir() }
	mut template := (os.join_path(parent, prefix + 'XXXXXX') + '\x00').bytes()
	if isnil(C.mkdtemp(&char(template.data))) {
		return error('Cannot create private report fixture')
	}
	return template[..template.len - 1].bytestr().clone()
}

pub fn write(path string, value b.Value) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

enum Kind {
	set
	delete
	remove_tree
	copy_tree
	remove_file
	replace_file
	record
	argv_change
	argv_duplicate
	all_qemu
	append
}

struct Case {
	name  string
	kind  Kind
	path  string
	keys  []string
	value b.Value = b.Value('')
	tag   string
	key   string
	mode  string
	index int
}

fn set_case(name string, path string, keys []string, value b.Value) Case {
	return Case{ name: name, kind: .set, path: path, keys: keys, value: value }
}

fn rec_case(name string, tag string, key string, value string, mode string, capture string, index int) Case {
	return Case{ name: name, kind: .record, path: capture + '/serial.log', tag: tag, key: key, value: b.Value(value), mode: mode, index: index }
}

fn cases(profile r.Profile) []Case {
	mut tests := []Case{}
	vconfig, mconfig := 'vinix-1/config.json', 'catalina-1/config.json'
	tests << Case{ name: 'missing final capture', kind: .remove_tree, path: 'vinix-2' }
	tests << Case{ name: 'extra complete capture', kind: .copy_tree, path: 'vinix-3' }
	mut reversed := r.order.clone()
	reversed.reverse_in_place()
	tests << set_case('changed plan order', 'campaign-plan.json', ['order'], r.strings(reversed))
	for key, value in {
		'source_sha256': b.Value('0'.repeat(64))
		'iterations':    r.num(10000)
		'samples':       r.num(5)
		'warmup':        b.Value('none')
		'common_qemu':   b.Value(b.Config{})
		'declared_utc':  b.Value('2099-01-01T00:00:00+00:00')
	} {
		tests << set_case('changed plan ' + key, 'campaign-plan.json', [key], value)
	}
	tests << set_case('driver exit_code=1', 'vinix-1/driver-exit.json', ['exit_code'], r.num(1))
	tests << set_case('driver exit_code=False', 'vinix-1/driver-exit.json', ['exit_code'], b.Value(false))
	tests << set_case('driver argv=[]', 'vinix-1/driver-exit.json', ['argv'], b.Value([]b.Value{}))
	for key, value in {
		'started_utc':  '2026-10-02T19:18:38'
		'finished_utc': 'bad'
	} {
		tests << set_case('driver ' + key + '=' + value, 'vinix-1/driver-exit.json', [key], b.Value(value))
	}
	tests << set_case('driver finished_utc=2026-10-02T00:00:00+00:00', 'vinix-1/driver-exit.json', ['finished_utc'], b.Value('2026-10-02T00:00:00+00:00'))
	tests << set_case('overlapping drivers', 'catalina-1/driver-exit.json', ['started_utc'], b.Value('2026-10-02T19:19:38.051711+00:00'))
	tests << Case{ name: 'missing driver', kind: .remove_file, path: 'vinix-1/driver-exit.json' }
	for name in ['bench.c', 'compare.py'] {
		tests << Case{ name: 'changed preserved ' + name, kind: .replace_file, path: if name == 'bench.c' {
			name
		} else {
			'validator/comparecore/core.v'
		} }
		tests << set_case('changed snapshot ' + name, 'source-snapshots.json', [name, 'sha256'], b.Value('0'.repeat(64)))
	}
	// The historical comparator pin now verifies archived bytes. Current native
	// policy and CLI are pinned independently, and both must reject tampering.
	tests << Case{ name: 'changed native comparator CLI', kind: .replace_file, path: 'validator/compare.v' }
	tests << set_case('old kernel provenance', 'validation/kernel-x86_64.json', ['kernel_sha256'], b.Value('0'.repeat(64)))
	build_key := 'optimized-${profile.version}-final'
	tests << Case{ name: 'missing ${profile.version} libc manifest', kind: .delete, path: 'validation/libc-builds.json', keys: [build_key] }
	for key, value in {
		'libc_so_sha256': b.Value('0'.repeat(64))
		'libc_a_sha256':  b.Value('0'.repeat(64))
		'retention':      r.num(0)
		'arch':           b.Value('aarch64')
		'version':        b.Value('1.2.6')
		'patches':        b.Value([]b.Value{})
	} {
		tests << set_case('changed saved libc ' + key, 'validation/libc-builds.json', [
			build_key,
			'manifest',
			key,
		], value)
	}
	tests << Case{ name: 'changed saved libc patch', kind: .replace_file, path: 'validation/libc.patch' }
	for key in ['kernel_sha256', 'source_sha256', 'libc_sha256', 'libc_a_sha256'] {
		tests << set_case('changed run ' + key, vconfig, [key], b.Value('0'.repeat(64)))
		tests << set_case('invalid run ' + key, vconfig, [key], b.Value('invalid'))
	}
	tests << set_case('libc manifest type', vconfig, ['libc_build'], b.Value([]b.Value{}))
	tests << set_case('libc manifest artifact mismatch', vconfig, ['libc_build', 'libc_so_sha256'], b.Value('0'.repeat(64)))
	tests << set_case('libc manifest flags mismatch', vconfig, ['libc_build', 'cflags'], b.Value('-O0'))
	for key, value in {
		'iterations':    r.num(1)
		'samples':       r.num(5)
		'argv':          b.Value([]b.Value{})
		'compile_flags': b.Value([]b.Value{})
	} {
		tests << set_case('run config ' + key, vconfig, [key], value)
	}
	for key, _ in r.qemu() {
		value := if key == 'memory_mb' { r.num(1) } else { b.Value('changed') }
		tests << set_case('unequal QEMU ' + key, vconfig, [key], value)
		tests << Case{ name: 'equally changed QEMU ' + key, kind: .all_qemu, keys: [key], value: value }
	}
	tests << Case{ name: 'actual QEMU argv differs', kind: .argv_change, path: vconfig }
	tests << Case{ name: 'duplicate actual QEMU option', kind: .argv_duplicate, path: vconfig }
	for key in ['assembly_sha256', 'binary_sha256', 'freshly_verified_assembly_sha256'] {
		tests << set_case('invalid Catalina ' + key, mconfig, [key], b.Value('invalid'))
		tests << set_case('changed Catalina ' + key, mconfig, [key], b.Value('0'.repeat(64)))
	}
	for key in ['guest_compile_command', 'host_link_command', 'sdk', 'build_method', 'build_mode',
		'guest_version'] {
		tests << set_case('different Catalina cohorts ' + key, 'catalina-2/config.json', [key], b.Value('changed'))
	}
	for tag in ['ALLOC-META', 'ALLOC-DONE', 'ALLOC-SAMPLE', 'ALLOC-RESULT'] {
		tests << rec_case('missing ' + tag, tag, '', '', 'drop', 'vinix-1', 0)
		tests << rec_case('duplicate ' + tag, tag, '', '', 'duplicate', 'vinix-1', 0)
	}
	mut meta_keys := b.meta_fields.clone()
	meta_keys << ['label', 'platform', 'release', 'compiler', 'compiler_major', 'compiler_minor',
		'compiler_patch', 'compiler_version', 'clock_resolution_ns']
	for key in meta_keys {
		tests << rec_case('missing metadata ' + key, 'ALLOC-META', key, '', 'remove', 'vinix-1', 0)
	}
	for key, value in {
		'schema':              '2'
		'arch':                'aarch64'
		'pointer_bits':        '32'
		'threads':             '2'
		'clock':               'CLOCK_REALTIME'
		'page_size':           '0'
		'clock_resolution_ns': '0'
		'samples':             '4'
		'iterations':          '0'
		'touch_stride':        '8'
		'large_bytes':         '1'
		'mixed_sizes':         '16'
		'compiler':            'clang'
		'compiler_major':      '13'
		'platform':            'Darwin'
	} {
		tests << rec_case('invalid metadata ' + key, 'ALLOC-META', key, value, '', 'vinix-1', 0)
	}
	tests << rec_case('different guest compiler metadata between cohorts', 'ALLOC-META', 'compiler_minor', '9', '', 'vinix-2', 0)
	tests << rec_case('different Vinix platform between cohorts', 'ALLOC-META', 'platform', 'Linux', '', 'vinix-2', 0)
	for capture in ['vinix-2', 'catalina-2'] {
		tests << rec_case('different ' + capture + ' release between cohorts', 'ALLOC-META', 'release', 'other', '', capture, 0)
	}
	for key in ['category', 'operation', 'pairs', 'samples', 'warmup_pairs', 'bytes', 'batch',
		'touch_stride'] {
		tests << rec_case('result specification ' + key, 'ALLOC-RESULT', key, '999', '', 'vinix-1', 0)
	}
	for key in ['label', 'category', 'operation', 'pairs', 'samples', 'warmup_pairs', 'bytes',
		'batch', 'touch_stride', 'median_ns_per_pair', 'min_ns_per_pair', 'max_ns_per_pair'] {
		tests << rec_case('missing result ' + key, 'ALLOC-RESULT', key, '', 'remove', 'vinix-1', 0)
	}
	for key in ['label', 'sample', 'pairs', 'elapsed_ns', 'ns_per_pair', 'checksum'] {
		tests << rec_case('missing sample ' + key, 'ALLOC-SAMPLE', key, '', 'remove', 'vinix-1', 0)
	}
	for key, value in {
		'workload':    'unknown'
		'label':       'other'
		'sample':      '0'
		'pairs':       '1'
		'elapsed_ns':  '0'
		'ns_per_pair': 'nan'
		'checksum':    '0'
	} {
		tests << rec_case('invalid sample ' + key + '=' + value, 'ALLOC-SAMPLE', key, value, '', 'vinix-1', 0)
	}
	for value in ['8', '-1'] {
		tests << rec_case('invalid sample sample=' + value, 'ALLOC-SAMPLE', 'sample', value, '', 'vinix-1', 0)
	}
	for value in ['18446744073709551616', '-1'] {
		tests << rec_case('invalid sample elapsed_ns=' + value, 'ALLOC-SAMPLE', 'elapsed_ns', value, '', 'vinix-1', 0)
	}
	tests << rec_case('invalid sample ns_per_pair=0', 'ALLOC-SAMPLE', 'ns_per_pair', '0', '', 'vinix-1', 0)
	tests << rec_case('duplicate sample index', 'ALLOC-SAMPLE', 'sample', '1', '', 'vinix-1', 1)
	for key in ['median_ns_per_pair', 'min_ns_per_pair', 'max_ns_per_pair'] {
		tests << rec_case('result summary differs ' + key, 'ALLOC-RESULT', key, '0', '', 'vinix-1', 0)
	}
	for key in ['label', 'workloads', 'checksum'] {
		tests << rec_case('missing footer ' + key, 'ALLOC-DONE', key, '', 'remove', 'vinix-1', 0)
		tests << rec_case('incorrect footer ' + key, 'ALLOC-DONE', key, '999', '', 'vinix-1', 0)
	}
	tests << Case{ name: 'record after footer', kind: .append, path: 'vinix-1/serial.log', value: b.Value('ALLOC-SAMPLE workload=malloc_hot_64') }
	tests << Case{ name: 'reported benchmark error', kind: .append, path: 'vinix-1/serial.log', value: b.Value('ALLOC-ERROR reason=test') }
	tests << rec_case('duplicate field', 'ALLOC-SAMPLE', 'label', 'vinix label=vinix', '', 'vinix-1', 0)
	return tests
}

fn change(value b.Value, keys []string, replacement b.Value, remove bool) !b.Value {
	if keys.len == 0 { return replacement }
	if value is map[string]b.Value {
		mut data := value.clone()
		key := keys[0]
		if keys.len == 1 && remove {
			data.delete(key)
		} else {
			updated := change(b.value(data, key), keys[1..], replacement, remove)!
			// Every map on the edited path was cloned above. Unedited children are
			// immutable, so this assignment cannot mutate the parsed base fixture.
			unsafe { data[key] = updated }
		}
		return b.Value(data)
	}
	return error('Invalid fixture mutation path')
}

fn (test Case) apply(work string) ! {
	path := work + '/' + test.path
	match test.kind {
		.set, .delete {
			write(path, change(b.Value(r.object(path)!), test.keys, test.value, test.kind == .delete)!)!
		}
		.remove_tree { os.rmdir_all(path)! }
		.copy_tree { os.cp_all(work + '/vinix-1', path, false)! }
		.remove_file { os.rm(path)! }
		.replace_file { os.write_file(path, 'changed\n')! }
		.all_qemu {
			for name in r.order {
				set_case('', name + '/config.json', test.keys, test.value).apply(work)!
			}
		}
		.argv_change, .argv_duplicate {
			mut data := r.object(path)!
			mut args := b.value(data, 'argv') as []b.Value
			if test.kind == .argv_duplicate {
				args << [b.Value('-m'), b.Value('4096')]
			} else {
				position := args.index(b.Value('-m'))
				assert position >= 0
				args[position + 1] = b.Value('2048')
			}
			data['argv'] = b.Value(args)
			write(path, b.Value(data))!
		}
		.append { os.write_file(path, os.read_file(path)! + (test.value as string) + '\n')! }
		.record {
			mut lines := os.read_lines(path)!
			positions := lines.map(it.starts_with(test.tag + ' '))
			mut selected := []int{}
			for index, matched in positions { if matched { selected << index } }
			assert selected.len > test.index
			position := selected[test.index]
			line := lines[position]
			match test.mode {
				'drop' { lines.delete(position) }
				'duplicate' { lines.insert(position, line) }
				else {
					mut tokens := line.split(' ')
					mut count := 0
					mut output := []string{}
					for token in tokens {
						if token.starts_with(test.key + '=') {
							count++
							if test.mode != 'remove' {
								output << test.key + '=' + (test.value as string)
							}
						} else {
							output << token
						}
					}
					assert count == 1
					lines[position] = output.join(' ')
				}
			}
			os.write_file(path, lines.join('\n') + '\n')!
		}
	}
}

fn fixture(ctx r.Context, base string) ! {
	os.mkdir_all(base + '/validator/comparecore')!
	for name in ['source-snapshots.json', 'campaign-plan.json'] {
		os.cp(ctx.here + '/' + name, base + '/' + name)!
	}
	os.write_file(base + '/bench.c', ctx.preserved_source('bench.c')!)!
	for name in ['compare.v', 'comparecore/core.v'] {
		os.cp(ctx.validator + '/' + name, base + '/validator/' + name)!
	}
	os.mkdir(base + '/validation')!
	for name in ['kernel-x86_64.json', 'libc-builds.json', 'libc.patch'] {
		os.cp(ctx.here + '/validation/' + name, base + '/validation/' + name)!
	}
	history := ctx.root + '/tests/alloc-bench/results/2026-10-02-userspace/earlier-candidate/final-v3-versus-catalina2'
	builds := r.object(base + '/validation/libc-builds.json')!
	build := b.value(builds, 'optimized-${ctx.profile.version}-final') as map[string]b.Value
	manifest := b.value(build, 'manifest')
	plan := r.object(base + '/campaign-plan.json')!
	declared := r.utc_time(b.value(plan, 'declared_utc'), 'fixture declaration')!
	for index, name in r.order {
		guest := if name.starts_with('vinix') { 'vinix' } else { 'catalina' }
		target := base + '/' + name
		os.mkdir(target)!
		os.cp(history + '/' + guest + '/serial.log', target + '/serial.log')!
		mut config := r.object(history + '/' + guest + '/config.json')!
		if guest == 'vinix' {
			config['kernel_sha256'] = b.Value(ctx.profile.kernel)
			config['libc_sha256'] = b.Value(ctx.profile.loader)
			config['libc_a_sha256'] = b.Value(ctx.profile.static_hash)
			config['libc_build'] = manifest
		}
		write(target + '/config.json', b.Value(config))!
		started := declared.add_seconds((index * 2 + 1) * 60)
		finished := declared.add_seconds((index * 2 + 2) * 60)
		start_text := started.format_ss_micro().replace(' ', 'T') + '+00:00'
		finish_text := finished.format_ss_micro().replace(' ', 'T') + '+00:00'
		driver := map[string]b.Value{
			'argv':         r.strings(['fixture-only', guest])
			'exit_code':    r.num(0)
			'started_utc':  b.Value(start_text)
			'finished_utc': b.Value(finish_text)
		}
		write(target + '/driver-exit.json', b.Value(driver))!
	}
}

pub struct Finding {
pub:
	test      string
	passed    bool
	rejection string @[omitempty]
}

pub struct Findings {
pub:
	passed          bool
	check_count     int
	method          string
	source_captures map[string]string
	scripts_sha256  map[string]string
	checks          []Finding
}

fn positive(data r.Report) ! {
	if data.cohort_count != 2 || data.all_cohorts_at_or_faster || data.all_pooled_workloads_at_or_faster {
		return error('Positive old-data fixture must report failed parity')
	}
	for row in data.pooled_workloads {
		for distribution in [row.vinix, row.catalina] {
			if distribution.sample_count != 14 || distribution.observations.len != 14 {
				return error('Every old-data observation must participate')
			}
			// Independent oracle: sort observations by cross-products of exact raw
			// integer durations (all pairs equal), then compute the two middle rates.
			mut raw := distribution.observations.clone()
			raw.sort(a.elapsed_ns < b.elapsed_ns)
			pairs := raw[0].pairs
			assert raw.all(it.pairs == pairs)
			median := (f64(raw[6].elapsed_ns) / f64(pairs) + f64(raw[7].elapsed_ns) / f64(pairs)) / 2
			if distribution.median_ns_per_pair != median || distribution.min_ns_per_pair != f64(raw[0].elapsed_ns) / f64(pairs) || distribution.max_ns_per_pair != f64(raw[13].elapsed_ns) / f64(pairs) {
				return error('Independent raw-sample statistic differs')
			}
		}
	}
}

pub fn suite(ctx r.Context) !Findings {
	temp := temporary('vinix-report-integrity-')!
	defer { os.rmdir_all(temp) or {} }
	base := temp + '/base'
	os.mkdir(base)!
	fixture(ctx, base)!
	positive(r.Context{ root: ctx.root, here: base, validator: base + '/validator', preserved_compare: ctx.preserved_compare, profile: ctx.profile }.recompute()!)!
	mut findings := [Finding{ test: 'positive old-data fixture retains all 14 observations and reports failed parity', passed: true }]
	tests := cases(ctx.profile)
	assert tests.len == 170 // 169 original negative cases, plus native CLI tampering.
	for index, test in tests {
		archive.checkpoint()!
		work := '${temp}/case-${index}'
		os.cp_all(base, work, false)!
		test.apply(work)!
		changed := r.Context{ root: ctx.root, here: work, validator: work + '/validator', preserved_compare: ctx.preserved_compare, profile: ctx.profile }
		mut rejected := false
		mut reason := ''
		changed.recompute() or {
			if err.code() in [130, 143] { return err }
			rejected = true
			reason = if err.msg().starts_with('Cannot load saved strict validator:') {
				err.msg()
			} else {
				'Cannot recompute: ' + err.msg()
			}
		}
		if !rejected { return error('Integrity violation accepted: ' + test.name) }
		findings << Finding{test.name, true, reason}
		os.rmdir_all(work)!
	}
	mut captures := map[string]string{}
	for guest in ['vinix', 'catalina'] {
		captures[guest] = archive.digest(os.read_file(ctx.root + '/tests/alloc-bench/results/2026-10-02-userspace/earlier-candidate/final-v3-versus-catalina2/' + guest + '/serial.log')!)
	}
	mut scripts := map[string]string{}
	for name in ['recompute.v', 'compare.v', 'check-recompute.v'] {
		scripts[name] = archive.digest(os.read_file(ctx.here + '/' + name)!)
	}
	scripts['comparecore/core.v'] = archive.digest(os.read_file(ctx.validator + '/comparecore/core.v')!)
	scripts['reportcore/report.v'] = archive.digest(os.read_file(ctx.validator + '/reportcore/report.v')!)
	return Findings{true, findings.len, 'Only temporary fixtures: duplicate preserved actual v3 serial captures, substitute synthetic ${ctx.profile.version} config/timestamps to exercise final validation, then reject one integrity violation per case. Fixture measurements are never saved or published as ${ctx.profile.version} timings.', captures, scripts, findings}
}

pub fn run(root string, here string, campaign string, args []string) int {
	mut output := ''
	mut index := 0
	for index < args.len {
		arg := args[index]
		index++
		if arg in ['-h', '--help'] {
			println('usage: check-recompute [-h] [--output OUTPUT]\n\nExercise report integrity checks using old captures only in temporary fixtures.')
			return 0
		}
		if arg.starts_with('--output=') {
			output = arg.all_after('=')
		} else if arg.len > 2 && '--output'.starts_with(arg) && index < args.len {
			output = args[index]
			index++
		} else {
			eprintln('check-recompute: error: unrecognized arguments: ' + arg)
			return 2
		}
	}
	guard := archive.own_commands()
	defer { guard.close() }
	ctx := r.context(root, here, campaign) or {
		eprintln('Cannot check report integrity: ${err}')
		return if err.code() in [130, 143] { err.code() } else { 1 }
	}
	result := suite(ctx) or {
		eprintln('Cannot check report integrity: ${err}')
		return if err.code() in [130, 143] { err.code() } else { 1 }
	}
	if output != '' {
		os.write_file(output, json2.encode(result, prettify: true) + '\n') or {
			eprintln('Cannot save report findings: ${err}')
			return 1
		}
	}
	println('Report integrity PASS: ${result.check_count} checks; temporary fixtures only, no new timings.')
	return 0
}
