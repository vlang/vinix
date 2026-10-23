// SPDX-License-Identifier: GPL-2.0-or-later
// Audit native priority query qualification without external tools.
module main

import crypto.sha256
import json2
import os

const candidate_source = '950db21493f4edab4bf9be97407f4f546397ce82e65a6a263e076f5d9aaff8ae'
const syscall_source = 'f125c27895e9e28ea346207211907868a1d2f24cb61faa489c50d2189ffb33c7'
const integration_base = 'a544610c9f559e97e86c38dc931c0c8125e174c9'
const integration_candidate = '730d43fb3d1505c4e7f8ad92c5292586d9c841db'

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
	exit_code     int
	detail        string
}

struct Maintained {
	architecture  string
	kernel_sha256 string
	results       []MaintainedCase
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

fn serial(text string, kind string) ! {
	baseline := kind in ['baseline-arm', 'baseline-x86']
	reference := kind == 'reference'
	name := 'PRIOQUERY'
	summary := 'LINUX PRIOQUERY SUMMARY: checks=6199 failures=' + if baseline { '403' } else { '0' }
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
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line == summary {
			summaries++
		} else if line.starts_with('LINUX ' + name + ' SUMMARY:') {
			return error('Unexpected summary')
		}
		if line == marker { markers++ }
		if line.starts_with('LINUX ' + name + ' MISMATCH:') { mismatches++ }
		if line.contains('KERNEL PANIC') || line.contains('Kernel panic') || line.contains('FATAL EXCEPTION')
			|| line.contains('REFERENCE FAIL') || line.contains('LINUX ' + name + ' FAIL:') {
			return error('Unexpected guest failure')
		}
		if !baseline && line.contains('LINUX ' + name + ': FAIL') {
			return error('Unexpected failing result')
		}
		if baseline && line.contains('LINUX ' + name + ': PASS') {
			return error('Baseline falsely passed')
		}
	}
	require(summaries == 1 && markers == 1, 'Missing or repeated result')!
	expected_mismatches := if baseline { 16 } else { 0 }
	require(mismatches == expected_mismatches, 'Unexpected mismatch count')!
	if reference {
		require(text.contains('Linux version 6.12.51'), 'Reference kernel version missing')!
	}
}

fn regression(text string, name string) ! {
	if name == 'prioquery' { serial(text, 'native')!; return }
	marker := 'LINUX ' + name.to_upper()
	mut passes := 0
	mut finals := 0
	for raw in text.split_into_lines() {
		line := raw.trim_space()
		if line == marker + ': PASS' { passes++ }
		if line.contains('KERNEL PANIC') || line.contains('FATAL EXCEPTION')
			|| line.contains(marker + ' FAIL') || line.contains(marker + ': FAIL')
			|| line.contains('MISMATCH') { return error('Maintained guest failure: ' + name) }
		if line.starts_with(marker + ' FINAL:') {
			require(line.ends_with(' failures=0'), 'Maintained cases failed: ' + name)!
			finals++
		}
	}
	expected := if name == 'threadnice' { 0 } else if name == 'grouptid' { 24 } else { 8 }
	require(passes == 1 && finals == expected, 'Missing or repeated maintained result: ' + name)!
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
	require(digest(root + '/source/kernel/proc/nice.v')! == candidate_source
		&& digest(root + '/source/kernel/syscall/table/linux_common.v')! == syscall_source, 'Wrong candidate source')!
	for suffix in ['arm', 'x86'] {
		architecture := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
		path := root + '/' + suffix
		probe := digest(path + '/compile/probe')!
		elf(os.read_bytes(path + '/compile/probe')!, suffix)!
		compiled := json2.decode[Compile](os.read_file(path + '/compile/receipt.json')!)!
		require(compiled.architecture == suffix && compiled.inputs.len >= 5 && compiled.outputs.len >= 5, 'Incomplete probe compile')!
		linked(root, manifest, compiled.inputs)!
		linked(root, manifest, compiled.outputs)!
		build := json2.decode[Build](os.read_file(path + '/build/receipt.json')!)!
		require(build.architecture == suffix && build.profile == 'prod' && build.build_executed
			&& build.build_exit_code == 0 && build.base_commit == integration_base
			&& build.candidate_commit == integration_candidate && build.candidate_source_sha256 == candidate_source,
			'Wrong build identity or result')!
		require(build.inputs_before.len > 100 && build.inputs_before == build.inputs_after, 'Build inputs changed')!
		build_root := '/kernel-' + suffix + '/kernel/'
		require(input_pin(build.inputs_before, build_root + 'proc/nice.v')! == candidate_source
			&& input_pin(build.inputs_before, build_root + 'syscall/table/linux_common.v')! == syscall_source, 'Build used different priority sources')!
		linked(root, manifest, build.inputs_before)!
		linked(root, manifest, build.outputs)!
		require(os.read_file(path + '/build/build.log.status')!.trim_space() == '0', 'Build command failed')!
		kernel := digest(path + '/build/kernel/bin/vinix')!
		elf(os.read_bytes(path + '/build/kernel/bin/vinix')!, suffix)!
		elf(os.read_bytes(path + '/baseline/kernel/bin/vinix')!, suffix)!
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
		require(reference.artifacts['controller_source'] == digest(root + '/tooling/prioquery-reference.v')!, 'Different reference controller')!
		require(reference.artifacts['wrapper_source'] == digest(root + '/source/fixture/prioqueryreferenceinit/core.v')!, 'Different wrapper source')!
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + '/reference/inputs.json')!)!)!
		serial(os.read_file(path + '/reference/serial.log')!, 'reference')!
		require(digest(path + '/reference/init')! == digest(path + '/compile/reference-init')!, 'Different Linux wrapper')!
		maintained := json2.decode[Maintained](os.read_file(path + '/maintained/receipt.json')!)!
		require(maintained.architecture == architecture && maintained.kernel_sha256 == kernel
			&& maintained.results.len == 7, "Wrong maintained runner identity")!
		mut seen := map[string]bool{}
		for result in maintained.results {
			require(result.name in ['prioquery', 'threadnice', 'niceabi', 'niceadmit', 'attrnice', 'groupabi', 'grouptid'] && result.name !in seen && result.exit_code == 0 && result.detail == '', 'Maintained runner failed')!
			seen[result.name] = true
			require(result.source_sha256 == digest(root + "/source/fixture/" + result.name + "fixture/core.v")!
				&& result.init_sha256 == digest(path + "/maintained/" + result.name + "/init")!, "Different maintained fixture")!
			linked(root, manifest, result.source_inputs)!
			elf(os.read_bytes(path + "/maintained/" + result.name + "/init")!, suffix)!
			regression(os.read_file(path + '/maintained/' + result.name + '/serial.log')!, result.name)!
		}
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + "/maintained/controller-inputs.json")!)!)!
		maintained_attempt := if suffix == 'arm' { 'third' } else { 'fourth' }
		for name in ['compile-second-' + suffix + '-record', 'kernel-second-' + suffix + '-record',
			'reference-first-' + suffix, 'candidate-second-' + suffix, 'maintained-' + maintained_attempt + '-' + suffix + '-record'] {
			require(os.read_file(root + '/attempts/' + name + '.status')!.trim_space() == '0', 'Recorded controller failed: ' + name)!
		}
		require(os.read_file(root + '/attempts/baseline-first-' + suffix + '.status')!.trim_space() == '1', 'Original kernel unexpectedly passed')!
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
	require(os.read_file(root + '/attempts/reference-controls-first.status')!.trim_space() == '0'
		&& os.read_file(root + '/attempts/reference-controls-first.log')!.contains('PASS (2 positive, 9 negative)'), 'Linux parser controls failed')!
	println('Native priority query evidence: PASS (both architectures; hashes, builds, 6199 Linux/native checks, 403 baseline failures, seven maintained suites)')
}

fn controls() ! {
	// Build receipts pin both the frozen source and its worktree copy.
	// Select the architecture worktree while retaining ambiguity refusals.
	pins := {
		'/cache/kernel-arm/kernel/proc/nice.v': candidate_source
		'/cache/source/kernel/proc/nice.v': candidate_source
	}
	require(input_pin(pins, '/kernel-arm/kernel/proc/nice.v')! == candidate_source,
		'Failed to select the architecture source')!
	mut path_refused := 0
	for suffix in ['/kernel/proc/nice.v', '/kernel-x86/kernel/proc/nice.v'] {
		input_pin(pins, suffix) or { path_refused++; continue }
		return error('Accepted ambiguous or absent build source')
	}
	require(path_refused == 2, 'Build path controls failed')!
	good := 'LINUX PRIOQUERY SUMMARY: checks=6199 failures=0\nLINUX PRIOQUERY: PASS\n'
	serial(good, 'native')!
	serial('Linux version 6.12.51\n' + good.replace('PRIOQUERY: PASS', 'PRIOQUERY REFERENCE: PASS'), 'reference')!
	mut baseline := 'LINUX PRIOQUERY SUMMARY: checks=6199 failures=403\nLINUX PRIOQUERY: FAIL\n'
	for _ in 0 .. 16 { baseline += 'LINUX PRIOQUERY MISMATCH: stage=1\n' }
	serial(baseline, 'baseline-arm')!
	serial(baseline, 'baseline-x86')!
	mut refused := 0
	for bad in [good.replace('6199', '6198'), good.replace('failures=0', 'failures=1'),
		good.replace('LINUX PRIOQUERY: PASS\n', ''), good + good,
		good + 'LINUX PRIOQUERY MISMATCH: injected\n', good + 'KERNEL PANIC injected\n'] {
		serial(bad, 'native') or {
			refused++
			continue
		}
		return error('Accepted negative serial control')
	}
	for bad in [baseline.replace('failures=403', 'failures=402'), baseline + 'LINUX PRIOQUERY MISMATCH: extra\n'] {
		serial(bad, 'baseline-arm') or { refused++; continue }
		return error('Accepted negative baseline control')
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
	require(refused == 9, 'Architecture control accepted')!
	println('Priority query evidence controls: PASS (11 negative controls)')
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
		eprintln('Usage: prioquery-evidence --self-test | check EVIDENCE-DIR')
		exit(2)
	}
}
