// SPDX-License-Identifier: GPL-2.0-or-later
// Audit native process-wide one-shot signal handlers against Linux.
module main

import crypto.sha256
import json2
import os

const candidate_source = '411d614c7cd3614daa388aa25a2b8f03db51d7a2ebdba31b643ada40f650db3e'
const integration_base = '8d81434c3484da21d23f08f4217d5b2e45c2a428'
const integration_candidate = '8529354bc41c85e93958d4c1e9c0213e55d82b13'
const cases = ['resethand', 'sigactionflags', 'autodisarm', 'altstackclone', 'altstackrestore', 'altstacknest', 'altstackframe', 'altstacksp', 'altstackhandler', 'altstackabi', 'sigactionabi', 'sigactioncopy', 'sigmaskcopy', 'altstackcopy', 'sigwaitorder', 'sigwaitcopy', 'sigpending', 'randomsignal', 'clonesignal', 'cloneclear', 'seccomp', 'runtime', 'futex', 'jit']

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
 area := '/Users/alex/.cache/vinix-linux-compat/resethand-20261026'
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

fn original_stages(configuration int) []int {
 if configuration >= 20 {
  return match configuration % 5 {
   0, 1 { [10, 11, 21, 50, 41, 53] }
   2 { [10, 11, 21, 24, 25, 31, 32, 27, 50, 41, 53] }
   3 { [10, 11, 21, 24, 25, 31, 27, 50, 41, 53] }
   else { [10, 11, 21, 50, 41, 42, 53] }
  }
 }
 return match configuration % 10 {
  0, 1 { [10, 11, 21, 23, 50, 41, 43, 53] }
  2, 3, 6, 7 { [10, 11, 21, 23, 24, 25, 31, 32, 33, 27, 50, 41, 43, 53] }
  4 { [10, 11, 21, 23, 50, 41, 42, 53] }
  5, 8 { [10, 11, 21, 23, 24, 25, 31, 33, 27, 50, 41, 43, 53] }
  else { [10, 11, 21, 23, 24, 25, 31, 33, 27, 50, 41, 42, 43, 53] }
 }
}

fn previous_serial(text string, kind string) ! {
 focused := kind in ['baseline-arm', 'baseline-x86', 'reference', 'native', 'autodisarm']
 failed := kind.starts_with('baseline-')
 name := if focused { 'AUTODISARM' } else { kind.to_upper() }
 checks := if focused { 1560 } else if kind == 'altstackclone' { 1440 } else if kind == 'altstackrestore' { 952 } else if kind == 'altstacknest' { 592 } else if kind == 'altstackframe' { 272 } else if kind == 'altstacksp' { 388 } else if kind == 'altstackhandler' { 19444 } else if kind == 'altstackabi' { 38880 } else if kind == 'sigactionabi' { 56000 } else if kind == 'sigactioncopy' { 4440 } else if kind == 'sigmaskcopy' { 3984 } else if kind == 'altstackcopy' { 560 } else if kind == 'sigwaitorder' { 27968 } else if kind == 'sigwaitcopy' { 1488 } else if kind == 'sigpending' { 428 } else { 0 }
 failures := if failed { 640 } else { 0 }
 summary := 'LINUX ' + name + ' SUMMARY: checks=' + checks.str() + ' failures=' + failures.str()
 marker := 'LINUX ' + name + if failed { ': FAIL' } else { ': PASS' }
 mut expected := map[string]bool{}
 mut mismatch_counts := map[string]int{}
 if focused { for ordinary in 0 .. 2 { for configuration in 0 .. 30 {
  stages := if failed { original_stages(configuration) } else { []int{} }
  child := 'LINUX AUTODISARM CHILD: ordinary=' + ordinary.str() + ' case=' + configuration.str()
   + ' status=0 bytes=8 checks=25 failures=' + stages.len.str()
  expected[child] = false
  for stage in stages {
   mismatch_counts['LINUX AUTODISARM MISMATCH: case=' + configuration.str() + ' stage=' + stage.str()]++
  }
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
  if focused && line.starts_with('LINUX AUTODISARM CHILD:') {
   require(line in expected && !expected[line], 'Changed or repeated disarming child')!
   expected[line] = true
  }
  if line.starts_with('LINUX ' + name + ' MISMATCH:') {
   require(failed && mismatch_counts[line] > 0, 'Changed disarming mismatch')!
   mismatch_counts[line]--; mismatches++
  }
  for bad in ['KERNEL PANIC', 'Kernel panic', 'FATAL EXCEPTION', 'REFERENCE FAIL', 'BUG:', 'LINUX ' + name + ' FAIL:'] {
   require(!line.contains(bad), 'Guest failure: ' + bad)!
  }
  if !failed { require(!line.contains(': FAIL') && !line.contains(' MISMATCH'), 'Unexpected failed check')! }
  else { require(line != 'LINUX AUTODISARM: PASS', 'Original kernel falsely passed')! }
 }
 require(markers == 1 && (checks == 0 || summaries == 1), 'Missing or repeated result')!
 require(mismatches == failures, 'Unexpected mismatch count')!
 for _, seen in expected { require(seen, 'Missing disarming child')! }
 for _, remaining in mismatch_counts { require(remaining == 0, 'Missing disarming mismatch')! }
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
		require(row.name in cases && row.name !in seen && selected.filter(it == row.name).len == 1
			&& row.exit_code == 0
			&& row.detail == '', 'Missing, repeated or changed maintained result')!
		seen[row.name] = true
	}
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
	require(digest(root + '/source/kernel/userland/signal.v')! == candidate_source, 'Different candidate source')!
	require(digest(root + '/source/kernel/userland/linux_signal_amd64.v')! == '537a36b46d4599dfed1e99df52ac7b9f502ff8812138d877a45e8c5288473196', 'Different x86 signal source')!
	require(digest(root + '/source/kernel/userland/userland_arm64.v')! == '5029f835e3266e1b4e1d0e3832a661d4a8af1959e7d8697d0375a7d4e8a6f3f8', 'Different ARM signal source')!
	fixture := digest(root + '/source/fixture/resethandfixture/core.v')!
	for suffix in ['arm', 'x86'] {
		path := root + '/' + suffix
		architecture := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
		build := json2.decode[Build](os.read_file(path + '/build/receipt.json')!)!
		require(build.architecture == suffix && build.profile == 'prod' && build.base_commit == integration_base
			&& build.candidate_commit == integration_candidate && build.candidate_source_sha256 == candidate_source
			&& build.build_executed && build.build_exit_code == 0 && build.inputs_before == build.inputs_after, 'Wrong or changed kernel build')!
		build_source(build.inputs_before, suffix, 'userland/signal.v', '411d614c7cd3614daa388aa25a2b8f03db51d7a2ebdba31b643ada40f650db3e', true)!
		build_source(build.inputs_before, suffix, 'userland/linux_signal_amd64.v', '537a36b46d4599dfed1e99df52ac7b9f502ff8812138d877a45e8c5288473196', true)!
		build_source(build.inputs_before, suffix, 'userland/userland_arm64.v', '5029f835e3266e1b4e1d0e3832a661d4a8af1959e7d8697d0375a7d4e8a6f3f8', true)!
		linked(root, manifest, build.inputs_before)!
		linked(root, manifest, build.outputs)!
		for flag in ['PROD=true', 'LIMINE_MP=1', 'ALLOC_TRACK=0', 'KERNEL_LINK_SEED=42'] { require(flag in build.command, 'Different build flags')! }
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + '/build/baseline-inputs.json')!)!)!
		require(os.read_file(path + '/build/build.log.status')!.trim_space() == '0', 'Failed kernel build')!
		kernel := digest(path + '/build/kernel/bin/vinix')!
		elf(os.read_bytes(path + '/build/kernel/bin/vinix')!, suffix)!
		compile := json2.decode[Compile](os.read_file(path + '/compile/receipt.json')!)!
		require(compile.architecture == suffix && input_pin(compile.inputs, '/resethandfixture/core.v')! == fixture, 'Different compiled probe source')!
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
			original := if suffix == 'arm' { 'a77b35189dbc6f805dc9d375e93980ca3e8f0ef6475cad7c7fbc49f79619582c' }
				else { '6650bd6a63e3dda5449421ac67c40bec4682a94b968c25e358aca1d0e22033d5' }
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
		require(reference.artifacts['controller_source'] == digest(root + '/tooling/resethand-reference.v')!
			&& reference.artifacts['wrapper_source'] == digest(root + '/source/fixture/resethandreferenceinit/core.v')!, 'Different reference source')!
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
	println('One-shot signal evidence: PASS (420 focused checks and 24 maintained suites on both architectures)')
}

fn flags_serial(text string, kind string) ! {
 if kind !in ['baseline-arm', 'baseline-x86', 'reference', 'native', 'sigactionflags'] {
  previous_serial(text, kind)!
  return
 }
 failed := kind.starts_with('baseline-')
 failures := if failed { 870 } else { 0 }
 summary := 'LINUX SIGACTIONFLAGS SUMMARY: checks=6480 failures=' + failures.str()
 marker := 'LINUX SIGACTIONFLAGS: ' + if failed { 'FAIL' } else { 'PASS' }
 mut expected := map[string]bool{}
 mut mismatches := map[string]int{}
 for ordinary in 0 .. 2 {
  uid := if ordinary == 0 { 0 } else { 1000 }
  gid := if ordinary == 0 { 0 } else { 2000 }
  for signal in [10, 12, 35] {
   expected['LINUX SIGACTIONFLAGS CASE: uid=' + uid.str() + ' gid=' + gid.str()
    + ' signal=' + signal.str() + ' checks=1080 failures=' + if failed { '145' } else { '0' }] = false
  }
 }
 // The fixture deliberately logs only the first 30 failures per credential.
 // All 870 failures are counted by the six case records and final summary.
 if failed { for index in 3 .. 9 { for stage in [13, 16, 17, 20, 24] {
  mismatches['LINUX SIGACTIONFLAGS MISMATCH: stage=' + stage.str() + ' index=' + index.str() + ' signal=10'] = 2
 } } }
 mut summaries := 0
 mut markers := 0
 mut versions := 0
 for raw in text.split_into_lines() {
  line := raw.trim_space()
  if linux_boot(line) { versions++ }
  if line == summary { summaries++ }
  else if line.starts_with('LINUX SIGACTIONFLAGS SUMMARY:') { return error('Wrong signal flag summary') }
  if line == marker { markers++ }
  else if line.starts_with('LINUX SIGACTIONFLAGS:') { return error('Wrong signal flag marker') }
  if line.starts_with('LINUX SIGACTIONFLAGS CASE:') {
   require(line in expected && !expected[line], 'Changed or repeated signal flag case')!
   expected[line] = true
  }
  if line.starts_with('LINUX SIGACTIONFLAGS MISMATCH') {
   require(failed && mismatches[line] > 0, 'Unexpected signal flag mismatch')!
   mismatches[line]--
  }
  for bad in ['KERNEL PANIC', 'Kernel panic', 'FATAL EXCEPTION', 'REFERENCE FAIL', 'BUG:', 'LINUX SIGACTIONFLAGS FAIL'] {
   require(!line.contains(bad), 'Guest failure: ' + bad)!
  }
  if !failed { require(!line.contains(': FAIL') && !line.contains(' MISMATCH'), 'Unexpected failed check')! }
 }
 require(markers == 1 && summaries == 1, 'Missing or repeated signal flag result')!
 for _, seen in expected { require(seen, 'Missing signal flag case')! }
 for _, count in mismatches { require(count == 0, 'Missing original signal flag mismatch')! }
 if kind == 'reference' { require(versions == 1, 'Missing or repeated Linux boot')! }
}

fn stages(kind string, mode int) []int {
 if !kind.starts_with('baseline-') || mode == 0 { return []int{} }
 if kind == 'baseline-arm' { return if mode == 3 { [11, 15] } else { [11, 15, 23, 24, 25, 27] } }
 return if mode == 3 { [15] } else { [15, 24] }
}

fn control_serial(kind string) string {
 mut lines := []string{}
 mut failures := 0
 for ordinary in 0 .. 2 {
  uid := if ordinary == 0 { 0 } else { 1000 }
  gid := if ordinary == 0 { 0 } else { 2000 }
  for signal in [10, 12, 28] { for mode in 0 .. 4 {
   expected := stages(kind, mode)
   for stage in expected {
    lines << 'LINUX RESETHAND MISMATCH: signal=' + signal.str() + ' mode=' + mode.str() + ' stage=' + stage.str()
   }
   failures += expected.len
   lines << 'LINUX RESETHAND CASE: uid=' + uid.str() + ' gid=' + gid.str() + ' signal=' + signal.str()
    + ' mode=' + mode.str() + ' checks=' + (if mode == 3 { 19 } else { 17 }).str() + ' failures=' + expected.len.str()
  } }
 }
 lines << 'LINUX RESETHAND SUMMARY: checks=420 failures=' + failures.str()
 lines << 'LINUX RESETHAND: ' + if failures == 0 { 'PASS' } else { 'FAIL' }
 return lines.join('\n') + '\n'
}

fn serial(text string, kind string) ! {
 if kind !in ['baseline-arm', 'baseline-x86', 'native', 'reference', 'resethand'] {
  flags_serial(text, kind)!
  return
 }
 mut records := map[string]int{}
 for line in control_serial(kind).split_into_lines().filter(it != '') { records[line]++ }
 mut versions := 0
 for raw in text.split_into_lines() {
  line := raw.trim_space()
  if linux_boot(line) { versions++ }
  for bad in ['KERNEL PANIC', 'Kernel panic', 'FATAL EXCEPTION', 'REFERENCE FAIL', 'BUG:', 'LINUX RESETHAND FAIL'] {
   require(!line.contains(bad), 'Guest failure: ' + bad)!
  }
  if line.starts_with('LINUX RESETHAND') {
   require(records[line] > 0, 'Unexpected, repeated or changed one-shot result: ' + line)!
   records[line]--
  } else {
   require(!line.contains(': FAIL') && !line.contains(' MISMATCH'), 'Unexpected failed check')!
  }
 }
 for _, count in records { require(count == 0, 'Missing one-shot case, mismatch or result')! }
 if kind == 'reference' { require(versions == 1, 'Missing or repeated Linux boot')! }
}

fn focused_controls() !int {
 good := control_serial('native')
 for kind in ['native', 'resethand'] { serial(good, kind)! }
 for kind in ['baseline-arm', 'baseline-x86'] { serial(control_serial(kind), kind)! }
 reference := 'Linux version control\n' + good
 serial(reference, 'reference')!
 serial(reference.replace('Linux version control', '[    0.000000] Linux version control'), 'reference')!
 mut refused := 0
 mut bad := []string{}
 for line in good.split_into_lines().filter(it != '') {
  bad << good.replace(line + '\n', '')
  bad << good + line + '\n'
 }
 for pair in [['checks=420', 'checks=419'], ['checks=17', 'checks=16'], ['failures=0', 'failures=1'],
  ['uid=1000 gid=2000', 'uid=0 gid=0'], ['mode=3', 'mode=2']] { bad << good.replace(pair[0], pair[1]) }
 for line in ['KERNEL PANIC injected', 'LINUX RESETHAND MISMATCH injected', 'LINUX RESETHAND FAIL: setup=1'] { bad << good + line + '\n' }
 bad << good + good
 bad << control_serial('baseline-arm')
 for text in bad {
  serial(text, 'native') or { refused++; continue }
  return error('Accepted negative focused serial control')
 }
 for kind in ['baseline-arm', 'baseline-x86'] {
  original := control_serial(kind)
  mut changed := []string{}
  for line in original.split_into_lines().filter(it != '') {
   changed << original.replace(line + '\n', '')
   changed << original + line + '\n'
  }
  changed << original.replace('stage=15', 'stage=14')
  changed << original.replace('failures=2', 'failures=1')
  changed << good
  changed << control_serial(if kind == 'baseline-arm' { 'baseline-x86' } else { 'baseline-arm' })
  for text in changed {
   serial(text, kind) or { refused++; continue }
   return error('Accepted changed original-kernel failure')
  }
 }
 for text in [good, reference + 'Linux version repeated\n'] {
  serial(text, 'reference') or { refused++; continue }
  return error('Accepted missing or repeated Linux boot')
 }
 return refused
}

fn controls() ! {
 mut refused := focused_controls()!
 focused := refused
 for bad in ['', '/absolute', 'relative/../escape'] {
  safe_relative(bad) or { refused++; continue }
  return error('Accepted unsafe path')
 }
 linked('.', Manifest{}, {'missing': 'pin'}) or { refused++ }
 require(refused == focused + 4, 'Focused negative control unexpectedly passed')!
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
 area := '/Users/alex/.cache/vinix-linux-compat/resethand-20261026'
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
 require(refused == focused + 25, 'Input identity control unexpectedly passed')!
 println('One-shot signal evidence controls: PASS (11 positive, ' + refused.str() + ' negative)')
}


fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { controls() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != 'check' { eprintln('Usage: resethand-evidence.v self-test | check BUNDLE'); exit(2) }
	check(os.args[2]) or { eprintln(err); exit(1) }
}
