// SPDX-License-Identifier: GPL-2.0-or-later
// Audit native clone/fork alternate-stack inheritance against Linux.
module main

import crypto.sha256
import json2
import os

const candidate_source = '32c1359431bc8efe60fbbe966cbd57898f6777f37dba7f68b4a99755e12fa970'
const integration_base = '6753f67b20200d10961e58d48f3d3ff2e1dd01de'
const integration_candidate = 'c6b5455ee837f44b843d03255294c8b610ad7635'
const cases = ['altstackclone', 'clonestack', 'cloneflags', 'clonethreadns', 'cloneparent', 'altstackrestore', 'altstacknest', 'altstackframe', 'altstacksp', 'altstackhandler', 'altstackabi', 'sigactionabi', 'sigactioncopy', 'sigmaskcopy', 'altstackcopy', 'sigwaitorder', 'sigwaitcopy', 'sigpending', 'randomsignal', 'clonesignal', 'cloneclear', 'seccomp', 'runtime', 'futex', 'jit']

struct Manifest {
	files   map[string]string
	modes   map[string]u32
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
	command                 []string
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

fn build_source(pins map[string]string, architecture string, source string, pin string, snapshot bool) ! {
 area := '/Users/alex/.cache/vinix-linux-compat/altstackclone-20261026'
 mut origins := [area + '/kernel-second-' + architecture + '/kernel/' + source]
 if snapshot { origins << area + '/source-second/kernel/' + source }
 for origin in origins { require(origin in pins && pins[origin] == pin, 'Build source differs: ' + origin)! }
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

fn failed_case(kind string, configuration int) bool {
 return kind.starts_with('baseline-') && configuration >= 8 && configuration % 8 !in [2, 5]
}

fn serial(text string, kind string) ! {
 focused := kind in ['baseline-arm', 'baseline-x86', 'reference', 'native', 'altstackclone']
 failed := kind.starts_with('baseline-')
 name := if focused { 'ALTSTACKCLONE' } else { kind.to_upper() }
 checks := if focused { 1440 } else if kind == 'altstackrestore' { 952 } else if kind == 'altstacknest' { 592 } else if kind == 'altstackframe' { 272 } else if kind == 'altstacksp' { 388 } else if kind == 'altstackhandler' { 19444 } else if kind == 'altstackabi' { 38880 } else if kind == 'sigactionabi' { 56000 } else if kind == 'sigactioncopy' { 4440 } else if kind == 'sigmaskcopy' { 3984 } else if kind == 'altstackcopy' { 560 } else if kind == 'sigwaitorder' { 27968 } else if kind == 'sigwaitcopy' { 1488 } else if kind == 'sigpending' { 428 } else { 0 }
 failures := if failed { 120 } else { 0 }
 summary := 'LINUX ' + name + ' SUMMARY: checks=' + checks.str() + ' failures=' + failures.str()
 marker := 'LINUX ' + name + if failed { ': FAIL' } else { ': PASS' }
 mut expected := map[string]bool{}
 mut descendants := map[string]int{}
 mut mismatch_counts := map[string]int{}
 if focused { for ordinary in 0 .. 2 { for configuration in 0 .. 24 {
  bad := failed_case(kind, configuration)
  child := 'LINUX ALTSTACKCLONE CHILD: ordinary=' + ordinary.str() + ' case=' + configuration.str()
   + ' status=0 bytes=8 checks=29 failures=' + if bad { '5' } else { '0' }
  expected[child] = false
  descendant := 'LINUX ALTSTACKCLONE DESCENDANT: case=' + configuration.str()
   + ' status=' + if configuration % 8 == 5 { '0' } else { '9472' }
   + ' bytes=8 checks=19 failures=' + if bad { '5' } else { '0' }
  descendants[descendant]++
  if bad { for stage in [30, 21, 22, 23, 32] {
   mismatch := 'LINUX ALTSTACKCLONE MISMATCH: case=' + configuration.str() + ' phase=1 stage=' + stage.str()
   mismatch_counts[mismatch]++
  } }
 } } }
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
  if focused && line.starts_with('LINUX ALTSTACKCLONE CHILD:') {
   require(line in expected && !expected[line], 'Changed or repeated inheritance child')!
   expected[line] = true
  }
  if focused && line.starts_with('LINUX ALTSTACKCLONE DESCENDANT:') {
   require(descendants[line] > 0, 'Changed or repeated descendant')!
   descendants[line]--
  }
  if line.starts_with('LINUX ' + name + ' MISMATCH:') {
   require(failed && mismatch_counts[line] > 0, 'Changed inheritance mismatch')!
   mismatch_counts[line]--; mismatches++
  }
  for bad in ['KERNEL PANIC', 'Kernel panic', 'FATAL EXCEPTION', 'REFERENCE FAIL', 'BUG:', 'LINUX ' + name + ' FAIL:'] {
   require(!line.contains(bad), 'Guest failure: ' + bad)!
  }
  if !failed { require(!line.contains(': FAIL') && !line.contains(' MISMATCH'), 'Unexpected failed check')! }
  else { require(line != 'LINUX ALTSTACKCLONE: PASS', 'Original kernel falsely passed')! }
 }
 require(markers == 1 && (checks == 0 || summaries == 1), 'Missing or repeated result')!
 require(mismatches == failures, 'Unexpected mismatch count')!
 for _, seen in expected { require(seen, 'Missing inheritance child')! }
 for _, remaining in descendants { require(remaining == 0, 'Missing descendant')! }
 for _, remaining in mismatch_counts { require(remaining == 0, 'Missing inheritance mismatch')! }
 if kind == 'reference' { require(versions == 1, 'Missing or repeated Linux boot')! }
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
		// Retain the observed timing-sensitive randomsignal failure as a failure.
		// This is an evidence audit, not an all-green maintained qualification.
		expected_code := if architecture == 'x86_64' && row.name == 'randomsignal' { 1 } else { 0 }
		require(row.name in cases && row.name !in seen && selected.filter(it == row.name).len == 1
			&& row.exit_code == expected_code
			&& row.detail == '', 'Missing, repeated or changed maintained result')!
		seen[row.name] = true
	}
}

fn maintained_serial(text string, name string, architecture string) ! {
	if architecture == 'x86_64' && name == 'randomsignal' {
		// Only this complete recorded diagnostic is accepted; no other failure is.
		require(sha256.sum(text.bytes()).hex() == '2e189c0392e19ca4939eb8ce906697791aeed6fba7a7f97b4e769111f21af497',
			'Different known randomsignal failure')!
		require(text.contains('LINUX RANDOMSIGNAL FAIL: interruption, masks, short requests or guards')
			&& !text.contains('LINUX RANDOMSIGNAL: PASS'), 'Randomsignal failure relabeled')!
		return
	}
	serial(text, name)!
}

fn check(root string) ! {
	manifest := json2.decode[Manifest](os.read_file(root + '/manifest.json')!)!
	require(manifest.files.len > 100 && manifest.omitted.len == 0, 'Incomplete evidence bundle')!
	require(manifest.modes.len == manifest.files.len, 'Incomplete artifact modes')!
	for name, pin in manifest.files {
		safe_relative(name)!
		require(os.real_path(root + '/' + name).starts_with(os.real_path(root) + '/'), 'Escaping evidence symlink')!
		require(pin.len == 64 && digest(root + '/' + name)! == pin, 'Artifact hash differs: ' + name)!
		require(os.stat(root + '/' + name)!.mode & 0o7777 == manifest.modes[name], 'Artifact mode differs: ' + name)!
	}
	for _, name in manifest.origins { safe_relative(name)!; require(name in manifest.files, 'Missing origin target')! }
	require(digest(root + '/source/kernel/userland/linux_task.v')! == candidate_source, 'Different candidate source')!
	require(digest(root + '/source/kernel/userland/clone_amd64.v')! == '23f37a3c0941c804c3f414f56422a991f80e665e20a30d36532ec76dd9539b82', 'Different clone source')!
	require(digest(root + '/source/kernel/userland/clone_arm64.v')! == '23ce962de60366118c04871b5967ab22703db4ee58c283467d33b27e051c1e3c', 'Different clone source')!
	fixture := digest(root + '/source/fixture/altstackclonefixture/core.v')!
	for suffix in ['arm', 'x86'] {
		path := root + '/' + suffix
		architecture := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
		build := json2.decode[Build](os.read_file(path + '/build/receipt.json')!)!
		require(build.architecture == suffix && build.profile == 'prod' && build.base_commit == integration_base
			&& build.candidate_commit == integration_candidate && build.candidate_source_sha256 == candidate_source
			&& build.build_executed && build.build_exit_code == 0 && build.inputs_before == build.inputs_after, 'Wrong or changed kernel build')!
		build_source(build.inputs_before, suffix, 'userland/linux_task.v', '32c1359431bc8efe60fbbe966cbd57898f6777f37dba7f68b4a99755e12fa970', true)!
		build_source(build.inputs_before, suffix, 'userland/clone_amd64.v', '23f37a3c0941c804c3f414f56422a991f80e665e20a30d36532ec76dd9539b82', true)!
		build_source(build.inputs_before, suffix, 'userland/clone_arm64.v', '23ce962de60366118c04871b5967ab22703db4ee58c283467d33b27e051c1e3c', true)!
		linked(root, manifest, build.inputs_before)!
		linked(root, manifest, build.outputs)!
		for flag in ['PROD=true', 'LIMINE_MP=1', 'ALLOC_TRACK=0', 'KERNEL_LINK_SEED=42'] { require(flag in build.command, 'Different build flags')! }
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + '/build/baseline-inputs.json')!)!)!
		require(os.read_file(path + '/build/build.log.status')!.trim_space() == '0', 'Failed kernel build')!
		kernel := digest(path + '/build/kernel/bin/vinix')!
		elf(os.read_bytes(path + '/build/kernel/bin/vinix')!, suffix)!
		compile := json2.decode[Compile](os.read_file(path + '/compile/receipt.json')!)!
		require(compile.architecture == suffix && input_pin(compile.inputs, '/altstackclonefixture/core.v')! == fixture, 'Different compiled probe source')!
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
			original := if suffix == 'arm' { '758a9cdab47fd7ebc618a83a4285b39b27946f955552ccbaeadd6bc897fb5a3d' }
				else { '9ceaee6c2fb89619e17e1b963228e083e8938e34ee85c7bd148434b9c9394a9e' }
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
		require(reference.artifacts['controller_source'] == digest(root + '/tooling/altstackclone-reference.v')!
			&& reference.artifacts['wrapper_source'] == digest(root + '/source/fixture/altstackclonereferenceinit/core.v')!, 'Different reference source')!
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
			maintained_serial(os.read_file(where + '/serial.log')!, row.name, architecture)!
		}

	}
	println('Alternate-stack inheritance evidence: VALID (1440 focused checks PASS on both; maintained AArch64 25/25, x86-64 24/25; randomsignal FAIL retained)')
}

fn control_serial(kind string) string {
 mut lines := []string{}
 for ordinary in 0 .. 2 { for configuration in 0 .. 24 {
  bad := failed_case(kind, configuration)
  if bad { for stage in [30, 21, 22, 23, 32] {
   lines << 'LINUX ALTSTACKCLONE MISMATCH: case=' + configuration.str() + ' phase=1 stage=' + stage.str()
  } }
  lines << 'LINUX ALTSTACKCLONE DESCENDANT: case=' + configuration.str()
   + ' status=' + if configuration % 8 == 5 { '0' } else { '9472' }
   + ' bytes=8 checks=19 failures=' + if bad { '5' } else { '0' }
  lines << 'LINUX ALTSTACKCLONE CHILD: ordinary=' + ordinary.str() + ' case=' + configuration.str()
   + ' status=0 bytes=8 checks=29 failures=' + if bad { '5' } else { '0' }
 } }
 lines << 'LINUX ALTSTACKCLONE SUMMARY: checks=1440 failures=' + if kind.starts_with('baseline-') { '120' } else { '0' }
 lines << 'LINUX ALTSTACKCLONE: ' + if kind.starts_with('baseline-') { 'FAIL' } else { 'PASS' }
 return lines.join('\n') + '\n'
}

fn controls() ! {
 good := control_serial('native')
 arm := control_serial('baseline-arm')
 x86 := control_serial('baseline-x86')
 serial(good, 'native')!
 serial(arm, 'baseline-arm')!
 serial(x86, 'baseline-x86')!
 reference := 'Linux version control\n' + good
 serial(reference, 'reference')!
 serial(reference.replace('Linux version control', '[    0.000000] Linux version control'), 'reference')!
 mut refused := 0
 for bad in [good.replace('checks=1440', 'checks=1439'), good.replace('failures=0', 'failures=1'),
  good.replace('LINUX ALTSTACKCLONE: PASS\n', ''), good + good, good + 'KERNEL PANIC injected\n',
  good + 'LINUX ALTSTACKCLONE MISMATCH: injected\n', good.replace('ordinary=1 case=23', 'ordinary=1 case=22'),
  good.replace('status=0 bytes=8 checks=29', 'status=7 bytes=0 checks=0'),
  good.all_after('\n'), arm] {
  serial(bad, 'native') or { refused++; continue }
  return error('Accepted negative focused serial control')
 }
 for kind in ['baseline-arm', 'baseline-x86'] {
  baseline := if kind == 'baseline-arm' { arm } else { x86 }
  for bad in [baseline.replace('checks=1440', 'checks=1439'), baseline.replace('failures=5', 'failures=4'),
   baseline.replace('status=9472', 'status=11'), baseline.replace('case=8 phase=1 stage=30', 'case=0 phase=1 stage=30'),
   baseline + 'LINUX ALTSTACKCLONE MISMATCH: case=8 phase=1 stage=30\n', good,
   baseline.replace('DESCENDANT: case=23', 'DESCENDANT: case=22')] {
   serial(bad, kind) or { refused++; continue }
   return error('Accepted changed original-kernel failure')
  }
 }
 for bad in [good, reference + '[    0.000000] Linux version repeated\n'] {
  serial(bad, 'reference') or { refused++; continue }
  return error('Accepted missing or repeated Linux boot')
 }
 for bad in ['', '/absolute', 'relative/../escape'] {
  safe_relative(bad) or { refused++; continue }
  return error('Accepted unsafe path')
 }
 linked('.', Manifest{}, {'missing': 'pin'}) or { refused++ }
 require(refused == 30, 'Focused negative control unexpectedly passed')!
 mut rows := []Case{}
 for name in cases { rows << Case{name: name} }
 command := ['runner', '--arch', 'aarch64', '--kernel-dir', 'kernel', '--state-dir', 'state', '--cases', cases.join(','), '--timeout', '900']
 pins := {'runner': 'runner-pin', 'kernel/bin/vinix': 'kernel-pin'}
 good_record := Maintained{architecture: 'aarch64', kernel_sha256: 'kernel-pin', results: rows}
 maintained_identity(good_record, 'aarch64', 'kernel-pin', command, pins)!
 mut duplicate := rows.clone(); duplicate[1] = rows[0]
 mut failed := rows.clone(); failed[0] = Case{name: cases[0], exit_code: 1}
 for bad in [Maintained{...good_record, architecture: 'x86_64'}, Maintained{...good_record, kernel_sha256: 'different'},
  Maintained{...good_record, results: rows[..rows.len - 1]}, Maintained{...good_record, results: duplicate}, Maintained{...good_record, results: failed}] {
  maintained_identity(bad, 'aarch64', 'kernel-pin', command, pins) or { refused++; continue }
  return error('Accepted changed maintained identity')
 }
 for index in [0, 2, 4, 8] {
  mut bad := command.clone(); bad[index] = 'different'
  maintained_identity(good_record, 'aarch64', 'kernel-pin', bad, pins) or { refused++; continue }
  return error('Accepted changed maintained command')
 }
 mut x86_rows := rows.clone()
 random_index := cases.index('randomsignal')
 x86_rows[random_index] = Case{name: 'randomsignal', exit_code: 1}
 x86_record := Maintained{architecture: 'x86_64', kernel_sha256: 'kernel-pin', results: x86_rows}
 mut x86_command := command.clone(); x86_command[2] = 'x86_64'
 maintained_identity(x86_record, 'x86_64', 'kernel-pin', x86_command, pins)!
 mut wrong_code := x86_rows.clone(); wrong_code[random_index] = Case{name: 'randomsignal', exit_code: 2}
 mut extra_failure := x86_rows.clone(); extra_failure[0] = Case{name: cases[0], exit_code: 1}
 for changed in [rows, wrong_code, extra_failure] {
  maintained_identity(Maintained{...x86_record, results: changed}, 'x86_64', 'kernel-pin', x86_command, pins) or { refused++; continue }
  return error('Accepted changed diagnostic qualification')
 }
 for changed in ['', 'LINUX RANDOMSIGNAL: PASS\n', 'LINUX RANDOMSIGNAL FAIL: interruption, masks, short requests or guards\n'] {
  maintained_serial(changed, 'randomsignal', 'x86_64') or { refused++; continue }
  return error('Accepted missing or changed complete diagnostic')
 }
 area := '/Users/alex/.cache/vinix-linux-compat/altstackclone-20261026'
 for architecture in ['arm', 'x86'] {
  tree := area + '/kernel-second-' + architecture + '/kernel/userland/source.v'
  snapshot := area + '/source-second/kernel/userland/source.v'
  build_source({tree: 'pin', snapshot: 'pin'}, architecture, 'userland/source.v', 'pin', true)!
  for bad in [{snapshot: 'pin'}, {tree: 'pin'}, {tree: 'changed', snapshot: 'pin'}, {tree: 'pin', snapshot: 'changed'}] {
   build_source(bad, architecture, 'userland/source.v', 'pin', true) or { refused++; continue }
   return error('Accepted changed or missing exact build input')
  }
  proc_source := area + '/kernel-second-' + architecture + '/kernel/proc/source.v'
  build_source({proc_source: 'pin'}, architecture, 'proc/source.v', 'pin', false)!
  for bad in [map[string]string{}, {proc_source: 'changed'}] {
   build_source(bad, architecture, 'proc/source.v', 'pin', false) or { refused++; continue }
   return error('Accepted changed or missing process build input')
  }
 }
 require(refused == 57, 'Input identity control unexpectedly passed')!
 println('Alternate-stack inheritance evidence controls: PASS (11 positive, 57 negative)')
}


fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { controls() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != 'check' { eprintln('Usage: altstackclone-evidence.v self-test | check BUNDLE'); exit(2) }
	check(os.args[2]) or { eprintln(err); exit(1) }
}
