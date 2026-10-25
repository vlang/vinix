// SPDX-License-Identifier: GPL-2.0-or-later
// Audit native alternate-stack handler import-fault precedence status against Linux.
module main

import crypto.sha256
import json2
import os

const candidate_source = '659b2392ff63e82bcaf42fd0031313efff58726cb63bbb09f24fed9e25a8579e'
const integration_base = '4e8c41a2e26effce5ccfb6b66331dad4b399f8ec'
const integration_candidate = '60c383cf5355594e1ad6cf610ab071c40607e073'
const cases = ['altstackhandler', 'altstackabi', 'sigactionabi', 'sigactioncopy', 'sigmaskcopy', 'altstackcopy', 'sigwaitorder', 'sigwaitcopy', 'sigpending', 'randomsignal', 'clonesignal', 'cloneclear', 'seccomp', 'runtime', 'futex', 'jit']
const retained_random_serial = '010128774f5d4f9ea9557cf109bc024b3e8eead64736e29a9a637b3921a19d72'
const retained_replay_serial = '6d861d2b088197f1976635dfa0952a6f27ed7041a50ca6c4c61eca9c77212115'

// This qualification retains a failed regression; it does not call it a pass.
fn retained_failure(text string) ! {
	require(sha256.sum(text.bytes()).hex() == retained_random_serial, 'Different retained random-signal failure')!
}

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

fn digest(path string) !string { data := os.read_bytes(path)!; defer { unsafe { data.free() } }; return sha256.sum(data).hex() }

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
	baseline := kind in ['baseline-arm', 'baseline-x86']
	reference := kind == 'reference'
	name := if baseline || reference || kind == 'native' { 'ALTSTACKHANDLER' } else { kind.to_upper() }
	checks := if baseline || reference || kind in ['native', 'altstackhandler'] { 19444 } else if kind == 'altstackabi' { 38880 } else if kind == 'sigactionabi' { 56000 } else if kind == 'sigactioncopy' { 4440 } else if kind == 'sigmaskcopy' { 3984 } else if kind == 'altstackcopy' { 560 } else if kind == 'sigwaitorder' { 27968 } else if kind == 'sigwaitcopy' { 1488 } else if kind == 'sigpending' { 428 } else { 0 }
	summary := 'LINUX ' + name + ' SUMMARY: checks=' + checks.str() + ' failures=' + if baseline { if kind == 'baseline-arm' { '2160' } else { '2160' } } else { '0' }
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
		else { require(line != 'LINUX ALTSTACKHANDLER: PASS', 'Original kernel falsely passed')! }
	}
	require(markers == 1 && (checks == 0 || summaries == 1), 'Missing or repeated result')!
	require(mismatches == if baseline { 60 } else { 0 }, 'Unexpected mismatch count')!
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
		code := if architecture == 'x86_64' && row.name == 'randomsignal' { 1 } else { 0 }
		require(row.name in cases && row.name !in seen && selected.filter(it == row.name).len == 1
			&& row.exit_code == code && row.detail == '', 'Missing, repeated or unexpected maintained result')!
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
	require(digest(root + '/source/kernel/userland/signal.v')! == candidate_source, 'Different candidate source')!
	require(digest(root + '/source/kernel/memory/mmap/mmap.v')! == 'abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f', 'Different mapping source')!
	require(digest(root + '/source/kernel/userland/exit.v')! == '2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff', 'Different exit source')!
	require(digest(root + '/source/kernel/posixtimer/posix_timer.v')! == 'a5874e940e181b10c8e4416c2f7cb2359c619bd40f54f09c64cce921712b21ab', 'Different timer source')!
	require(digest(root + '/source/kernel/syscall/table/gaps.v')! == 'f7a135f09229e9808ab5e4b75c3a0874d7087d3da4032aebbc7ab66e4e122a84', 'Different syscall table source')!
	fixture := digest(root + '/source/fixture/altstackhandlerfixture/core.v')!
	for suffix in ['arm', 'x86'] {
		path := root + '/' + suffix
		architecture := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
		build := json2.decode[Build](os.read_file(path + '/build/receipt.json')!)!
		require(build.architecture == suffix && build.profile == 'prod' && build.base_commit == integration_base
			&& build.candidate_commit == integration_candidate && build.candidate_source_sha256 == candidate_source
			&& build.build_executed && build.build_exit_code == 0 && build.inputs_before == build.inputs_after, 'Wrong or changed kernel build')!
		mut source_count := 0
		for origin, pin in build.inputs_before {
			if origin.ends_with('/kernel/userland/signal.v') {
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
		require(compile.architecture == suffix && input_pin(compile.inputs, '/altstackhandlerfixture/core.v')! == fixture, 'Different compiled probe source')!
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
			original := if suffix == 'arm' { 'a2eeb08a38785bd6a21a8409a675788cc45967dc2428ba98f1c638a1dc0354b3' }
				else { '5a319314d4fb1b0bc5efc0f47a823bb425cf358e4eb22779c180f8da85f869bd' }
			require(image == if kind == 'native' { kernel } else { original }, 'Different native kernel')!
			require(input_pin(record.inputs, '/kernel/bin/vinix')! == image, 'Native kernel input differs')!
			elf(os.read_bytes(where + '/kernel/bin/vinix')!, suffix)!
			require(record.serial_sha256 == digest(where + '/serial.log')! && record.iso_sha256 == digest(where + '/test.iso')!, 'Native output differs')!
			serial(os.read_file(where + '/serial.log')!, if kind == 'baseline' { 'baseline-' + suffix } else { kind })!
		}
		reference := json2.decode[Reference](os.read_file(path + '/reference/receipt.json')!)!
		require(reference.architecture == architecture && reference.passed && reference.finished && reference.status == 0, 'Failed Linux reference')!
		for name, file in {'probe': 'probe', 'kernel': 'linux', 'serial': 'serial.log', 'initramfs': 'initramfs.cpio', 'wrapper_elf': 'init'} {
			require(reference.artifacts[name] == digest(path + '/reference/' + file)!, 'Linux artifact differs')!
		}
		require(reference.artifacts['probe'] == probe && reference.artifacts['wrapper_elf'] == digest(path + '/compile/reference-init')!, 'Different reference ELF')!
		require(reference.artifacts['controller_source'] == digest(root + '/tooling/altstackhandler-reference.v')!
			&& reference.artifacts['wrapper_source'] == digest(root + '/source/fixture/altstackhandlerreferenceinit/core.v')!, 'Different reference source')!
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
			if suffix == 'x86' && row.name == 'randomsignal' {
				retained_failure(os.read_file(where + '/serial.log')!)!
			} else { serial(os.read_file(where + '/serial.log')!, row.name)! }
		}
		if suffix == 'x86' {
			where := path + '/randomsignal-replay'
			replay := json2.decode[Native](os.read_file(where + '/receipt.json')!)!
			require(replay.architecture == architecture && replay.exit_code == 1
				&& os.read_file(where + '/status')!.trim_space() == '1', 'Different random-signal replay status')!
			linked(root, manifest, replay.inputs)!
			row := maintained.results.filter(it.name == 'randomsignal')[0]
			require(input_pin(replay.inputs, '/randomsignal/init')! == row.init_sha256
				&& digest(where + '/rootfs/sbin/init')! == row.init_sha256, 'Different replay ELF')!
			require(input_pin(replay.inputs, '/kernel/bin/vinix')! == kernel
				&& digest(where + '/kernel/bin/vinix')! == kernel, 'Different replay kernel')!
			require(replay.serial_sha256 == digest(where + '/serial.log')!
				&& replay.iso_sha256 == digest(where + '/test.iso')!, 'Different replay output')!
			require(replay.serial_sha256 == retained_replay_serial, 'Different retained replay failure')!
		}
	}
	println('Alternate-stack handler evidence audit: PASS (complete hashes, both builds, same-ELF Linux/native/original; AArch64 16 passed; x86-64 15 passed, randomsignal and identical replay failed)')
}

fn controls() ! {
	good := 'LINUX ALTSTACKHANDLER SUMMARY: checks=19444 failures=0\nLINUX ALTSTACKHANDLER: PASS\n'
	serial(good, 'native')!
	reference := 'Linux version control\nLINUX ALTSTACKHANDLER SUMMARY: checks=19444 failures=0\nLINUX ALTSTACKHANDLER: PASS\n'
	serial(reference, 'reference')!
	serial(reference.replace('Linux version control', '[    0.000000] Linux version control'), 'reference')!
	baseline := 'LINUX ALTSTACKHANDLER SUMMARY: checks=19444 failures=2160\nLINUX ALTSTACKHANDLER: FAIL\n' + 'LINUX ALTSTACKHANDLER MISMATCH: injected\n'.repeat(60)
	serial(baseline, 'baseline-arm')!
	serial(baseline, 'baseline-x86')!
	mut architecture_refusals := 0
	for kind in ['baseline-arm', 'baseline-x86'] {
		wrong := baseline.replace('failures=2160', if kind == 'baseline-arm' { 'failures=2161' } else { 'failures=2159' })
		serial(wrong, kind) or { architecture_refusals++; continue }
		return error('Accepted wrong original failure count')
	}
	require(architecture_refusals == 2, 'Architecture controls unexpectedly passed')!
	mut refused := 0
	for bad in [good.replace('19444', '19443'), good.replace('failures=0', 'failures=1'),
		good.replace('LINUX ALTSTACKHANDLER: PASS\n', ''), good + good, good + 'KERNEL PANIC injected\n',
		good + 'LINUX ALTSTACKHANDLER MISMATCH: injected\n'] {
		serial(bad, 'native') or { refused++; continue }
		return error('Accepted negative serial control')
	}
	for bad in [baseline.replace('failures=2160', 'failures=2159'), baseline + 'LINUX ALTSTACKHANDLER MISMATCH: extra\n'] {
		serial(bad, 'baseline-arm') or { refused++; continue }
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
	mut mixed := rows.clone()
	mixed[cases.index('randomsignal')] = Case{name: 'randomsignal', exit_code: 1}
	xcommand := command.map(if it == 'aarch64' { 'x86_64' } else { it })
	xrecord := Maintained{architecture: 'x86_64', kernel_sha256: 'kernel-pin', results: mixed}
	maintained_identity(xrecord, 'x86_64', 'kernel-pin', xcommand, pins)!
	for bad in [Maintained{...xrecord, results: rows}, Maintained{...xrecord, results: failed}] {
		maintained_identity(bad, 'x86_64', 'kernel-pin', xcommand, pins) or { refused++; continue }
		return error('Accepted missing or changed retained regression failure')
	}
	retained_failure('changed failure') or { refused++ }
	require(refused == 26, 'Retained-failure control unexpectedly passed')!
	println('Alternate-stack handler evidence controls: PASS (7 positive, 28 negative)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { controls() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != 'check' { eprintln('Usage: altstackhandler-evidence.v self-test | check BUNDLE'); exit(2) }
	check(os.args[2]) or { eprintln(err); exit(1) }
}
