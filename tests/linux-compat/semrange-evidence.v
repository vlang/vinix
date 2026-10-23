// SPDX-License-Identifier: GPL-2.0-or-later
// Audit the bounded native semaphore SETVAL range qualification without external tools.
module main

import crypto.sha256
import json2
import os

const candidate_source = '0ee9007d431ac0f225a59e391af2d379dcbb6380c6d6da813f0f2f1fa9adaab1'
const integration_base = 'f7db726bbba470e3b4746a90197a8b3958b62a78'
const integration_candidate = '7eb399c6e8da852729a04fa52943a848eb1b6c92'

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
	regression := kind == 'regression'
	word := kind == 'word'
	pid := kind == 'pid'
	array := kind == 'array'
	baseline := kind == 'baseline'
	reference := kind == 'reference'
	name := if regression { 'SEMABI' } else if word { 'SEMWORD' } else if pid { 'SEMPID' } else if array { 'SEMARRAY' } else { 'SEMRANGE' }
	summary := 'LINUX ' + name + ' SUMMARY: checks=' + if regression {
		'175 failures=0'
	} else if word {
		'276 failures=0'
	} else if pid {
		'261 failures=0'
	} else if array {
		'457 failures=0'
	} else if baseline {
		'4200 failures=240'
	} else {
		'4200 failures=0'
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
	require(mismatches == if baseline { 240 } else { 0 }, 'Unexpected mismatch count')!
	if reference {
		require(text.contains('Linux version 6.12.51'), 'Reference kernel version missing')!
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
	require(digest(root + '/source/sysvsem.v')! == candidate_source, 'Wrong candidate source')!
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
		require(input_pin(build.inputs_before, '/kernel/sysvsem/sysvsem.v')! == candidate_source, 'Build used different semaphore source')!
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
			serial(text, kind)!
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
		require(reference.artifacts['controller_source'] == digest(root + '/tooling/semrange-reference.v')!, 'Different reference controller')!
		require(reference.artifacts['wrapper_source'] == digest(root + '/source/fixture/semrangereferenceinit/core.v')!, 'Different wrapper source')!
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + '/reference/inputs.json')!)!)!
		serial(os.read_file(path + '/reference/serial.log')!, 'reference')!
		require(digest(path + '/reference/init')! == digest(path + '/compile/reference-init')!, 'Different Linux wrapper')!
		maintained := json2.decode[Maintained](os.read_file(path + '/maintained/receipt.json')!)!
		require(maintained.architecture == architecture && maintained.kernel_sha256 == kernel
			&& maintained.results.len == 5, "Wrong maintained runner identity")!
		mut seen := map[string]bool{}
		for result in maintained.results {
			require(result.name in ["semrange", "semarray", "sempid", "semword", "semabi"] && result.name !in seen && result.exit_code == 0 && result.detail == "", "Maintained runner failed")!
			seen[result.name] = true
			require(result.source_sha256 == digest(root + "/source/fixture/" + result.name + "fixture/core.v")!
				&& result.init_sha256 == digest(path + "/maintained/" + result.name + "/init")!, "Different maintained fixture")!
			linked(root, manifest, result.source_inputs)!
			elf(os.read_bytes(path + "/maintained/" + result.name + "/init")!, suffix)!
			serial(os.read_file(path + "/maintained/" + result.name + "/serial.log")!, if result.name == "semabi" { "regression" } else if result.name == "semword" { "word" } else if result.name == "sempid" { "pid" } else if result.name == "semarray" { "array" } else { "native" })!
		}
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + "/maintained/controller-inputs.json")!)!)!
		for prefix in ['compile-second-', 'build-first-', 'reference-first-', 'native-first-', 'maintained-first-'] {
			require(os.read_file(root + '/attempts/' + prefix + suffix + '.status')!.trim_space() == '0', 'Recorded controller failed: ' + prefix + suffix)!
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
	require(os.read_file(root + '/attempts/parser-controls.status')!.trim_space() == '0'
		&& os.read_file(root + '/attempts/parser-controls.log')!.contains('PASS (2 positive, 9 negative)'), 'Linux parser controls failed')!
	println('Native semaphore SETVAL range evidence: PASS (both architectures; hashes, builds, Linux, baseline, maintained runner and 457/261/276/175-case semaphore regressions)')
}

fn controls() ! {
	good := 'LINUX SEMRANGE SUMMARY: checks=4200 failures=0\nLINUX SEMRANGE: PASS\n'
	serial(good, 'native')!
	serial('LINUX SEMARRAY SUMMARY: checks=457 failures=0\nLINUX SEMARRAY: PASS\n', 'array')!
	serial('LINUX SEMPID SUMMARY: checks=261 failures=0\nLINUX SEMPID: PASS\n', 'pid')!
	serial('LINUX SEMWORD SUMMARY: checks=276 failures=0\nLINUX SEMWORD: PASS\n', 'word')!
	serial('LINUX SEMABI SUMMARY: checks=175 failures=0\nLINUX SEMABI: PASS\n', 'regression')!
	mut baseline := 'LINUX SEMRANGE SUMMARY: checks=4200 failures=240\nLINUX SEMRANGE: FAIL\n'
	for _ in 0 .. 240 { baseline += 'LINUX SEMRANGE MISMATCH: stage=1\n' }
	serial(baseline, 'baseline')!
	mut refused := 0
	for bad in [good.replace('4200', '4199'), good.replace('failures=0', 'failures=1'),
		good.replace('LINUX SEMRANGE: PASS\n', ''), good + good,
		good + 'LINUX SEMRANGE MISMATCH: injected\n', good + 'KERNEL PANIC injected\n'] {
		serial(bad, 'native') or {
			refused++
			continue
		}
		return error('Accepted negative serial control')
	}
	for bad in [baseline.replace('failures=240', 'failures=239'), baseline + 'LINUX SEMRANGE MISMATCH: extra\n'] {
		serial(bad, 'baseline') or { refused++; continue }
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
	println('Semaphore SETVAL range evidence controls: PASS (9 negative controls)')
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
		eprintln('Usage: semrange-evidence --self-test | check EVIDENCE-DIR')
		exit(2)
	}
}
