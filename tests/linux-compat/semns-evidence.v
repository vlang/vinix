// SPDX-License-Identifier: GPL-2.0-or-later
// Audit the bounded native semaphore IPC namespace qualification without external tools.
module main

import crypto.sha256
import json2
import os

const candidate_source = 'b7f1c1c6bb8926ac79804a3e263428778872df96d6d7e85851deb71fb8729fe0'
const candidate_hook = '7c06d49862ece2b1b36bc6b600fad71038eca405939b5c1089b98a2ed2dac436'
const integration_base = '11fb7f395f04ac7f56aab7b97c3b6226f18413fa'
const integration_candidate = 'b30fa5233f3a1d8c8673e8d31f3889cedf769a35'

struct Manifest {
	files   map[string]string
	origins map[string]string
	omitted map[string]string
}

struct Build {
	architecture            string
	profile                 string
	base_commit             string
	candidate_commit        string
	candidate_source_sha256 string
	build_executed          bool
	build_exit_code         int
	inputs_before           map[string]string
	inputs_after            map[string]string
	outputs                 map[string]string
}

struct Native {
	architecture  string
	exit_code     int
	inputs        map[string]string
	serial_sha256 string
}

struct Reference {
	architecture string
	passed       bool
	finished     bool
	status       int
	artifacts    map[string]string
}

struct Compile {
	architecture string
	inputs       map[string]string
	outputs      map[string]string
}

struct MaintainedCase {
	name          string
	source_sha256 string
	source_inputs map[string]string
	init_sha256   string
	iso_sha256    string
	exit_code     int
	detail        string
}

struct Maintained {
	architecture  string
	kernel_sha256 string
	results       []MaintainedCase
}

struct Selection {
	state      string
	controller string
}

fn safe_relative(name string) ! {
	require(name != '' && !os.is_abs_path(name) && '..' !in name.split('/'), 'Unsafe evidence path')!
}

fn selected_result(selected MaintainedCase, source Maintained, architecture string, kernel string) ! {
	require(source.architecture == architecture && source.kernel_sha256 == kernel, 'Different retry kernel or architecture')!
	matches := source.results.filter(it.name == selected.name)
	require(matches.len == 1 && matches[0] == selected && selected.exit_code == 0 && selected.detail == '', 'Selected result differs from original attempt')!
}

fn controller_binding(args []string, source Maintained, selected string, origin string, expected string, pins map[string]string) ! {
	require(args.len == 11, 'Wrong maintained command length')!
	require(args[1] == '--arch' && args[2] == source.architecture && args[3] == '--kernel-dir'
		&& args[5] == '--state-dir' && args[7] == '--cases' && args[9] == '--timeout', 'Wrong maintained command')!
	require(origin == expected && origin != '', 'Controller state differs from selected attempt')!
	require(pins[args[4] + '/bin/vinix'] == source.kernel_sha256 && args[0] in pins, 'Controller kernel or runner not pinned')!
	cases := args[8].split(',')
	require(selected in cases && cases.len == source.results.len, 'Controller cases differ from receipt')!
	for row in source.results {
		require(cases.filter(it == row.name).len == 1, 'Controller cases differ from receipt')!
	}
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn require(good bool, message string) ! {
	if !good { return error(message) }
}

fn elf(bytes []u8, architecture string) ! {
	machine := if architecture == 'arm' {
		183
	} else if architecture == 'x86' {
		62
	} else {
		0
	}
	require(machine != 0 && bytes.len >= 20 && bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
		&& int(bytes[18]) + (int(bytes[19]) << 8) == machine, 'Wrong ELF architecture: ' + architecture)!
}

fn namespace_storage(text string, baseline bool) ! {
	mut rows := 0
	mut seen := map[u64]bool{}
	mut grew := false
	mut retained := false
	mut storage := 0
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line.starts_with('LINUX SEMNS SLAB:') {
			words := line.fields()
			require(words.len == 7, 'Malformed slab row')!
			size := words[3].all_after('size=').parse_uint(10, 64)!
			before := words[4].all_after('before=').parse_uint(10, 64)!
			occupied := words[5].all_after('occupied=').parse_uint(10, 64)!
			after := words[6].all_after('after=').parse_uint(10, 64)!
			require(size > 0 && size !in seen && words[3].starts_with('size=') && words[4].starts_with('before=') && words[5].starts_with('occupied=') && words[6].starts_with('after='), 'Invalid slab row')!
			seen[size] = true
			rows++
			grew = grew || occupied >= before + 200
			retained = retained || after > before
		}
		if line.starts_with('LINUX SEMNS STORAGE:') {
			words := line.fields()
			require(words.len == 7 && words[3] == 'arrays=200' && words[4] == 'semaphores=6400' && words[5].starts_with('big_pages='), 'Malformed namespace storage result')!
			pages := words[5].all_after('big_pages=').split('/')
			require(pages.len == 3, 'Missing page counters')!
			before := pages[0].parse_uint(10, 64)!
			_ := pages[1].parse_uint(10, 64)!
			after := pages[2].parse_uint(10, 64)!
			require(words[6] == if baseline { 'FAIL' } else { 'PASS' }, 'Wrong storage verdict')!
			if !baseline { require(after <= before, 'Retained large pages')! }
			storage++
		}
	}
	require(storage == 1 && rows >= 14 && grew && retained == baseline, 'Missing storage measurement or retained slab objects')!
}

fn unchanged_counter(word string, label string) ! {
	require(word.starts_with(label), 'Missing storage counter')!
	values := word[label.len..].split('/')
	require(values.len == 2, 'Malformed storage counter')!
	before := values[0].parse_uint(10, 64)!
	after := values[1].parse_uint(10, 64)!
	require(before == after, 'Maintained storage counter changed')!
}

fn maintained_cohort(line string, kind string) !string {
	words := line.fields()
	if kind == 'cloneipc' {
		require(words.len == 8, 'Malformed clone storage result')!
		require(words[3] in ['ordinary=0', 'ordinary=1'] && words[4] in ['namespace=0', 'namespace=1']
			&& words[5] == 'cycles=200' && words[7] == 'PASS', 'Unknown or failing clone storage cohort')!
		unchanged_counter(words[6], 'big_pages=')!
		return words[3] + '/' + words[4]
	}
	require(words.len == 9 && words[8] == 'PASS', 'Malformed maintained storage result')!
	require(words[3] in ['kind=0', 'kind=1', 'kind=2', 'kind=3'] && words[4] == 'cycles=200'
		&& words[7] == 'errors=0', 'Unknown or failing maintained storage cohort')!
	unchanged_counter(words[5], 'big_pages=')!
	unchanged_counter(words[6], 'written_after_free=')!
	return words[3]
}

fn serial(text string, kind string) ! {
	baseline := kind in ['baseline-arm', 'baseline-x86']
	reference := kind == 'reference'
	namespace := kind in ['native', 'semns', 'reference', 'baseline-arm', 'baseline-x86']
	name := if namespace { 'SEMNS' } else { kind.to_upper() }
	counts := {
		'seminfo':  11965
		'semmeta':  28713
		'semperm':  256552
		'semrange': 4200
		'semarray': 457
		'sempid':   261
		'semword':  276
		'semabi':   175
		'semwait':  11163
	}
	checks := if namespace {
		if reference { 445 } else { 446 }
	} else {
		counts[kind] or { 0 }
	}
	summary := 'LINUX ' + name + ' SUMMARY: checks=' + checks.str() + ' failures=' + if baseline {
		'36'
	} else {
		'0'
	}
	marker := 'LINUX ' + name + if reference {
		' REFERENCE: PASS'
	} else if baseline {
		': FAIL'
	} else {
		': PASS'
	}
	mut summaries := 0
	mut markers := 0
	mut mismatches := 0
	mut storage := 0
	mut cohorts := map[string]bool{}
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line == summary {
			summaries++
		} else if line.starts_with('LINUX ' + name + ' SUMMARY:') {
			return error('Unexpected summary')
		}
		if line == marker { markers++ }
		if line.starts_with('LINUX ' + name + ' MISMATCH:') { mismatches++ }
		if line.contains('KERNEL PANIC') || line.contains('Kernel panic') || line.contains('FATAL EXCEPTION') || line.contains('REFERENCE FAIL') || line.contains('LINUX ' + name + ' FAIL:') {
			return error('Unexpected guest failure')
		}
		if !baseline && line.contains('LINUX ' + name + ': FAIL') {
			return error('Unexpected failing result')
		}
		if baseline && line.contains('LINUX ' + name + ': PASS') {
			return error('Baseline falsely passed')
		}
		if !namespace && line.starts_with('LINUX ' + name + ' STORAGE:') {
			cohort := maintained_cohort(line, kind)!
			require(cohort !in cohorts, 'Repeated maintained storage cohort')!
			cohorts[cohort] = true
			storage++
		}
	}
	require(markers == 1 && summaries == if checks == 0 { 0 } else { 1 }, 'Missing or repeated result')!
	require(mismatches == if baseline { 12 } else { 0 }, 'Unexpected mismatch count')!
	if reference {
		require(text.contains('Linux version 6.12.51'), 'Reference kernel version missing')!
	}
	if namespace && !reference { namespace_storage(text, baseline)! }
	if kind in ['semwait', 'procns', 'cloneipc'] {
		require(storage == 4, 'Missing maintained storage cohort')!
	}
}

fn linked(root string, manifest Manifest, pins map[string]string) ! {
	for origin, pin in pins {
		if relative := manifest.origins[origin] {
			require(digest(root + '/' + relative)! == pin, 'Receipt differs from retained artifact: ' + relative)!
		} else {
			require(manifest.omitted[origin] == pin, 'Missing artifact or explicit external pin: ' + origin)!
		}
	}
}

fn input_pin(pins map[string]string, ending string) !string {
	mut found := ''
	for path, pin in pins {
		if path.ends_with(ending) {
			require(found == '', 'Ambiguous input: ' + ending)!
			found = pin
		}
	}
	require(found != '', 'Missing input: ' + ending)!
	return found
}

fn audit(root string) ! {
	manifest := json2.decode[Manifest](os.read_file(root + '/manifest.json')!)!
	require(manifest.files.len > 30 && manifest.origins.len > 30, 'Incomplete manifest')!
	for name, pin in manifest.files {
		require(!os.is_abs_path(name) && '..' !in name.split('/'), 'Unsafe manifest path')!
		require(digest(root + '/' + name)! == pin, 'Changed artifact: ' + name)!
	}
	for _, name in manifest.origins { require(name in manifest.files, 'Unhashed origin')! }
	require(digest(root + '/source/kernel/sysvsem/sysvsem.v')! == candidate_source, 'Wrong candidate source')!
	require(digest(root + '/source/kernel/syscall/table/sysv_message.v')! == candidate_hook, 'Wrong namespace release hook')!
	for suffix in ['arm', 'x86'] {
		architecture := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
		path := root + '/' + suffix
		probe := digest(path + '/compile/probe')!
		elf(os.read_bytes(path + '/compile/probe')!, suffix)!
		compiled := json2.decode[Compile](os.read_file(path + '/compile/receipt.json')!)!
		require(compiled.architecture == suffix && compiled.inputs.len >= 5 && compiled.outputs.len >= 5, 'Incomplete probe compile')!
		linked(root, manifest, compiled.inputs)!
		linked(root, manifest, compiled.outputs)!
		require(input_pin(compiled.inputs, '/semnsfixture/core.v')! ==
			digest(root + '/source/fixture/semnsfixture/core.v')!, 'Different compiled fixture source')!
		require(input_pin(compiled.inputs, '/semnsreferenceinit/core.v')! ==
			digest(root + '/source/fixture/semnsreferenceinit/core.v')!, 'Different compiled wrapper source')!
		require(input_pin(compiled.outputs, '/probe')! == probe
			&& input_pin(compiled.outputs, '/reference-init')! == digest(path + '/compile/reference-init')!,
			'Different compiled executables')!
		build := json2.decode[Build](os.read_file(path + '/build/receipt.json')!)!
		require(build.architecture == suffix && build.profile == 'prod' && build.build_executed
			&& build.build_exit_code == 0 && build.base_commit == integration_base
			&& build.candidate_commit == integration_candidate && build.candidate_source_sha256 == candidate_source,
			'Wrong build identity or result')!
		require(build.inputs_before.len > 100 && build.inputs_before == build.inputs_after, 'Build inputs changed')!
		require(input_pin(build.inputs_before, '/kernel-' + suffix + '/kernel/sysvsem/sysvsem.v')! == candidate_source,
			'Build used different semaphore source')!
		require(input_pin(build.inputs_before, '/kernel-' + suffix + '/kernel/syscall/table/sysv_message.v')! == candidate_hook,
			'Build used different namespace release hook')!
		linked(root, manifest, build.inputs_before)!
		linked(root, manifest, build.outputs)!
		require(os.read_file(path + '/build/build.log.status')!.trim_space() == '0', 'Build command failed')!
		kernel := digest(path + '/build/kernel/bin/vinix')!
		elf(os.read_bytes(path + '/build/kernel/bin/vinix')!, suffix)!
		elf(os.read_bytes(path + '/baseline/kernel/bin/vinix')!, suffix)!
		original := if suffix == 'arm' {
			'4fb6c16168f1e3eac43c9f8dabfcb01fc0704ab06c0139b07b926371a0648541'
		} else {
			'33a50d250c174934a428ad8b674df7778559b09515e8013a68bac325c61b3f52'
		}
		require(digest(path + '/baseline/kernel/bin/vinix')! == original, 'Wrong original kernel')!
		for kind in ['baseline', 'native'] {
			record := json2.decode[Native](os.read_file(path + '/' + kind + '/receipt.json')!)!
			require(record.architecture == architecture && record.exit_code == if kind == 'baseline' {
				1
			} else {
				0
			},
				'Wrong native result')!
			require(os.read_file(path + '/' + kind + '/status')!.trim_space() == record.exit_code.str(), 'Native status disagrees')!
			linked(root, manifest, record.inputs)!
			require(digest(path + '/' + kind + '/kernel/bin/vinix')! == input_pin(record.inputs, '/kernel/bin/vinix')!, 'Copied kernel differs from input')!
			require(digest(path + '/' + kind + '/rootfs/sbin/init')! == input_pin(record.inputs, '/probe')!, 'Copied probe differs from input')!
			text := os.read_file(path + '/' + kind + '/serial.log')!
			require(digest(path + '/' + kind + '/serial.log')! == record.serial_sha256, 'Native serial hash')!
			serial(text, if kind == 'baseline' { kind + '-' + suffix } else { kind })!
			if kind != 'baseline' {
				require(digest(path + '/' + kind + '/kernel/bin/vinix')! == kernel, 'Different regression kernel')!
			}
			require(digest(path + '/' + kind + '/rootfs/sbin/init')! == probe, 'Different ABI probe')!
		}
		reference := json2.decode[Reference](os.read_file(path + '/reference/receipt.json')!)!
		require(reference.architecture == architecture && reference.passed && reference.finished && reference.status == 0,
			'Reference did not pass')!
		require(reference.artifacts['probe'] == probe && digest(path + '/reference/probe')! == probe,
			'Different Linux probe')!
		require(reference.artifacts['serial'] == digest(path + '/reference/serial.log')!, 'Reference serial hash')!
		require(reference.artifacts['controller_source'] == digest(root + '/tooling/semns-reference.v')!, 'Different reference controller')!
		require(reference.artifacts['wrapper_source'] == digest(root + '/source/fixture/semnsreferenceinit/core.v')!, 'Different wrapper source')!
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + '/reference/inputs.json')!)!)!
		serial(os.read_file(path + '/reference/serial.log')!, 'reference')!
		require(digest(path + '/reference/init')! == digest(path + '/compile/reference-init')!, 'Different Linux wrapper')!
		maintained := json2.decode[Maintained](os.read_file(path + '/maintained/receipt.json')!)!
		require(maintained.architecture == architecture && maintained.kernel_sha256 == kernel
			&& maintained.results.len == 12, 'Wrong maintained runner identity')!
		mut seen := map[string]bool{}
		selection := json2.decode[map[string]Selection](os.read_file(path + '/maintained/selection.json')!)!
		require(selection.len == 12, 'Incomplete maintained selection provenance')!
		for result in maintained.results {
			require(result.name in ['semns', 'cloneipc', 'procns', 'semwait', 'seminfo', 'semmeta',
				'semperm', 'semrange', 'semarray', 'sempid', 'semword', 'semabi'] && result.name !in seen && result.exit_code == 0 && result.detail == '', 'Maintained runner failed')!
			seen[result.name] = true
			attempt := selection[result.name] or { return error('Missing selected attempt') }
			safe_relative(attempt.state)!
			safe_relative(attempt.controller)!
			require(attempt.state.starts_with('attempts/states/') && attempt.controller.starts_with('maintained-' + suffix + '-'), 'Wrong attempt provenance')!
			source := json2.decode[Maintained](os.read_file(root + '/' + attempt.state + '/receipt.json')!)!
			selected_result(result, source, architecture, kernel)!
			// A batch may fail another case. Preserve its status and every original
			// result; selecting a passing row never rewrites that batch as passing.
			failed := source.results.any(it.exit_code != 0 || it.detail != '')
			require(os.read_file(root + '/attempts/' + attempt.controller + '.status')!.trim_space() == if failed {
				'1'
			} else {
				'0'
			}, 'Attempt status disagrees with original receipt')!
			controller_inputs := json2.decode[map[string]string](os.read_file(root + '/' + attempt.state + '/controller-inputs.json')!)!
			linked(root, manifest, controller_inputs)!
			args := json2.decode[[]string](os.read_file(root + '/' + attempt.state + '/controller-command.json')!)!
			require(args.len == 11, 'Wrong maintained command length')!
			controller_binding(args, source, result.name, manifest.origins[args[6] + '/receipt.json'], attempt.state + '/receipt.json', controller_inputs)!
			for artifact in ['init', 'test.iso', 'serial.log'] {
				require(digest(path + '/maintained/' + result.name + '/' + artifact)! == digest(root + '/' + attempt.state + '/' + result.name + '/' + artifact)!, 'Selected artifact differs from original attempt')!
			}
			require(result.source_sha256 == digest(root + '/source/fixture/' + result.name + 'fixture/core.v')!
				&& result.init_sha256 == digest(path + '/maintained/' + result.name + '/init')!
				&& result.iso_sha256 == digest(path + '/maintained/' + result.name + '/test.iso')!, 'Different maintained fixture')!
			linked(root, manifest, result.source_inputs)!
			elf(os.read_bytes(path + '/maintained/' + result.name + '/init')!, suffix)!
			serial(os.read_file(path + '/maintained/' + result.name + '/serial.log')!, result.name)!
		}
		build_tag := if suffix == 'arm' { 'build-arm-second' } else { 'build-x86-third' }
		for name in ['compile-' + suffix + '-fourth', build_tag, 'linux-' + suffix + '-fourth',
			'native-' + suffix + '-fourth'] {
			require(os.read_file(root + '/attempts/' + name + '.status')!.trim_space() == '0', 'Recorded controller failed: ' + name)!
		}
		require(os.read_file(root + '/attempts/baseline-' + suffix + '-fourth.status')!.trim_space() == '1', 'Original kernel unexpectedly passed')!

		baseline_pins := json2.decode[map[string]string](os.read_file(path + '/build/baseline-inputs.json')!)!
		require(input_pin(baseline_pins, '/kernel/bin/vinix')! == digest(path + '/baseline/kernel/bin/vinix')!, 'Wrong baseline build')!
	}
	reviews := json2.decode[[]map[string]string](os.read_file(root + '/review/generated-review.json')!)!
	require(reviews.len == 2, 'Missing generated-C review')!
	mut reviewed := map[string]bool{}
	for review in reviews {
		suffix := review['architecture']
		require(suffix in ['arm', 'x86'] && suffix !in reviewed, 'Wrong review architecture')!
		reviewed[suffix] = true
		require(review['generated_c_sha256'] == digest(root + '/' + suffix + '/build/blob.c')!
			&& review['excerpt_sha256'] == digest(root + '/review/generated-review-' + suffix + '.c.txt')!
			&& review['result'].starts_with('PASS:'), 'Generated-C review differs from build')!
	}
	require(os.read_file(root + '/attempts/reference-parser.status')!.trim_space() == '0'
		&& os.read_file(root + '/attempts/reference-parser.log')!.contains('PASS (2 positive, 9 negative)'), 'Linux parser controls failed')!
	println('Native semaphore namespace evidence: PASS (both architectures; hashes, builds, Linux, baseline, storage and 12 maintained suites)')
}

fn controls() ! {
	mut rows := ''
	for i in 1 .. 19 {
		rows += 'LINUX SEMNS SLAB: size=' + (i * 16).str() + ' before=10 occupied=210 after=10\n'
	}
	good := rows + 'LINUX SEMNS STORAGE: arrays=200 semaphores=6400 big_pages=12/13/12 PASS\nLINUX SEMNS SUMMARY: checks=446 failures=0\nLINUX SEMNS: PASS\n'
	serial(good, 'native')!
	serial('Linux version 6.12.51\nLINUX SEMNS SUMMARY: checks=445 failures=0\nLINUX SEMNS REFERENCE: PASS\n', 'reference')!
	baseline := good.replace('after=10', 'after=210').replace('12/13/12 PASS', '12/13/13 FAIL').replace('failures=0', 'failures=36').replace('SEMNS: PASS', 'SEMNS: FAIL') + 'LINUX SEMNS MISMATCH: injected\n'.repeat(12)
	serial(baseline, 'baseline-arm')!
	serial(baseline, 'baseline-x86')!
	mut refused := 0
	for bad in [good.replace('checks=446', 'checks=445'), good.replace('failures=0', 'failures=1'),
		good.replace('LINUX SEMNS: PASS\n', ''), good + good,
		good + 'LINUX SEMNS MISMATCH: injected\n', good + 'KERNEL PANIC injected\n',
		good.replace('after=10', 'after=11'), good.replace('12/13/12 PASS', '12/13/14 PASS'),
		good.replace('occupied=210', 'occupied=11'), good.replace(rows, ''),
		good.replace('arrays=200', 'arrays=199')] {
		serial(bad, 'native') or {
			refused++
			continue
		}
		return error('Accepted negative namespace control')
	}
	for bad in [baseline.replace('failures=36', 'failures=35'),
		baseline + 'LINUX SEMNS MISMATCH: extra\n', baseline.replace('after=210', 'after=10')] {
		serial(bad, 'baseline-arm') or {
			refused++
			continue
		}
		return error('Accepted negative baseline control')
	}
	mut readers := 'LINUX PROCNS: PASS\n'
	for i in 0 .. 4 {
		readers += 'LINUX PROCNS STORAGE: kind=' + i.str() + ' cycles=200 big_pages=12/12 written_after_free=0/0 errors=0 PASS\n'
	}
	serial(readers, 'procns')!
	for bad in [readers.replace('kind=0', 'kind=1'), readers.replace('kind=3', 'kind=4'),
		readers.replace('cycles=200', 'cycles=199'), readers.replace('12/12', '12/13'),
		readers.replace('written_after_free=0/0', 'written_after_free=0/1'),
		readers.replace('errors=0', 'errors=1'), readers.all_before_last('LINUX PROCNS STORAGE:')] {
		serial(bad, 'procns') or {
			refused++
			continue
		}
		return error('Accepted negative maintained storage control')
	}
	mut clones := 'LINUX CLONEIPC: PASS\n'
	for ordinary in 0 .. 2 {
		for namespace in 0 .. 2 {
			clones += 'LINUX CLONEIPC STORAGE: ordinary=' + ordinary.str() + ' namespace=' + namespace.str() + ' cycles=200 big_pages=12/12 PASS\n'
		}
	}
	serial(clones, 'cloneipc')!
	for bad in [clones.replace('ordinary=0', 'ordinary=2'),
		clones.replace('namespace=0', 'namespace=1')] {
		serial(bad, 'cloneipc') or {
			refused++
			continue
		}
		return error('Accepted negative clone storage control')
	}
	mut header := []u8{len: 20}
	header[0] = 127
	header[1] = `E`
	header[2] = `L`
	header[3] = `F`
	header[4] = 2
	header[5] = 1
	header[18] = 183
	elf(header, 'arm')!
	elf(header, 'x86') or { refused++ }
	row := MaintainedCase{ name: 'semns', init_sha256: 'probe', iso_sha256: 'iso' }
	original := Maintained{ architecture: 'aarch64', kernel_sha256: 'kernel', results: [row] }
	selected_result(row, original, 'aarch64', 'kernel')!
	for bad in [Maintained{ ...original, architecture: 'x86_64' },
		Maintained{ ...original, kernel_sha256: 'other' }, Maintained{ ...original, results: [] },
		Maintained{ ...original, results: [row, row] },
		Maintained{ ...original, results: [MaintainedCase{ ...row, exit_code: 1 }] },
		Maintained{ ...original, results: [MaintainedCase{ ...row, init_sha256: 'other' }] }] {
		selected_result(row, bad, 'aarch64', 'kernel') or {
			refused++
			continue
		}
		return error('Accepted changed retry provenance')
	}
	for bad in ['', '/absolute', 'attempts/../outside'] {
		safe_relative(bad) or {
			refused++
			continue
		}
		return error('Accepted unsafe attempt path')
	}
	args := ['runner', '--arch', 'aarch64', '--kernel-dir', 'kernel', '--state-dir', 'state', '--cases', 'semns', '--timeout', '7200']
	pins := {'runner': 'runner-pin', 'kernel/bin/vinix': 'kernel'}
	controller_binding(args, original, 'semns', 'attempt', 'attempt', pins)!
	for bad in [args[..10], args.clone().map(if it == 'aarch64' { 'x86_64' } else { it }),
		args.clone().map(if it == 'kernel' { 'other' } else { it }),
		args.clone().map(if it == 'semns' { 'procns' } else { it })] {
		controller_binding(bad, original, 'semns', 'attempt', 'attempt', pins) or { refused++; continue }
		return error('Accepted changed controller binding')
	}
	controller_binding(args, original, 'semns', 'other', 'attempt', pins) or { refused++ }
	require(refused == 38, 'Evidence control accepted')!
	println('Semaphore namespace evidence controls: PASS (38 negative controls)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		controls() or {
			eprintln(err)
			exit(1)
		}
	} else if os.args.len == 3 && os.args[1] == 'check' {
		audit(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
	} else {
		eprintln('Usage: semns-evidence --self-test | check EVIDENCE-DIR')
		exit(2)
	}
}
