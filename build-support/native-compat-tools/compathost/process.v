// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import guesthost
import hosttest
import json2
import os
import regex
import strconv

fn positive_option(parsed hosttest.Arguments, name string, fallback int) !int {
	if name !in parsed.options { return fallback }
	value := strconv.atoi(parsed.options[name]) or { return error_with_code('Invalid integer: ' + name, 2) }
	if value <= 0 { return error_with_code(name + ' must be positive', 2) }
	return value
}

// Validation happens through the shared argparse-compatible parser first.
// Walk consumed options afterward so append actions preserve their order.
fn appended_options(args []string, names []string) map[string][]string {
	mut result := map[string][]string{}
	mut index := 0
	for index < args.len {
		argument := args[index]
		if argument == '--' { break }
		name := argument.all_before('=')
		for wanted in names {
			if name.starts_with('--') && wanted.starts_with(name) {
				value := if argument.contains('=') { argument.all_after('=') } else { args[index + 1] }
				result[wanted] << value
			}
		}
		if !argument.contains('=') && name.starts_with('--') && name != '--build-only' { index++ }
		index++
	}
	return result
}

fn snapshot_kernel(work string, source string, arch string) !string {
	target := work + '/kernel/bin/vinix'
	os.mkdir_all(os.dir(target))!
	hosttest.module_copy_file_preserving_stat(resolve(source)! + '/bin/vinix', target)!
	elf_arch(target, arch)!
	return work + '/kernel'
}

fn configure_process_launch(command []string, arch string, memory int, smp int, cpu string) []string {
	mut configured := command.clone()
	for index, argument in configured {
		if argument == '-m' { configured[index + 1] = memory.str() }
		if argument == '-smp' { configured[index + 1] = smp.str() }
		if argument == '-cpu' && arch == 'x86_64' { configured[index + 1] = cpu }
	}
	return configured
}

fn process_command(args []string, family string) !int {
	mut forwarded := []string{}
	if family == 'scheduler-qos' {
		forwarded << ['--source', root() + '/tests/scheduler-qos/guest.c', '--expect', 'SCHED-QOS PASS',
			'--fail', 'SCHED-QOS FAIL', '--smp', '4', '--memory', '8192']
	} else if family == 'tlb' {
		forwarded << ['--source', root() + '/tests/tlb/guest.c', '--expect', 'TLB: ALL PASS', '--fail', 'FAIL: TLB']
	}
	forwarded << args
	if family == 'memory-retention' {
		// This wrapper's fixed policy followed user arguments in the original.
		forwarded << ['--source', root() + '/tests/memory-retention/guest.c', '--expect', 'RETENTION PASS', '--fail', 'RETENTION FAIL']
	}
	parsed := hosttest.parse_arguments(forwarded, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--source', value: true },
		hosttest.Option{ name: '--expect', value: true },
		hosttest.Option{ name: '--fail', value: true },
		hosttest.Option{ name: '--define', value: true },
		hosttest.Option{ name: '--cpu', value: true },
		hosttest.Option{ name: '--smp', value: true },
		hosttest.Option{ name: '--memory', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--build-only' },
	], 0, 'Usage: run --arch aarch64|x86_64 [--kernel-dir DIR] [--source C] [--expect MARKER] [--fail MARKER] [--define DEFINE] [--cpu MODEL] [--smp N] [--memory MIB] [--timeout SECONDS] [--state-dir DIR] [--build-only]',
		'Run process, scheduler or TLB qualification with the unchanged C fixture.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--arch'])!
	arch := parsed.options['--arch']
	smp := positive_option(parsed, '--smp', 4)!
	if smp < 2 { return error_with_code('qualification requires at least two CPUs', 2) }
	memory := positive_option(parsed, '--memory', 4096)!
	timeout := positive_option(parsed, '--timeout', 600)!
	source := resolve(parsed.options['--source'] or { root() + '/tests/process-smp/guest.c' })!
	expected := parsed.options['--expect'] or { 'PROCESS-SMP PASS' }
	if expected == '' { return error_with_code('Expected marker must be nonempty', 2) }
	kernel := resolve(parsed.options['--kernel-dir'] or { root() + '/kernel' })!
	if !os.is_file(kernel + '/bin/vinix') { return error_with_code('build the requested kernel first', 2) }
	work := if '--state-dir' in parsed.options {
		resolve(parsed.options['--state-dir'])!
	} else { hosttest.work_dir('', 'vinix-process-smp-')! }
	os.mkdir_all(work)!
	defer { if '--state-dir' !in parsed.options { retire(work) } }
	cc, link := target_compiler(arch)!
	// Preserve linker flags before inputs, exactly as the original recipe.
	flags := [...cc, ...link, ...if arch == 'aarch64' { ['-fno-stack-protector'] } else { []string{} },
		'-static', '-pthread', '-O2', '-Wall', '-Wextra', '-Werror']
	guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
	append := appended_options(forwarded, ['--define', '--fail'])
	defines := append['--define'].map('-D' + it)
	init := work + '/init'
	compile_command := [...flags, ...defines, work + '/serial.o', source, '-o', init]
	run(compile_command)!
	elf_arch(init, arch)!
	archive := guesthost.image(init, work)!
	private_kernel := snapshot_kernel(work, kernel, arch)!
	mut receipt := {
		'family': json2.Any(family)
		'arch': json2.Any(arch)
		'compile_command': json2.Any(hosttest.strings(compile_command))
		'source_sha256': json2.Any(hosttest.sha(source)!)
		'init_sha256': json2.Any(hosttest.sha(init)!)
		'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!)
		'archive_sha256': json2.Any(hosttest.sha(archive)!)
	}
	hosttest.write_json(work + '/inputs.json', receipt)!
	if '--build-only' in parsed.options { return 0 }
	configured := guesthost.launch(init, archive, work, private_kernel, arch, true)!
	argv := configure_process_launch(configured.command, arch, memory, smp, parsed.options['--cpu'] or { 'max' })
	receipt['command'] = hosttest.strings(argv)
	hosttest.write_json(work + '/inputs.json', receipt)!
	println('Guest artifacts: ' + work)
	return guesthost.boot(argv, configured.env, work, [expected],
		['PROCESS-SMP FAIL', 'JOB-CHECK FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC', ...append['--fail']], timeout, true)!
}

fn backlog_command(args []string) !int {
	parsed := hosttest.parse_arguments(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--guest-state-dir', value: true },
		hosttest.Option{ name: '--original-reference', value: true },
		hosttest.Option{ name: '--build-only' },
	], 0, 'Usage: run --arch aarch64|x86_64 --state-dir FRESH-DIR [--original-reference C] [--build-only | --kernel-dir DIR --guest-state-dir FRESH-DIR]',
		'Build and run the seven independent Linux listen-backlog cases.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--arch', '--state-dir'])!
	if '--build-only' !in parsed.options { needed(parsed, ['--kernel-dir', '--guest-state-dir'])! }
	work := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-listen-backlog-')!
	arch := parsed.options['--arch']
	cc, link := target_compiler(arch)!
	flags := [...cc, '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-D_GNU_SOURCE=',
		'-fno-stack-protector', '-fno-strict-aliasing']
	control := parsed.options['--original-reference'] or { '' }
	fixture := work + '/fixture.o'
	if control != '' {
		os.cp(resolve(control)!, work + '/fixture.c')!
		run([...flags, '-Dmain=vinix_independent_fixture', '-c', work + '/fixture.c', '-o', fixture])!
	} else { guesthost.compile_module(root() + '/tests/listen-backlog/backlogfixture', fixture, arch, flags)! }
	imports := output([os.getenv_opt('NM') or { 'nm' }, '-u', fixture])!
	if allocator_imports(imports) { return error('Unexpected fixture allocation import:\n' + imports) }
	mut objects := [fixture]
	for name in ['fixturedriver', 'serialcore'] {
		object := work + '/' + name + '.o'
		guesthost.compile_module(root() + '/tests/kernel-gaps/' + name, object, arch, flags)!
		objects << object
	}
	init := work + '/init'
	run([...cc, '-static', ...objects, ...link, '-o', init])!
	elf_arch(init, arch)!
	hosttest.write_json(work + '/inputs.json', {
		'arch': json2.Any(arch)
		'original_reference': if control == '' { json2.Any(json2.null) } else { json2.Any(control) }
		'compiler_flags': json2.Any(hosttest.strings(flags))
		'imports': json2.Any(hosttest.strings(imports.split_into_lines()))
		'sources_sha256': json2.Any(hosttest.string_map(directory_hashes(work, '.c')!))
		'init_sha256': json2.Any(hosttest.sha(init)!)
	})!
	if '--build-only' in parsed.options { println(init); return 0 }
	state := hosttest.work_dir(parsed.options['--guest-state-dir'], 'vinix-backlog-guest-')!
	return guesthost.guest('', init, state, snapshot_kernel(work, parsed.options['--kernel-dir'], arch)!, arch,
		['LISTEN-BACKLOG-PASS cases=7', 'INDEPENDENT FIXTURE PASS'],
		['LISTEN-BACKLOG-FAIL', 'INDEPENDENT FIXTURE FAIL'], false, true, 60)!
}

fn directory_hashes(directory string, suffix string) !map[string]string {
	mut hashes := map[string]string{}
	mut names := os.ls(directory)!
	names.sort()
	for name in names {
		if os.is_file(directory + '/' + name) && (suffix == '' || name.ends_with(suffix)) {
			hashes[name] = hosttest.sha(directory + '/' + name)!
		}
	}
	return hashes
}

fn string_rows(rows [][]string) json2.Any {
	return json2.Any(rows.map(json2.Any(hosttest.strings(it))))
}

struct InspectionSpec {
	revision string
	module_name string
	expected []string
	failure string
	timeout int
}

fn inspection_spec(family string) !InspectionSpec {
	return match family {
		'resource-open' { InspectionSpec{ revision: '22c5d6ee193d107102888f359bfade8e34b592d2', module_name: 'resourcefixture', expected: ['RESOURCE OPEN semantics PASS', 'RESOURCE OPEN: PASS'], failure: 'FAIL: resource open', timeout: 180 } }
		'proc-thread-lock' { InspectionSpec{ revision: '8ca75d10e8b804cf26705ba9c04614965da81690', module_name: 'lockfixture', expected: ['VINIX PROC THREAD LOCK: PASS'], failure: 'FAIL: proc thread lock:', timeout: 180 } }
		'proc-map-lookup' { InspectionSpec{ revision: '47db8e1ce160c2829ad9df9fde6e1f1345d1f80c', module_name: 'mapfixture', expected: ['VINIX PROC MAP LOOKUP: PASS'], failure: 'FAIL: proc map lookup:', timeout: 1800 } }
		else { return error('Unknown inspection fixture') }
	}
}

fn inspection_compiler(arch string) ![]string {
	if arch == 'x86_64' {
		return compiler_prefix('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')!
	}
	gcc_root := root() + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl'
	mut versions := os.ls(gcc_root)!
	versions.sort()
	if versions.len == 0 { return error('Missing ARM musl GCC installation') }
	return [...compiler_prefix('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang')!, '--target=aarch64-linux-musl',
		'--sysroot=' + root() + '/build-aarch64-userland/sysroot', '--gcc-install-dir=' + gcc_root + '/' + versions.last()]
}

fn matched_rows(text string, pattern string, width int) ![][]string {
	mut compiled := regex.regex_opt(pattern)!
	matches := compiled.find_all_str(text)
	mut rows := [][]string{}
	for item in matches {
		compiled.match_string(item)
		mut row := []string{}
		for index in 0 .. width { row << compiled.get_group_by_id(item, index) }
		rows << row
	}
	return rows
}

// Python int comparisons were unbounded. Never narrow captured report values.
fn decimal_zero(value string) bool {
	unsigned := value.trim_left('+-')
	return unsigned.len > 0 && unsigned.bytes().all(it == `0`)
}

fn decimal_at_least(value string, minimum string) bool {
	unsigned := value.trim_left('0')
	return unsigned.len > minimum.len || (unsigned.len == minimum.len && unsigned >= minimum)
}

fn inspection_report(text string, family string, arch string) !map[string]json2.Any {
	classes := if arch == 'aarch64' { 18 } else { 14 }
	mut report := map[string]json2.Any{}
	if family == 'resource-open' {
		rows := matched_rows(text, r'RESOURCE-OPEN window=(\d+) class=(\d+) objects=([+-]?\d+)', 3)!
		large := matched_rows(text, r'RESOURCE-OPEN window=(\d+) large_pages=([+-]?\d+) written_after_free=(\d+) flat=(\d+)', 4)!
		if rows.len != 2 * classes || !rows.all(decimal_zero(it[2])) || large.len != 2
			|| !large.all(decimal_zero(it[1]) && decimal_zero(it[2]) && it[3].trim_left('0') == '1') {
			return error('RESOURCE OPEN retained objects/pages or written-after-free counters differ')
		}
		report['class_rows'] = string_rows(rows)
		report['large_rows'] = string_rows(large)
	} else if family == 'proc-map-lookup' {
		rows := matched_rows(text, r'PROC-MAP-RETENTION class=(\d+) live=([+-]?\d+) pages=([+-]?\d+)', 3)!
		large := matched_rows(text, r'PROC-MAP-RETENTION large=([+-]?\d+) uaf=([+-]?\d+)', 2)!
		cohorts := matched_rows(text, r'proc map lookup: completed growth cohort (\d+) children=(\d+)', 2)!
		progress := matched_rows(text, r'proc map lookup: (\d+) lookups, (\d+) directory snapshots', 2)!
		if rows.len != classes || !rows.all(decimal_zero(it[1]) && decimal_zero(it[2]))
			|| large != [['0', '0']] || cohorts != [['1', '12'], ['2', '12'], ['3', '12'], ['4', '12']]
			|| progress.len != 1 || !progress[0].all(decimal_at_least(it, '100')) {
			return error('PROC MAP retained counters, cohort count or inspection progress differs')
		}
		report['class_rows'] = string_rows(rows)
		report['large_rows'] = string_rows(large)
		report['cohort_rows'] = string_rows(cohorts)
		report['progress'] = string_rows(progress)
	} else {
		progress := matched_rows(text, r'proc thread lock: (\d+) snapshots, (\d+) process CPU clocks', 2)!
		if progress.len != 1 || !decimal_at_least(progress[0][0], '100') || !decimal_at_least(progress[0][1], '10')
			|| text.count('PASS: process inspection completes during sibling thread churn') != 1
			|| text.count('VINIX PROC THREAD LOCK: PASS') != 1 {
			return error('PROC THREAD LOCK inspection/clock progress or marker count differs')
		}
		report['progress'] = string_rows(progress)
	}
	return report
}

fn inspection_command(args []string, family string) !int {
	spec := inspection_spec(family)!
	parsed := hosttest.parse_arguments(args, [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--guest-state-dir', value: true },
		hosttest.Option{ name: '--build-only' },
	], 0, 'Usage: run --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR --guest-state-dir PREFIX [--build-only]',
		'Compare the immutable original C and maintained V process inspection fixtures.') or { return error_with_code(err.msg(), 2) }
	needed(parsed, ['--arch', '--kernel-dir', '--state-dir', '--guest-state-dir'])!
	arch := parsed.options['--arch']
	work := hosttest.work_dir(parsed.options['--state-dir'], 'vinix-inspection-')!
	raw := output(['git', '-C', root(), 'show', spec.revision + ':tests/' + family + '/test.c'])!
	write(work + '/original.c', raw)!
	compiler := inspection_compiler(arch)!
	mut flags := [...compiler, '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-strict-aliasing']
	if family != 'resource-open' { flags << '-pthread' }
	module_path := root() + '/tests/' + family + '/' + spec.module_name
	fixture := work + '/fixture.o'
	guesthost.compile_module(module_path, fixture, arch, [...flags, '-D_GNU_SOURCE'])!
	guesthost.compile_module(root() + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, flags)!
	run([...flags, '-c', work + '/original.c', '-o', work + '/original.o'])!
	imports := output(['/opt/homebrew/opt/llvm/bin/llvm-nm', '-u', fixture])!
	if allocator_imports(imports) { return error('Unexpected fixture allocation import:\n' + imports) }
	private_kernel := snapshot_kernel(work, parsed.options['--kernel-dir'], arch)!
	mut receipt := {
		'original_revision': json2.Any(spec.revision)
		'original_lines': json2.Any(raw.split_into_lines().len)
		'original_sha256': json2.Any(hosttest.text_sha(raw))
		'arch': json2.Any(arch)
		'compiler_flags': json2.Any(hosttest.strings(flags))
		'fixture_imports': json2.Any(hosttest.strings(imports.split_into_lines()))
		'source_hashes': json2.Any(hosttest.string_map(directory_hashes(module_path, '')!))
		'kernel_sha256': json2.Any(hosttest.sha(private_kernel + '/bin/vinix')!)
		'harness_timeout_seconds': json2.Any(spec.timeout)
	}
	if family != 'resource-open' {
		receipt['qemu_cpus'] = if arch == 'aarch64' {
			json2.Any(strconv.atoi(os.getenv_opt('VINIX_QEMU_SMP') or { '4' })!)
		} else { json2.Any(2) }
		receipt['fixture_alarm_seconds'] = if family == 'proc-map-lookup' { 600 } else { 120 }
	}
	mut variants := map[string]json2.Any{}
	mut previous := map[string]json2.Any{}
	for variant in ['original', 'v'] {
		program := work + '/' + variant + '-init'
		run([...compiler, ...if arch == 'aarch64' { ['-fuse-ld=lld'] } else { []string{} }, '-static',
			...if family == 'resource-open' { []string{} } else { ['-pthread'] },
			if variant == 'original' { work + '/original.o' } else { fixture }, work + '/serial.o', '-o', program])!
		elf_arch(program, arch)!
		state := resolve(parsed.options['--guest-state-dir'])! + '-' + variant
		mut item := { 'program_sha256': json2.Any(hosttest.sha(program)!) }
		variants[variant] = item
		receipt['variants'] = variants
		hosttest.write_json(work + '/validation.json', receipt)!
		if '--build-only' in parsed.options { continue }
		hosttest.work_dir(state, 'vinix-inspection-guest-')!
		archive := guesthost.image(program, state)!
		configured := guesthost.launch(program, archive, state, private_kernel, arch, true)!
		item['command'] = hosttest.strings(configured.command)
		positive, negative := guesthost.verdict_policy(spec.expected, [spec.failure], false)
		code := guesthost.boot(configured.command, configured.env, state, positive, negative, spec.timeout, false)!
		item['harness_exit'] = code
		variants[variant] = item
		receipt['variants'] = variants
		hosttest.write_json(work + '/validation.json', receipt)!
		os.cp(state + '/serial.log', work + '/' + variant + '-run.log')!
		if code != 0 { return code }
		serial := os.read_file(state + '/serial.log')!
		report := inspection_report(serial, family, arch)!
		if variant == 'v' && family != 'proc-thread-lock' {
			for name in ['class_rows', 'large_rows'] {
				before := previous[name] or { return error('Missing original retention rows') }
				after := report[name] or { return error('Missing V retention rows') }
				if json2.encode(before) != json2.encode(after) { return error('Original C/V retention rows differ') }
			}
		}
		previous = report.clone()
		for key, value in report { item[key] = value }
		item['passed'] = true
		item['serial_sha256'] = hosttest.sha(state + '/serial.log')!
		variants[variant] = item
		receipt['variants'] = variants
		hosttest.write_json(work + '/validation.json', receipt)!
		println('PASS ' + family + ' ' + variant + ' ' + arch + ': original inspection/retention assertions')
	}
	if '--build-only' !in parsed.options && family != 'proc-thread-lock' { receipt['original_V_retention_equal'] = true }
	hosttest.write_json(work + '/validation.json', receipt)!
	return 0
}
