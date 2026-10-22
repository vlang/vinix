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
	return Pin{ path: os.abs_path(path), sha256: sha256.hexhash(os.read_file(path)!) }
}

// Admission checks must also run with -prod, which removes V assertions.
fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn verify(pins []Pin) ! {
	for item in pins {
		require(pin(item.path)! == item, 'evidence digest mismatch: ' + item.path)!
	}
}

// Historical build receipts retain their original paths and hashes. Tool
// sources can advance independently; an exact content-addressed copy preserves
// those old inputs without attributing an old run to the new implementation.
fn verify_inputs(pins []Pin, archive string, source_prefix string) ! {
	for item in pins {
		require(item.sha256.len == 64, 'invalid input digest length: ' + item.path)!
		for byte in item.sha256.bytes() {
			require((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`), 'invalid input digest: ' + item.path)!
		}
		require(os.abs_path(item.path) == item.path, 'input path must be absolute: ' + item.path)!
		current := pin(item.path) or { Pin{} }
		if current == item { continue }
		require(item.path.starts_with(source_prefix), 'changed input outside historical source scope: ' + item.path)!
		require(pin(archive + '/' + item.sha256)!.sha256 == item.sha256, 'historical input digest mismatch: ' + item.path)!
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
		require(!found, 'duplicate counter ' + name)!
		text := part.all_after('=')
		require(text.len > 0, 'empty counter ' + name)!
		for byte in text {
			require(byte >= `0` && byte <= `9`, 'invalid counter ' + name)!
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
	require(parts.len == 7 && parts[0] == 'GUEST' && parts[1] == 'TLS', 'invalid tracked allocation marker: ' + line)!
	require(parts[2] in tlsruntime.modes() && parts[3] == 'retained', 'invalid tracked mode: ' + line)!
	require(parts[4] == '0' && parts[5] == 'tracked' && parts[6] == 'bytes', 'nonzero or invalid retained allocation: ' + line)!
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
		require(!found && tracked_mode(line)! == mode, 'duplicate or unexpected probe mode: ' + line)!
		found = true
	}
	require(found, 'missing probe allocation marker: ' + mode)!
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
			require(!tls, 'duplicate curl version banner')!
			parts := line.fields()
			require(parts.len >= 4 && version(parts[1], ''), 'invalid curl version banner')!
			mut libcurl := false
			mut openssl := false
			for part in parts {
				if version(part, 'libcurl/') { libcurl = true }
				if version(part, 'OpenSSL/') { openssl = true }
			}
			require(libcurl && openssl, 'missing curl TLS implementation version')!
			tls = true
		}
		if line.starts_with('GUEST TLS file baseline=') {
			require(!baseline && line.fields().len == 5, 'duplicate or malformed file baseline')!
			initial := field(line, 'baseline')!
			require(initial <= ~u64(0) - 131072, 'file baseline overflows reservation ceiling')!
			ceiling = field(line, 'ceiling')!
			require(ceiling == initial + 131072, 'incorrect reservation ceiling')!
			baseline = true
		} else if line == native_pass {
			require(!passed, 'duplicate native completion marker')!
			passed = true
		} else if line.starts_with('GUEST TLS ') {
			mode := tracked_mode(line)!
			require(baseline && mode !in tracked, 'missing baseline or duplicate tracked mode: ' + mode)!
			tracked[mode] = true
		}
		if line.starts_with('COLLECTION STRESS settled ') {
			mode := line.all_after('settled ').all_before(':')
			require(mode in tlsruntime.modes() && mode !in settled && mode in tracked, 'invalid or duplicate settlement: ' + mode)!
			require(line.fields().len == 7, 'malformed settlement: ' + mode)!
			field(line, 'initial')!
			require(baseline && field(line, 'bytes')! <= ceiling && field(line, 'waits')! <= 30, 'unsettled reservation: ' + mode)!
			settled[mode] = true
		}
	}
	require(baseline && passed && tls && settled.len == tlsruntime.modes().len && tracked.len == tlsruntime.modes().len, 'incomplete native TLS evidence')!
	require(text.contains('HWTEST PASS packages-https-runtime'), 'missing native hardware completion marker')!
	require(!text.contains('HWTEST FAIL') && !text.contains('V panic:') && !text.contains('Out of memory'), 'native failure marker')!
}

fn requests(text string, digest string, repetitions int) ! {
	require(repetitions in [1, 2], 'invalid request repetition count')!
	mut counts := map[string]int{}
	mut setups := map[string]int{}
	for line in text.split_into_lines() {
		fields := line.fields()
		require(fields.len == 4 && fields[0] in tlsruntime.modes(), 'malformed request: ' + line)!
		mode := fields[0]
		if fields[1] == 'setup' {
			require(!mode.starts_with('fetch-') && fields[3] == '-', 'invalid setup request: ' + line)!
			require(fields[2] == if setups[mode] % 2 == 0 { 'index.json' } else { 'index.sig' }, 'incorrect setup resource: ' + line)!
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
		require(fields[1] == route, 'incorrect request route: ' + line)!
		step := counts[mode] % 2
		if mode.starts_with('refresh-') {
			require(fields[2] == if step == 0 { 'index.json' } else { 'index.sig' }, 'incorrect refresh resource: ' + line)!
			require(fields[3] == '-', 'unexpected refresh range: ' + line)!
		} else {
			resource := if mode.starts_with('install-') || mode.ends_with('-http') || mode.ends_with('-redirect') {
				'objects/' + digest
			} else {
				'payload'
			}
			require(fields[2] == resource, 'incorrect payload resource: ' + line)!
			ranged := !mode.ends_with('-fresh') && !mode.ends_with('-size') && !(tlsruntime.requests(mode) == 2 && step == 1)
			require(fields[3] == if mode.ends_with('-truncated') && step == 1 {
				'bytes=1536-'
			} else if ranged {
				'bytes=512-'
			} else {
				'-'
			}, 'incorrect request range: ' + line)!
		}
		counts[mode]++
	}
	for mode in tlsruntime.modes() {
		require(counts[mode] == repetitions * (tlsruntime.cycles + tlsruntime.warmups) * tlsruntime.requests(mode), 'incorrect request count: ' + mode)!
		require(setups[mode] == if mode.starts_with('fetch-') { 0 } else { 2 * repetitions }, 'incorrect setup count: ' + mode)!
	}
}

fn retain() ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	prefix := root + '/tests/packages/results/2026-10-22/https-runtime-'
	if os.args.len == 5 && os.args[1] == '--check-inputs' {
		verify_inputs(json2.decode[[]Pin](os.read_file(os.args[2])!)!, os.args[3], os.args[4])!
		println('GUEST TLS historical input evidence PASS')
		return
	}
	if os.args.len == 3 && os.args[1] == '--check-native' {
		native(os.read_file(os.args[2])!)!
		println('GUEST TLS native evidence PASS')
		return
	}
	if os.args.len == 5 && os.args[1] == '--check-requests' {
		requests(os.read_file(os.args[2])!, os.args[3], strconv.atoi(os.args[4])!)!
		println('GUEST TLS request evidence PASS')
		return
	}
	if os.args.len == 2 && os.args[1] == '--verify' {
		ledger := json2.decode[Ledger](os.read_file(prefix + 'ledger.json')!)!
		require(ledger.format == 1, 'unsupported TLS ledger format')!
		verify_inputs(ledger.inputs, prefix + 'inputs', root + '/tools/')!
		verify(ledger.evidence)!
		println('GUEST TLS retained hashes PASS')
		return
	}
	require(os.args.len == 4, 'usage: https-runtime-retain HOST_WORK ARM_WORK X86_WORK | --verify')!
	os.mkdir_all(os.dir(prefix))!
	mut inputs := []Pin{}
	mut evidence := []Pin{}
	controls := prefix + 'evidence-check.txt'
	require(os.read_file(controls)!.contains('GUEST TLS evidence controls PASS'), 'missing evidence controls')!
	evidence << pin(controls)!
	input_controls := prefix + 'input-check.txt'
	require(os.read_file(input_controls)!.contains('GUEST TLS historical input controls PASS'), 'missing historical input controls')!
	evidence << pin(input_controls)!
	mode_controls := prefix + 'retainer-modes.txt'
	mode_text := os.read_file(mode_controls)!
	require(mode_text.contains('GUEST TLS normal and prod retainer controls PASS'), 'missing retainer build-mode controls')!
	require(mode_text.contains('Retainer source SHA256 ' + pin(@FILE)!.sha256 + '\n'), 'retainer build-mode source mismatch')!
	evidence << pin(mode_controls)!
	cleanup := prefix + 'cleanup-check.txt'
	cleanup_text := os.read_file(cleanup)!
	require(cleanup_text.contains('GUEST TLS controller failure cleanup PASS'), 'missing controller cleanup check')!
	require(cleanup_text.contains('Controller source SHA256 ' + pin(root + '/tests/packages/https-runtime-check.v')!.sha256 + '\n'), 'controller cleanup source mismatch')!
	evidence << pin(cleanup)!
	planning := prefix + 'root-planning.txt'
	require(os.read_file(planning)!.contains('1000 root-planning install/remove/upgrade/deploy and removal-plan success/refusal cycles retain zero tracked bytes and preserve borrowed inputs PASS'), 'missing root-planning ownership check')!
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
		require(receipt.format == 1 && receipt.checks.len == if i == 0 { 51 } else { 4 }, 'invalid TLS receipt format or check count: ' + work)!
		verify_inputs(receipt.inputs, prefix + 'inputs', root + '/tools/')!
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
		})!
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
		root + '/tests/packages/https-runtime-input-check.v',
		prefix + 'inputs/README.md',
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
			require(unique.last() == item, 'conflicting input digest: ' + item.path)!
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
