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

fn evidence(root string, category string, workload string, arch string, name string, limits string) !ApplicationEvidence {
	base := 'tests/linux-compat/results/2026-10-11/'
	report := base + name + '.json'
	receipt := base + 'inputs-' + name + '.json'
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
			name := if arch == 'aarch64' { language + '-aarch64' } else { 'applications-x86_64' }
			// The initial catalog uses a legacy controller receipt basename.
			if arch == 'x86_64' {
				base := 'tests/linux-compat/results/2026-10-11/'
				mut row := audit_application(os.read_file(root + '/' + base + name + '.json')!,
					os.read_file(root + '/' + base + 'inputs-x86_64.json')!, arch, language)!
				row.category = 'language runtimes'
				row.report = base + name + '.json'
				row.receipt = base + 'inputs-x86_64.json'
				row.limitations = 'Initial catalog limitation; native x86-64 compiler/runtime workload remains unqualified'
				rows << row
			} else {
				rows << evidence(root, 'language runtimes', language, arch, name,
					if language == 'java' { 'OpenJDK thread/NIO/TCP and JAR workload needs the privileged VINIX_ALLOW_WX launch policy; ordinary-user JIT and desktop install/update unqualified' }
					else { 'Go compilation, threads, files, timers and TCP; package install/update and desktop integration unqualified' })!
			}
		}
		for browser in ['firefox', 'chromium'] {
			name := if arch == 'x86_64' { 'browsers-x86_64' }
				else if browser == 'firefox' { 'firefox-shared-memory-aarch64' }
				else { 'browsers-before-aarch64' }
			rows << evidence(root, 'browsers', browser, arch, name,
				if browser == 'firefox' { 'Default-policy ordinary-user headless run times out without JavaScript/PNG proof; libpci/libGL probing fails; sandbox, portals and install/update unqualified' }
				else { 'Packaged sandbox helper is mode 0755; required setuid setup refused, crash handler ptrace unavailable; no JavaScript/DOM proof' })!
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
	return ApplicationIndex{'2026-10-11', 'vinix-guest receipts; exact recorded inputs only',
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
