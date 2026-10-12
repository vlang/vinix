// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct ApplicationEvidence {
mut:
	category string
	workload string
	architecture string
	execution_path string
	status string
	detail string
	limitations string
	report string
	receipt string
	report_sha256 string
	receipt_sha256 string
	kernel_sha256 string
	driver_sha256 string
	full_lifecycle_qualified bool
}

struct ApplicationIndex {
	date string
	context string
	complete_support_qualified bool
	applications []ApplicationEvidence
}

fn valid_hash(value string) bool {
	return value.len == 64 && value.bytes().all(it in '0123456789abcdef'.bytes())
}

// Guest reports are content-addressed by their controller receipts. Never
// promote a host run, a renamed architecture or an edited result to evidence.
fn audit_application(raw string, receipt_raw string, arch string, workload string) !ApplicationEvidence {
	report := json2.decode[json2.Any](raw)!.as_map()
	receipt := json2.decode[json2.Any](receipt_raw)!.as_map()
	path := 'native-' + arch
	if arch !in ['aarch64', 'x86_64'] || report['context']!.str() != 'vinix-guest'
		|| report['execution_path']!.str() != path || receipt['execution_path']!.str() != path
		|| receipt['architecture']!.str() != arch {
		return error('application evidence has a host or mismatched architecture/path')
	}
	inputs := receipt['inputs']!.as_map_of_strings()
	for name in ['guest_report', 'kernel', 'snapshot_kernel', 'workloads', 'rootfs_manifest', 'init_source'] {
		if !valid_hash(inputs[name]) { return error('missing or invalid input hash: ' + name) }
	}
	if inputs['guest_report'] != sha256.sum(raw.trim_space().bytes()).hex()
		|| inputs['kernel'] != inputs['snapshot_kernel']
		|| inputs['workloads'] != report['suite_sha256']!.str() {
		return error('application report or kernel/driver inputs do not match the receipt')
	}
	if workload !in receipt['cases']!.str().split(',') {
		return error('controller did not request the reported workload')
	}
	mut names := map[string]bool{}
	mut selected := map[string]json2.Any{}
	mut failed := false
	for item in report['results']!.as_array() {
		verdict := item.as_map()
		name := verdict['name']!.str()
		status := verdict['status']!.str()
		if name in names || status !in ['passed', 'failed', 'unsupported'] {
			return error('duplicate workload or unknown verdict')
		}
		names[name] = true
		failed = failed || status != 'passed'
		if status == 'unsupported' && !verdict['detail']!.str().starts_with('unsupported:') {
			return error('unsupported workload does not publish its missing dependency')
		}
		if name == workload { selected = verdict.clone() }
	}
	if selected.len == 0 || (receipt['exit_code']!.int() == 0) == failed {
		return error('missing verdict or controller exit contradicts workload results')
	}
	if selected['status']!.str() == 'passed' && report['commands']!.as_array().len < 2 {
		return error('a version-only run is not application qualification')
	}
	if selected['status']!.str() == 'passed' && workload in ['firefox', 'chromium'] {
		audit_browser_proof(report, receipt, workload)!
	}
	return ApplicationEvidence{
		workload: workload
		architecture: arch
		execution_path: path
		status: selected['status']!.str()
		detail: selected['detail']!.str()
		report_sha256: inputs['guest_report']
		receipt_sha256: sha256.sum(receipt_raw.bytes()).hex()
		kernel_sha256: inputs['kernel']
		driver_sha256: inputs['workloads']
		// Workload receipts explicitly separate this broader acceptance gate.
		full_lifecycle_qualified: report['complete_lifecycle_qualified']!.bool()
	}
}

// A passing verdict alone must not promote a browser's version banner or
// unrelated HTTP request to JavaScript/render qualification.
fn audit_browser_proof(report map[string]json2.Any, receipt map[string]json2.Any, name string) ! {
	uid := report['uid']!.int()
	if uid <= 0 || receipt['uid']!.int() != uid {
		return error('passing browser evidence requires the recorded ordinary-user identity')
	}
	mut proofs := []map[string]json2.Any{}
	for item in report['browsers']!.as_array() {
		proof := item.as_map()
		if proof['name']!.str() == name { proofs << proof }
	}
	if proofs.len != 1 { return error('passing browser evidence requires one matching render proof') }
	proof := proofs[0]
	callback := proof['javascript_callback']!.str()
	if !callback.starts_with('GET /result/') || !callback.ends_with('/42 HTTP/1.1') {
		return error('browser JavaScript callback does not contain the required result')
	}
	nonce := callback.all_after('GET /result/').all_before('/42 HTTP/1.1')
	if !valid_hash(nonce) || !valid_hash(proof['page_sha256']!.str()) {
		return error('browser page and nonce hashes are missing or invalid')
	}
	if name == 'firefox' && !valid_hash(proof['screenshot_sha256']!.str()) {
		return error('Firefox render proof has no valid PNG hash')
	}
	if name == 'chromium' && !proof['dom_verified']!.bool() {
		return error('Chromium render proof has no verified DOM')
	}
	program := proof['executable']!.str()
	if !program.starts_with('/') { return error('browser proof does not identify an absolute executable') }
	mut count := 0
	mut rendered := false
	mut version := false
	for item in report['commands']!.as_array() {
		command := item.as_map()
		argv := command['argv']!.as_array().map(it.str())
		if argv.len == 0 || argv[0] != program { continue }
		count++
		if command['exit_code']!.int() != 0 || command['timed_out']!.bool()
			|| command['output_limited']!.bool() || !valid_hash(command['executable_sha256']!.str()) {
			return error('passing browser proof contains a failed or incomplete command')
		}
		if argv.any(it == '--no-sandbox' || (it.starts_with('--disable-') && it.contains('sandbox'))) {
			return error('passing browser proof disables its sandbox')
		}
		for key, value in command['environment_overrides']!.as_map_of_strings() {
			if key.starts_with('MOZ_DISABLE_') && key.ends_with('_SANDBOX') && value != '' && value != '0' {
				return error('passing browser proof disables its sandbox through the environment')
			}
		}
		if '--version' in argv { version = true }
		if argv.any(it == '--headless' || it.starts_with('--headless=')) {
			if name == 'firefox' && '--screenshot' in argv { rendered = true }
			if name == 'chromium' && '--dump-dom' in argv
				&& command['stdout']!.str().contains('id="verdict">42</p>') { rendered = true }
		}
	}
	if count < 2 || !version || !rendered { return error('browser proof lacks matching version and headless render commands') }
}

fn evidence(root string, category string, workload string, arch string, name string, limits string) !ApplicationEvidence {
	base := 'tests/linux-compat/results/2026-10-11/'
	report := base + name + '.json'
	receipt := base + 'inputs-' + name + '.json'
	return evidence_files(root, category, workload, arch, report, receipt, limits)
}

fn evidence_files(root string, category string, workload string, arch string, report string, receipt string, limits string) !ApplicationEvidence {
	mut result := audit_application(os.read_file(root + '/' + report)!,
		os.read_file(root + '/' + receipt)!, arch, workload)!
	result.category = category
	result.limitations = limits
	result.report = report
	result.receipt = receipt
	return result
}

fn application_index(root string) !ApplicationIndex {
	mut rows := []ApplicationEvidence{}
	for arch in ['aarch64', 'x86_64'] {
		for category, workload in {'media': 'media', 'office': 'office', 'databases': 'sqlite', 'servers': 'server'} {
			limits := match workload {
				'media' { 'FFmpeg software encode/decode; audio/video capture, GPU codecs and desktop playback unqualified' }
				'office' { 'Gnumeric conversion, save and reopen; printing, accessibility, clipboard and portal integration unqualified' }
				'sqlite' { 'SQLite WAL, integrity and reopen; concurrent writers, recovery and other database engines unqualified' }
				else { 'BusyBox exact-content loopback HTTP; DNS/TLS, system service dependencies and isolation unqualified' }
			}
			rows << evidence(root, category, workload, arch, 'catalog-' + arch, limits)!
		}
		for language in ['go', 'java'] {
			if language == 'java' {
				base := 'tests/linux-compat/results/2026-10-12/jit-java-' + arch
				rows << evidence_files(root, 'language runtimes', language, arch, base + '.json', base + '-inputs.json',
					'OpenJDK 21 compiles, runs and creates/reopens a JAR as UID 1000 through a read-only administrator-approved JIT runtime mount; extracted inputs do not qualify package scripts, install/update or desktop integration')!
				continue
			}
			rows << evidence(root, 'language runtimes', language, arch, language + '-' + arch,
				if arch == 'x86_64' { 'Go compiles and runs as UID 1000: threads, files, timers, subprocesses and TCP; extracted inputs do not qualify package installation or desktop integration' }
				else { 'Go compilation, threads, files, timers and TCP; package install/update and desktop integration unqualified' })!
		}
		for browser in ['firefox', 'chromium'] {
			if browser == 'firefox' {
				base := 'tests/linux-compat/results/2026-10-12/jit-firefox-' + arch
				rows << evidence_files(root, 'browsers', browser, arch, base + '.json', base + '-inputs.json',
					'Firefox 128.14.0esr default sandbox settings, UID 1000, scoped read-only JIT mount, 4096 MiB guest: actual JavaScript callback and PNG; full isolation, GPU, portals and installed lifecycle unqualified')!
				continue
			}
			name := if arch == 'x86_64' { 'browsers-x86_64' }
				else { 'browsers-before-aarch64' }
			rows << evidence(root, 'browsers', browser, arch, name,
				'Packaged sandbox helper is mode 0755; required setuid setup refused, crash handler ptrace unavailable; no JavaScript/DOM proof')!
		}
		if arch == 'aarch64' {
			rows << evidence(root, 'games', 'games', arch, 'game-doom-aarch64',
				'Chocolate Doom repeats 1710 timedemo ticks using licensed external IWAD and SDL dummy video; visible frames, audio/input/GPU, saves and install/update unqualified')!
		} else {
			base := 'tests/linux-compat/results/2026-10-11/'
			mut row := audit_application(os.read_file(root + '/' + base + 'applications-x86_64.json')!,
				os.read_file(root + '/' + base + 'inputs-x86_64.json')!, arch, 'games')!
			row.category = 'games'
			row.report = base + 'applications-x86_64.json'
			row.receipt = base + 'inputs-x86_64.json'
			row.limitations = 'Native x86-64 game workload, graphics/input/audio, saves and package lifecycle unqualified'
			rows << row
		}
	}
	rows.sort(a.key() < b.key())
	return ApplicationIndex{'2026-10-12', 'vinix-guest receipts; exact recorded inputs only',
		rows.all(it.status == 'passed' && it.full_lifecycle_qualified), rows}
}

fn application_markdown(index ApplicationIndex) string {
	intro := 'Every result is verified against its guest controller receipt and kernel/driver hashes. '
		+ 'Passed workloads cover their stated predicates; full install/run/save/update/desktop support remains unqualified. '
		+ 'Failed and unsupported dependencies are retained. This index does not rerun or upgrade dated evidence.'
	mut lines := ['# Linux application regression coverage', '',
		'Generated by `build-support/run-v-tool.sh tools/linux-compat/applications`.', '',
		intro, '',
		'| Family | Application | Architecture | Workload result | Receipt | Dependencies and limits |',
		'| --- | --- | --- | --- | --- | --- |']
	for row in index.applications {
		lines << '| ' + row.category + ' | ' + row.workload + ' | ' + row.architecture + ' | ' + row.status
			+ ' | [guest](../' + row.report + '), [inputs](../' + row.receipt + ') | ' + row.limitations + ' |'
	}
	return lines.join('\n') + '\n'
}

fn (row ApplicationEvidence) key() string {
	return row.category + '/' + row.architecture + '/' + row.workload
}
