// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import crypto.sha256
import strconv
import tlsruntime

struct Pin {
	path   string
	sha256 string
}

struct Check {
	name      string
	argv      []string
	seconds   f64
	artifacts []Pin
}

struct Receipt {
	format int
	inputs []Pin
	checks []Check
}

struct Ledger {
	format   int = 1
	inputs   []Pin
	evidence []Pin
}

fn pin(path string) !Pin {
	return Pin{ path: os.abs_path(path), sha256: sha256.sum(os.read_bytes(path)!).hex() }
}

fn verify(pins []Pin) ! {
	for item in pins {
		assert pin(item.path)! == item, item.path
	}
}

fn save(source string, target string, mut evidence []Pin) ! {
	os.cp(source, target)!
	evidence << pin(target)!
}

fn field(line string, name string) !u64 {
	mut found := false
	mut value := u64(0)
	for part in line.fields() {
		if !part.starts_with(name + '=') { continue }
		assert !found, 'duplicate counter ' + name
		text := part.all_after('=')
		assert text.len > 0, 'empty counter ' + name
		for byte in text {
			assert byte >= `0` && byte <= `9`, 'invalid counter ' + name
		}
		value = strconv.parse_uint(text, 10, 64)!
		found = true
	}
	if !found { return error('missing counter ' + name) }
	return value
}

const native_pass = 'GUEST TLS 23 cases with 8 measured cycles preserve authenticated state, certificate policy, bounded recovery and retired replies PASS'

fn tracked_mode(line string) !string {
	parts := line.fields()
	assert parts.len == 7 && parts[0] == 'GUEST' && parts[1] == 'TLS'
	assert parts[2] in tlsruntime.modes() && parts[3] == 'retained'
	assert parts[4] == '0' && parts[5] == 'tracked' && parts[6] == 'bytes', line
	return parts[2]
}

fn version(token string, prefix string) bool {
	return token.starts_with(prefix) && token.len > prefix.len
		&& token[prefix.len] >= `0` && token[prefix.len] <= `9`
}

fn probe(text string, mode string) ! {
	mut found := false
	for line in text.split_into_lines() {
		if !line.starts_with('GUEST TLS ') { continue }
		assert !found && tracked_mode(line)! == mode
		found = true
	}
	assert found
}

fn native(text string) ! {
	mut ceiling := u64(0)
	mut settled := map[string]bool{}
	mut tracked := map[string]bool{}
	mut baseline := false
	mut passed := false
	mut tls := false
	for line in text.split_into_lines() {
		// Certificate refusals also print "curl failed to verify ...". That
		// explanation is not the single version banner required below.
		if line.starts_with('curl ') && !line.starts_with('curl failed to verify ') {
			assert !tls
			parts := line.fields()
			assert parts.len >= 4 && version(parts[1], '')
			mut libcurl := false
			mut openssl := false
			for part in parts {
				if version(part, 'libcurl/') { libcurl = true }
				if version(part, 'OpenSSL/') { openssl = true }
			}
			assert libcurl && openssl, 'missing curl TLS implementation version'
			tls = true
		}
		if line.starts_with('GUEST TLS file baseline=') {
			assert !baseline && line.fields().len == 5
			initial := field(line, 'baseline')!
			assert initial <= ~u64(0) - 131072
			ceiling = field(line, 'ceiling')!
			assert ceiling == initial + 131072
			baseline = true
		} else if line == native_pass {
			assert !passed
			passed = true
		} else if line.starts_with('GUEST TLS ') {
			mode := tracked_mode(line)!
			assert baseline && mode !in tracked
			tracked[mode] = true
		}
		if line.starts_with('COLLECTION STRESS settled ') {
			mode := line.all_after('settled ').all_before(':')
			assert mode in tlsruntime.modes() && mode !in settled && mode in tracked
			assert line.fields().len == 7
			field(line, 'initial')!
			assert baseline && field(line, 'bytes')! <= ceiling && field(line, 'waits')! <= 30
			settled[mode] = true
		}
	}
	assert baseline && passed && tls && settled.len == tlsruntime.modes().len && tracked.len == tlsruntime.modes().len
	assert text.contains('HWTEST PASS packages-https-runtime')
	assert !text.contains('HWTEST FAIL') && !text.contains('V panic:') && !text.contains('Out of memory')
}

fn requests(text string, digest string, repetitions int) {
	assert repetitions in [1, 2]
	mut counts := map[string]int{}
	mut setups := map[string]int{}
	for line in text.split_into_lines() {
		fields := line.fields()
		assert fields.len == 4 && fields[0] in tlsruntime.modes(), line
		mode := fields[0]
		if fields[1] == 'setup' {
			assert !mode.starts_with('fetch-') && fields[3] == '-'
			assert fields[2] == if setups[mode] % 2 == 0 { 'index.json' } else { 'index.sig' }
			setups[mode]++
			continue
		}
		route := if mode.ends_with('-corrupt') {
			'no-range-corrupt'
		} else if mode.ends_with('-fallback') {
			'no-range'
		} else if mode.ends_with('-truncated') {
			'truncated'
		} else if mode.ends_with('-http') {
			'forbidden'
		} else if mode.ends_with('-redirect') {
			'insecure-redirect'
		} else if mode.ends_with('-size') {
			'oversized'
		} else {
			'ranges'
		}
		assert fields[1] == route, line
		step := counts[mode] % 2
		if mode.starts_with('refresh-') {
			assert fields[2] == if step == 0 { 'index.json' } else { 'index.sig' }
			assert fields[3] == '-', line
		} else {
			resource := if mode.starts_with('install-') || mode.ends_with('-http') || mode.ends_with('-redirect') {
				'objects/' + digest
			} else {
				'payload'
			}
			assert fields[2] == resource, line
			ranged := !mode.ends_with('-fresh') && !mode.ends_with('-size') && !(tlsruntime.requests(mode) == 2 && step == 1)
			assert fields[3] == if mode.ends_with('-truncated') && step == 1 {
				'bytes=1536-'
			} else if ranged {
				'bytes=512-'
			} else {
				'-'
			}, line
		}
		counts[mode]++
	}
	for mode in tlsruntime.modes() {
		assert counts[mode] == repetitions * (tlsruntime.cycles + tlsruntime.warmups) * tlsruntime.requests(mode), mode
		assert setups[mode] == if mode.starts_with('fetch-') { 0 } else { 2 * repetitions }, mode
	}
}

fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	prefix := root + '/tests/packages/results/2026-10-22/https-runtime-'
	if os.args.len == 3 && os.args[1] == '--check-native' {
		native(os.read_file(os.args[2])!)!
		println('GUEST TLS native evidence PASS')
		return
	}
	if os.args.len == 5 && os.args[1] == '--check-requests' {
		requests(os.read_file(os.args[2])!, os.args[3], strconv.atoi(os.args[4])!)
		println('GUEST TLS request evidence PASS')
		return
	}
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		assert ledger.format == 1
		verify(ledger.inputs)!
		verify(ledger.evidence)!
		println('GUEST TLS retained hashes PASS')
		return
	}
	assert os.args.len == 4, 'usage: https-runtime-retain HOST_WORK ARM_WORK X86_WORK | --verify'
	os.mkdir_all(os.dir(prefix))!
	mut inputs := []Pin{}
	mut evidence := []Pin{}
	controls := prefix + 'evidence-check.txt'
	assert os.read_file(controls)!.contains('GUEST TLS evidence controls PASS')
	evidence << pin(controls)!
	cleanup := prefix + 'cleanup-check.txt'
	cleanup_text := os.read_file(cleanup)!
	assert cleanup_text.contains('GUEST TLS controller failure cleanup PASS')
	assert cleanup_text.contains('Controller source SHA256 ' + pin(root + '/tests/packages/https-runtime-check.v')!.sha256 + '\n')
	evidence << pin(cleanup)!
	planning := prefix + 'root-planning.txt'
	assert os.read_file(planning)!.contains('1000 root-planning install/remove/upgrade/deploy and removal-plan success/refusal cycles retain zero tracked bytes and preserve borrowed inputs PASS')
	evidence << pin(planning)!
	for i, directory in os.args[1..] {
		state := os.abs_path(directory)
		work := if i == 0 { state } else { state + '-tls' }
		label := if i == 0 {
			'host'
		} else if i == 1 {
			'aarch64'
		} else {
			'x86_64'
		}
		receipt := json2.decode[Receipt](os.read_file(work + '/qualification.json')!)!
		assert receipt.format == 1 && receipt.checks.len == if i == 0 { 51 } else { 4 }
		verify(receipt.inputs)!
		inputs << receipt.inputs
		fixture := json2.decode[tlsruntime.Fixture](os.read_file(work + if i == 0 {
			'/probe.json'
		} else {
			'/fixture.json'
		})!)!
		requests(os.read_file(work + '/requests.txt')!, fixture.payload.sha256, if i == 0 {
			2
		} else {
			1
		})
		save(work + '/qualification.json', prefix + label + '.json', mut evidence)!
		mut summary := ''
		for check in receipt.checks {
			verify(check.artifacts)!
			inputs << check.artifacts
			summary += check.name + ' PASS\n'
			if i == 0 && !check.name.ends_with('-compile') && check.name != 'certificate' {
				text := os.read_file(work + '/' + check.name + '.txt')!
				mode := check.name.all_after(if check.name.starts_with('probe-sanitize-') {
					'probe-sanitize-'
				} else {
					'probe-'
				})
				probe(text, mode)!
				save(work + '/' + check.name + '.txt', prefix + check.name + '.txt', mut evidence)!
			}
		}
		if i == 0 {
			os.write_file(prefix + 'host.txt', summary)!
			evidence << pin(prefix + 'host.txt')!
		}
		save(work + '/requests.txt', prefix + label + '-requests.txt', mut evidence)!
		for file in ['certificate.cnf', 'ca.pem', 'certificate.txt', 'untrusted/ca.pem', 'manifest.json',
			'repository/index.json', 'repository/index.sig']! {
			inputs << pin(work + '/' + file)!
		}
		if i > 0 {
			serial := state + '/packages-https-runtime/serial.log'
			native(os.read_file(serial)!)!
			save(serial, prefix + label + '.serial.txt', mut evidence)!
			save(state + '/packages-https-runtime/qemu.log', prefix + label + '.qemu.txt', mut evidence)!
			for file in ['guest/init', 'guest/init.c', 'guest/build.log', 'guest/program-0/tls-probe',
				'guest/program-0/tls-probe.c', 'guest/program-0/build.log']! {
				inputs << pin(state + '/' + file)!
			}
			inputs << pin(work + '/fixture.json')!
			inputs << pin(work + '/curl-files.json')!
		} else {
			for file in ['probe.json', 'probe-sanitize.json']! { inputs << pin(work + '/' + file)! }
		}
	}
	for path in [@FILE, root + '/tests/packages/https-runtime-evidence-check.v',
		root + '/tests/packages/https-runtime-cleanup-check.v',
		root + '/tools/packages/pkgcore/removal_test.v',
		root + '/tests/packages/https-runtime-check.md', root + '/roadmap.md',
		root + '/tools/packages/SDK.md', root + '/tools/packages/README.md',
		root + '/docs/application-distribution.md']! {
		inputs << pin(path)!
	}
	inputs.sort(a.path < b.path)
	mut unique := []Pin{}
	for item in inputs {
		if unique.len > 0 && unique.last().path == item.path {
			assert unique.last() == item
			continue
		}
		unique << item
	}
	os.write_file(prefix + 'ledger.json', json2.encode(Ledger{ inputs: unique, evidence: evidence }) + '\n')!
	println('GUEST TLS retained ' + unique.len.str() + ' input/artifact hashes and ' + evidence.len.str() + ' evidence hashes PASS')
}

fn main() {
	retain() or {
		eprintln(err)
		exit(1)
	}
}
