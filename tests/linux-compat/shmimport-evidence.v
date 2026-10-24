// SPDX-License-Identifier: GPL-2.0-or-later
// Audit native shared-memory metadata-import status against Linux.
module main

import crypto.sha256
import json2
import os

const candidate_source = 'f67e8818f41bc2c61e728eba9a415d702119d4d1a1a7f289ca768d28bdbf989d'
const integration_base = '71c1556570c02d136dde1508d7866e7889666474'
const integration_candidate = '2c0e2d6a3f1079c500ca9dfe4c0a3f618bae4e2a'
const cases = ['shmimport', 'shmremove', 'shmtime', 'shmset', 'shmabi', 'shmflags', 'shmremap', 'sharedmem', 'runtime', 'mmap', 'namespace', 'jit']

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

struct Compile {
	architecture string
	inputs       map[string]string
	outputs      map[string]string
}

struct Native {
	architecture  string
	exit_code     int
	inputs        map[string]string
	serial_sha256 string
	iso_sha256    string
}

struct Reference {
	architecture string
	passed       bool
	finished     bool
	status       int
	artifacts    map[string]string
}

struct Case {
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
	results       []Case
}

fn require(good bool, message string) ! {
	if !good { return error(message) }
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn safe_relative(name string) ! {
	require(name != '' && !os.is_abs_path(name) && '..' !in name.split('/'), 'Unsafe evidence path')!
}

fn linked(root string, manifest Manifest, pins map[string]string) ! {
	require(pins.len > 0, 'Empty input inventory')!
	for origin, pin in pins {
		name := manifest.origins[origin] or { return error('Missing retained input: ' + origin) }
		require(manifest.files[name] == pin && digest(root + '/' + name)! == pin, 'Input hash differs: ' + origin)!
	}
}

fn input_pin(pins map[string]string, suffix string) !string {
	mut found := []string{}
	for origin, pin in pins { if origin.ends_with(suffix) { found << pin } }
	require(found.len == 1, 'Missing or ambiguous input: ' + suffix)!
	return found[0]
}

fn elf(bytes []u8, suffix string) ! {
	machine := if suffix == 'arm' { 183 } else if suffix == 'x86' { 62 } else { 0 }
	require(machine != 0 && bytes.len >= 20 && bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
		&& int(bytes[18]) + (int(bytes[19]) << 8) == machine, 'Wrong ELF architecture')!
}

fn linux_boot(line string) bool {
	mut message := line
	if line.starts_with('[') {
		parts := line.all_before(']').trim_left('[').trim_space().split('.')
		if parts.len != 2 { return false }
		for part in parts {
			if part == '' { return false }
			for byte in part.bytes() { if byte < `0` || byte > `9` { return false } }
		}
		message = line.all_after(']').trim_space()
	}
	return message.starts_with('Linux version ')
}

fn serial(text string, kind string) ! {
	baseline := kind == 'baseline'
	reference := kind == 'reference'
	name := if baseline || reference || kind == 'native' { 'SHMIMPORT' } else { kind.to_upper() }
	checks := if baseline || reference || kind in ['native', 'shmimport'] { 218 } else if kind == 'shmremove' { 301 } else if kind == 'shmtime' { 175 } else if kind == 'shmset' { 398 } else if kind == 'shmabi' { 243 } else if kind == 'shmflags' { 1763 } else if kind == 'shmremap' { 1101 } else { 0 }
	summary := 'LINUX ' + name + ' SUMMARY: checks=' + checks.str() + ' failures=' + if baseline { '33' } else { '0' }
	marker := 'LINUX ' + name + if baseline { ': FAIL' } else { ': PASS' }
	mut summaries := 0
	mut markers := 0
	mut mismatches := 0
	mut versions := 0
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if linux_boot(line) { versions++ }
		if line == summary { summaries++ }
		else if checks > 0 && line.starts_with('LINUX ' + name + ' SUMMARY:') { return error('Wrong summary') }
		if line == marker { markers++ }
		if line.starts_with('LINUX ' + name + ' MISMATCH:') { mismatches++ }
		for bad in ['KERNEL PANIC', 'Kernel panic', 'FATAL EXCEPTION', 'REFERENCE FAIL', 'BUG:', 'LINUX ' + name + ' FAIL:'] {
			require(!line.contains(bad), 'Guest failure: ' + bad)!
		}
		if !baseline { require(!line.contains(': FAIL') && !line.contains(' MISMATCH'), 'Unexpected failed check')! }
		else { require(line != 'LINUX SHMIMPORT: PASS', 'Original kernel falsely passed')! }
	}
	require(markers == 1 && (checks == 0 || summaries == 1), 'Missing or repeated result')!
	require(mismatches == if baseline { 33 } else { 0 }, 'Unexpected mismatch count')!
	if reference { require(versions == 1, 'Missing or repeated Linux boot')! }
}

fn maintained_identity(record Maintained, architecture string, kernel string, command []string,
	pins map[string]string) ! {
	require(record.architecture == architecture && record.kernel_sha256 == kernel
		&& record.results.len == cases.len, 'Wrong maintained identity')!
	require(command.len == 11 && command[1] == '--arch' && command[2] == architecture
		&& command[3] == '--kernel-dir' && command[5] == '--state-dir'
		&& command[7] == '--cases' && command[9] == '--timeout', 'Wrong maintained command')!
	require(pins[command[4] + '/bin/vinix'] == kernel && command[0] in pins, 'Unpinned maintained runner or kernel')!
	selected := command[8].split(',')
	require(selected.len == cases.len, 'Wrong maintained case count')!
	mut seen := map[string]bool{}
	for row in record.results {
		require(row.name in cases && row.name !in seen && selected.filter(it == row.name).len == 1
			&& row.exit_code == 0 && row.detail == '', 'Missing, repeated or failing maintained case')!
		seen[row.name] = true
	}
}

fn check(root string) ! {
	manifest := json2.decode[Manifest](os.read_file(root + '/manifest.json')!)!
	require(manifest.files.len > 100 && manifest.omitted.len == 0, 'Incomplete evidence bundle')!
	for name, pin in manifest.files {
		safe_relative(name)!
		require(os.real_path(root + '/' + name).starts_with(os.real_path(root) + '/'), 'Escaping evidence symlink')!
		require(pin.len == 64 && digest(root + '/' + name)! == pin, 'Artifact hash differs: ' + name)!
	}
	for _, name in manifest.origins { safe_relative(name)!; require(name in manifest.files, 'Missing origin target')! }
	require(digest(root + '/source/kernel/sysvshm/sysvshm.v')! == candidate_source, 'Different candidate source')!
	require(digest(root + '/source/kernel/memory/mmap/mmap.v')! == 'abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f', 'Different mapping source')!
	require(digest(root + '/source/kernel/userland/exit.v')! == '2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff', 'Different exit source')!
	fixture := digest(root + '/source/fixture/shmimportfixture/core.v')!
	for suffix in ['arm', 'x86'] {
		path := root + '/' + suffix
		architecture := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
		build := json2.decode[Build](os.read_file(path + '/build/receipt.json')!)!
		require(build.architecture == suffix && build.profile == 'prod' && build.base_commit == integration_base
			&& build.candidate_commit == integration_candidate && build.candidate_source_sha256 == candidate_source
			&& build.build_executed && build.build_exit_code == 0 && build.inputs_before == build.inputs_after, 'Wrong or changed kernel build')!
		mut source_count := 0
		for origin, pin in build.inputs_before {
			if origin.ends_with('/kernel/sysvshm/sysvshm.v') {
				require(pin == candidate_source, 'Build source differs')!
				source_count++
			}
		}
		require(source_count > 0, 'Missing kernel source input')!
		require(input_pin(build.inputs_before, '/kernel/memory/mmap/mmap.v')! == 'abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f', 'Changed mapping/exit source')!
		require(input_pin(build.inputs_before, '/kernel/userland/exit.v')! == '2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff', 'Changed mapping/exit source')!
		linked(root, manifest, build.inputs_before)!
		linked(root, manifest, build.outputs)!
		require(os.read_file(path + '/build/build.log.status')!.trim_space() == '0', 'Failed kernel build')!
		kernel := digest(path + '/build/kernel/bin/vinix')!
		elf(os.read_bytes(path + '/build/kernel/bin/vinix')!, suffix)!
		compile := json2.decode[Compile](os.read_file(path + '/compile/receipt.json')!)!
		require(compile.architecture == suffix && input_pin(compile.inputs, '/shmimportfixture/core.v')! == fixture, 'Different compiled probe source')!
		linked(root, manifest, compile.inputs)!
		linked(root, manifest, compile.outputs)!
		probe := digest(path + '/compile/probe')!
		elf(os.read_bytes(path + '/compile/probe')!, suffix)!
		for kind in ['native', 'baseline'] {
			where := path + '/' + kind
			record := json2.decode[Native](os.read_file(where + '/receipt.json')!)!
			code := if kind == 'baseline' { 1 } else { 0 }
			require(record.architecture == architecture && record.exit_code == code
				&& os.read_file(where + '/status')!.trim_space() == code.str(), 'Wrong native status')!
			linked(root, manifest, record.inputs)!
			require(input_pin(record.inputs, '/probe')! == probe && digest(where + '/rootfs/sbin/init')! == probe, 'Different native probe')!
			image := digest(where + '/kernel/bin/vinix')!
			original := if suffix == 'arm' { '4a5028dcc4407581595ab71e67d7d7f26cfedc24a2c3b492aa5c7d4964dbc3e0' }
				else { '621d97adf8ed1a054a1d8081197b5a98ece08690d46b6518b7e4aa42f85a703b' }
			require(image == if kind == 'native' { kernel } else { original }, 'Different native kernel')!
			require(input_pin(record.inputs, '/kernel/bin/vinix')! == image, 'Native kernel input differs')!
			elf(os.read_bytes(where + '/kernel/bin/vinix')!, suffix)!
			require(record.serial_sha256 == digest(where + '/serial.log')! && record.iso_sha256 == digest(where + '/test.iso')!, 'Native output differs')!
			serial(os.read_file(where + '/serial.log')!, kind)!
		}
		reference := json2.decode[Reference](os.read_file(path + '/reference/receipt.json')!)!
		require(reference.architecture == architecture && reference.passed && reference.finished && reference.status == 0, 'Failed Linux reference')!
		for name, file in {'probe': 'probe', 'kernel': 'linux', 'serial': 'serial.log', 'initramfs': 'initramfs.cpio', 'wrapper_elf': 'init'} {
			require(reference.artifacts[name] == digest(path + '/reference/' + file)!, 'Linux artifact differs')!
		}
		require(reference.artifacts['probe'] == probe && reference.artifacts['wrapper_elf'] == digest(path + '/compile/reference-init')!, 'Different reference ELF')!
		require(reference.artifacts['controller_source'] == digest(root + '/tooling/shmimport-reference.v')!
			&& reference.artifacts['wrapper_source'] == digest(root + '/source/fixture/shmimportreferenceinit/core.v')!, 'Different reference source')!
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + '/reference/inputs.json')!)!)!
		serial(os.read_file(path + '/reference/serial.log')!, 'reference')!
		maintained := json2.decode[Maintained](os.read_file(path + '/maintained/receipt.json')!)!
		pins := json2.decode[map[string]string](os.read_file(path + '/maintained/controller-inputs.json')!)!
		command := json2.decode[[]string](os.read_file(path + '/maintained/controller-command.json')!)!
		maintained_identity(maintained, architecture, kernel, command, pins)!
		linked(root, manifest, pins)!
		require(manifest.origins[command[6] + '/receipt.json'] == suffix + '/maintained/receipt.json', 'Different maintained state')!
		for row in maintained.results {
			where := path + '/maintained/' + row.name
			require(row.source_sha256 == digest(root + '/source/fixture/' + row.name + 'fixture/core.v')!
				&& row.init_sha256 == digest(where + '/init')! && row.iso_sha256 == digest(where + '/test.iso')!, 'Maintained fixture differs')!
			linked(root, manifest, row.source_inputs)!
			elf(os.read_bytes(where + '/init')!, suffix)!
			serial(os.read_file(where + '/serial.log')!, row.name)!
		}
	}
	println('Shared-memory metadata-import evidence: PASS (both architectures, complete hashes, builds, same-ELF Linux/native/original checks, 12 maintained suites)')
}

fn controls() ! {
	good := 'LINUX SHMIMPORT SUMMARY: checks=218 failures=0\nLINUX SHMIMPORT: PASS\n'
	serial(good, 'native')!
	reference := 'Linux version control\nLINUX SHMIMPORT SUMMARY: checks=218 failures=0\nLINUX SHMIMPORT: PASS\n'
	serial(reference, 'reference')!
	serial(reference.replace('Linux version control', '[    0.000000] Linux version control'), 'reference')!
	baseline := 'LINUX SHMIMPORT SUMMARY: checks=218 failures=33\nLINUX SHMIMPORT: FAIL\n' + 'LINUX SHMIMPORT MISMATCH: injected\n'.repeat(33)
	serial(baseline, 'baseline')!
	mut refused := 0
	for bad in [good.replace('218', '217'), good.replace('failures=0', 'failures=1'),
		good.replace('LINUX SHMIMPORT: PASS\n', ''), good + good, good + 'KERNEL PANIC injected\n',
		good + 'LINUX SHMIMPORT MISMATCH: injected\n'] {
		serial(bad, 'native') or { refused++; continue }
		return error('Accepted negative serial control')
	}
	for bad in [baseline.replace('failures=33', 'failures=32'), baseline + 'LINUX SHMIMPORT MISMATCH: extra\n'] {
		serial(bad, 'baseline') or { refused++; continue }
		return error('Accepted negative original control')
	}
	for bad in [reference.replace('Linux version control\n', ''),
		reference + '[    0.000000] Linux version repeated\n'] {
		serial(bad, 'reference') or { refused++; continue }
		return error('Accepted missing or repeated Linux boot')
	}
	for bad in ['', '/absolute', 'relative/../escape'] {
		safe_relative(bad) or { refused++; continue }
		return error('Accepted unsafe path')
	}
	linked('.', Manifest{}, {'missing': 'pin'}) or { refused++ }
	require(refused == 14, 'Negative control unexpectedly passed')!
	mut rows := []Case{}
	for name in cases { rows << Case{name: name} }
	command := ['runner', '--arch', 'aarch64', '--kernel-dir', 'kernel', '--state-dir',
		'state', '--cases', cases.join(','), '--timeout', '900']
	pins := {'runner': 'runner-pin', 'kernel/bin/vinix': 'kernel-pin'}
	good_record := Maintained{architecture: 'aarch64', kernel_sha256: 'kernel-pin', results: rows}
	maintained_identity(good_record, 'aarch64', 'kernel-pin', command, pins)!
	mut duplicate := rows.clone()
	duplicate[1] = rows[0]
	mut failed := rows.clone()
	failed[0] = Case{name: cases[0], exit_code: 1}
	for bad in [Maintained{...good_record, architecture: 'x86_64'},
		Maintained{...good_record, kernel_sha256: 'different'},
		Maintained{...good_record, results: rows[..rows.len - 1]},
		Maintained{...good_record, results: duplicate}, Maintained{...good_record, results: failed}] {
		maintained_identity(bad, 'aarch64', 'kernel-pin', command, pins) or { refused++; continue }
		return error('Accepted changed maintained identity')
	}
	for index in [0, 2, 4, 8] {
		mut bad := command.clone()
		bad[index] = 'different'
		maintained_identity(good_record, 'aarch64', 'kernel-pin', bad, pins) or { refused++; continue }
		return error('Accepted changed maintained command')
	}
	require(refused == 23, 'Maintained negative control unexpectedly passed')!
	println('Shared-memory metadata-import evidence controls: PASS (5 positive, 23 negative)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { controls() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != 'check' { eprintln('Usage: shmimport-evidence.v self-test | check BUNDLE'); exit(2) }
	check(os.args[2]) or { eprintln(err); exit(1) }
}
