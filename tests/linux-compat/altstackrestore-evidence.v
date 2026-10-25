// SPDX-License-Identifier: GPL-2.0-or-later
// Audit native alternate-stack restoration against Linux.
module main

import crypto.sha256
import json2
import os

const candidate_source = '2f93d741c584d56863a012e004be71e9af971fa27887c26c345b38f9bbbed3b0'
const integration_base = 'ca6031576041870ce9f8c23981594696a4bef84e'
const integration_candidate = '6753f67b20200d10961e58d48f3d3ff2e1dd01de'
const cases = ['altstackrestore', 'altstacknest', 'altstackframe', 'altstacksp', 'altstackhandler', 'altstackabi', 'sigactionabi', 'sigactioncopy', 'sigmaskcopy', 'altstackcopy', 'sigwaitorder', 'sigwaitcopy', 'sigpending', 'randomsignal', 'clonesignal', 'cloneclear', 'seccomp', 'runtime', 'futex', 'jit']

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
 area := '/Users/alex/.cache/vinix-linux-compat/altstackrestore-20261025'
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
 if !kind.starts_with('baseline-') { return false }
 return configuration in [1, 5, 6, 8, 12, 13, 15, 16, 19, 20]
  || (kind == 'baseline-arm' && configuration in [22, 23, 26])
}

fn serial(text string, kind string) ! {
 focused := kind in ['baseline-arm', 'baseline-x86', 'reference', 'native', 'altstackrestore']
 failed := kind.starts_with('baseline-')
 reference := kind == 'reference'
 name := if focused { 'ALTSTACKRESTORE' } else { kind.to_upper() }
 checks := if focused { 952 } else if kind == 'altstacknest' { 592 } else if kind == 'altstackframe' { 272 } else if kind == 'altstacksp' { 388 } else if kind == 'altstackhandler' { 19444 } else if kind == 'altstackabi' { 38880 } else if kind == 'sigactionabi' { 56000 } else if kind == 'sigactioncopy' { 4440 } else if kind == 'sigmaskcopy' { 3984 } else if kind == 'altstackcopy' { 560 } else if kind == 'sigwaitorder' { 27968 } else if kind == 'sigwaitcopy' { 1488 } else if kind == 'sigpending' { 428 } else { 0 }
 failures := if kind == 'baseline-arm' { 130 } else if kind == 'baseline-x86' { 100 } else { 0 }
 summary := 'LINUX ' + name + ' SUMMARY: checks=' + checks.str() + ' failures=' + failures.str()
 marker := 'LINUX ' + name + if failed { ': FAIL' } else { ': PASS' }
 mut expected := map[string]bool{}
 mut mismatch_counts := map[string]int{}
 if focused { for ordinary in 0 .. 2 { for configuration in 0 .. 28 {
  bad := failed_case(kind, configuration)
  child := 'LINUX ALTSTACKRESTORE CHILD: ordinary=' + ordinary.str() + ' case=' + configuration.str()
   + ' status=0 bytes=8 checks=16 failures=' + if bad { '5' } else { '0' }
  expected[child] = false
  if bad { for stage in [41, 31, 32, 33, 44] {
   mismatch := 'LINUX ALTSTACKRESTORE MISMATCH: stage=' + stage.str() + ' case=' + configuration.str()
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
  if focused && line.starts_with('LINUX ALTSTACKRESTORE CHILD:') {
   require(line in expected && !expected[line], 'Changed or repeated restoration child')!
   expected[line] = true
  }
  if line.starts_with('LINUX ' + name + ' MISMATCH:') {
   require(failed && mismatch_counts[line] > 0, 'Changed restoration mismatch')!
   mismatch_counts[line]--
   mismatches++
  }
  for bad in ['KERNEL PANIC', 'Kernel panic', 'FATAL EXCEPTION', 'REFERENCE FAIL', 'BUG:', 'LINUX ' + name + ' FAIL:'] {
   require(!line.contains(bad), 'Guest failure: ' + bad)!
  }
  if !failed { require(!line.contains(': FAIL') && !line.contains(' MISMATCH'), 'Unexpected failed check')! }
  else { require(line != 'LINUX ALTSTACKRESTORE: PASS', 'Original kernel falsely passed')! }
 }
 require(markers == 1 && (checks == 0 || summaries == 1), 'Missing or repeated result')!
 require(mismatches == failures, 'Unexpected mismatch count')!
 for _, seen in expected { require(seen, 'Missing restoration child')! }
 for _, remaining in mismatch_counts { require(remaining == 0, 'Missing restoration mismatch')! }
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
	for source, pin in {'linux_signal_amd64.v': 'bb503415f6707c3aeebcf2fcd48800f7e5550fc9f36a8781ea4794add5ca7aee', 'userland_arm64.v': '8365bddea663871a6b1e0cb590e76da7a6b81756feaa6b71acfc1dd687a739eb'} {
		require(digest(root + '/source/kernel/userland/' + source)! == pin, 'Different signal-frame source')!
	}
	require(digest(root + '/source/kernel/memory/mmap/mmap.v')! == 'abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f', 'Different mapping source')!
	require(digest(root + '/source/kernel/userland/exit.v')! == '2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff', 'Different exit source')!
	require(digest(root + '/source/kernel/posixtimer/posix_timer.v')! == 'a5874e940e181b10c8e4416c2f7cb2359c619bd40f54f09c64cce921712b21ab', 'Different timer source')!
	require(digest(root + '/source/kernel/syscall/table/gaps.v')! == 'f7a135f09229e9808ab5e4b75c3a0874d7087d3da4032aebbc7ab66e4e122a84', 'Different syscall table source')!
	for source, pin in {'proc_amd64.v': 'be298f73befc262ee9edaeda025c1c538ed0435b355d573d6f6134a23299f5f4', 'proc_arm64.v': 'cb9dcb352594ba6c9f0381421f5fc42af665d054ece60e0119babfa1b60c3358'} {
		require(digest(root + '/source/kernel/proc/' + source)! == pin, 'Different process source')!
	}
	fixture := digest(root + '/source/fixture/altstackrestorefixture/core.v')!
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
		for source, pin in {'linux_signal_amd64.v': 'bb503415f6707c3aeebcf2fcd48800f7e5550fc9f36a8781ea4794add5ca7aee', 'userland_arm64.v': '8365bddea663871a6b1e0cb590e76da7a6b81756feaa6b71acfc1dd687a739eb'} {
			build_source(build.inputs_before, suffix, 'userland/' + source, pin, true)!
		}
		for source, pin in {'proc_amd64.v': 'be298f73befc262ee9edaeda025c1c538ed0435b355d573d6f6134a23299f5f4', 'proc_arm64.v': 'cb9dcb352594ba6c9f0381421f5fc42af665d054ece60e0119babfa1b60c3358'} {
			build_source(build.inputs_before, suffix, 'proc/' + source, pin, false)!
		}
		require(input_pin(build.inputs_before, '/kernel/memory/mmap/mmap.v')! == 'abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f', 'Changed mapping/exit source')!
		require(input_pin(build.inputs_before, '/kernel/userland/exit.v')! == '2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff', 'Changed mapping/exit source')!
		linked(root, manifest, build.inputs_before)!
		linked(root, manifest, build.outputs)!
		require(os.read_file(path + '/build/build.log.status')!.trim_space() == '0', 'Failed kernel build')!
		kernel := digest(path + '/build/kernel/bin/vinix')!
		elf(os.read_bytes(path + '/build/kernel/bin/vinix')!, suffix)!
		compile := json2.decode[Compile](os.read_file(path + '/compile/receipt.json')!)!
		require(compile.architecture == suffix && input_pin(compile.inputs, '/altstackrestorefixture/core.v')! == fixture, 'Different compiled probe source')!
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
			original := if suffix == 'arm' { '8e6e52d19bf4ed1cb9c0e18d2c5874d206ee446c92583befb4da2c4de627f181' }
				else { '4de60361e177630383da4dea1a865a8e331e424a08077a7a5ded621848ce5cda' }
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
		require(reference.artifacts['controller_source'] == digest(root + '/tooling/altstackrestore-reference.v')!
			&& reference.artifacts['wrapper_source'] == digest(root + '/source/fixture/altstackrestorereferenceinit/core.v')!, 'Different reference source')!
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
	println('Alternate-stack restoration evidence: PASS (952 focused checks and 20 maintained suites on both architectures)')
}

fn control_serial(kind string) string {
 mut lines := []string{}
 for ordinary in 0 .. 2 { for configuration in 0 .. 28 {
  bad := failed_case(kind, configuration)
  if bad { for stage in [41, 31, 32, 33, 44] {
   lines << 'LINUX ALTSTACKRESTORE MISMATCH: stage=' + stage.str() + ' case=' + configuration.str()
  } }
  lines << 'LINUX ALTSTACKRESTORE CHILD: ordinary=' + ordinary.str() + ' case=' + configuration.str()
   + ' status=0 bytes=8 checks=16 failures=' + if bad { '5' } else { '0' }
 } }
 failures := if kind == 'baseline-arm' { 130 } else if kind == 'baseline-x86' { 100 } else { 0 }
 lines << 'LINUX ALTSTACKRESTORE SUMMARY: checks=952 failures=' + failures.str()
 lines << 'LINUX ALTSTACKRESTORE: ' + if failures == 0 { 'PASS' } else { 'FAIL' }
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
 for bad in [good.replace('checks=952', 'checks=951'), good.replace('failures=0', 'failures=1'),
  good.replace('LINUX ALTSTACKRESTORE: PASS\n', ''), good + good, good + 'KERNEL PANIC injected\n',
  good + 'LINUX ALTSTACKRESTORE MISMATCH: injected\n', good.replace('ordinary=1 case=27', 'ordinary=1 case=26'),
  good.replace('status=0 bytes=8 checks=16', 'status=7 bytes=0 checks=0'),
  good.all_after('\n'), arm] {
  serial(bad, 'native') or { refused++; continue }
  return error('Accepted negative focused serial control')
 }
 for kind in ['baseline-arm', 'baseline-x86'] {
  baseline := if kind == 'baseline-arm' { arm } else { x86 }
  for bad in [baseline.replace('checks=952', 'checks=951'), baseline.replace('failures=5', 'failures=4'),
   baseline.replace('status=0', 'status=11'), baseline.replace('stage=41 case=1\n', 'stage=41 case=0\n'),
   baseline + 'LINUX ALTSTACKRESTORE MISMATCH: stage=41 case=1\n', good,
   if kind == 'baseline-arm' { x86 } else { arm }] {
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
 area := '/Users/alex/.cache/vinix-linux-compat/altstackrestore-20261025'
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
 require(refused == 51, 'Input identity control unexpectedly passed')!
 println('Alternate-stack restoration evidence controls: PASS (10 positive, 51 negative)')
}


fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { controls() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != 'check' { eprintln('Usage: altstackrestore-evidence.v self-test | check BUNDLE'); exit(2) }
	check(os.args[2]) or { eprintln(err); exit(1) }
}
