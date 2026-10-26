// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve/reclaim only the explicitly reviewed interrupted first x86 attempt.
module main

import crypto.sha256
import json2
import os

const state = '/Users/alex/Library/Caches/vinix-codex/section14/package-perf-x86-20261026'
const root = state + '/attempt01'
const archive = state + '/attempt01.tar.gz'
const output = state + '/attempt01-preservation'
const retained = '/Users/alex/Library/Caches/vinix-codex/section14/integration-20261026/routing-retained-inputs'
const sealer = retained + '/tools/software-release-routing-bundle'
const reader = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a/archive-controls-build-03/evidence-archive-check-prod'
const reader_source = '/Users/alex/code/vinix/tests/packages/evidence-archive-check.v'
const prepared_hash = '69ccf163367ce9f2c690a76358e2bbddbf347726a898a690872ca86927022e6f'

struct Eligibility {
	device u64
	inode u64
	pins map[string]string
	archive_sha256 string
	manifest_sha256 string
}

fn sha(path string) !string {
	before := os.lstat(path)!
	if before.get_filetype() != .regular { return error('requires ordinary file: ' + path) }
	mut f := os.open(path)!
	defer { f.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut bytes := []u8{len: 1024 * 1024}
	defer { unsafe { bytes.free() } }
	for {
		n := f.read(mut bytes) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	after := os.lstat(path)!
	if after.get_filetype() != .regular || before.dev != after.dev || before.inode != after.inode || before.size != after.size {
		return error('file identity changed: ' + path)
	}
	return sum.sum([]u8{}).hex()
}

fn invoke(args []string, log string) ! {
	if os.exists(log) || os.is_link(log) { return error('requires new command log') }
	os.write_file(log + '.argv.json', json2.encode(args) + '\n')!
	r := os.exec(args)
	os.write_file(log, r.output)!
	os.write_file(log + '.exit.json', json2.encode({'exit_code': r.exit_code}) + '\n')!
	if r.exit_code != 0 { return error('command failed: ' + log) }
}

fn identity() !os.Stat {
	i := os.lstat(root)!
	if i.get_filetype() != .directory || os.real_path(root) != root {
		return error('requires canonical original directory')
	}
	return i
}

fn tools() !map[string]string {
	mut pins := map[string]string{}
	for path, expected in {
		sealer: '0bf024564aba9cedfac1fd8f92b3f117e5735511cafb1dfb409f449ca00ca94b'
		reader: '8808f2000e0ed1f9977a2ed9bd42ef0eaf0a4143be3440222a38be3237d1757a'
		reader_source: '59e10b89aa8416207bfaad35446b8dd389d64425c61585dca7328ce15c88ebfa'
	} {
		pins[path] = sha(path)!
		if pins[path] != expected { return error('reviewed tool differs') }
	}
	pins[@FILE] = sha(@FILE)!
	if pins[@FILE] != sha256.hexhash($embed_file('archive-x86-failure.v').to_string()) {
		return error('compiled producer source differs')
	}
	pins[os.executable()] = sha(os.executable())!
	return pins
}

fn verify(pins map[string]string) ! {
	for path, hash in pins {
		if sha(path)! != hash { return error('preserved input changed: ' + path) }
	}
}

fn preserve() ! {
	i := identity()!
	if os.exists(output) || os.is_link(output) || os.exists(archive) || os.is_link(archive) ||
		os.exists(root + '/bundle.sha256') || os.exists(root + '/after-inputs.json') ||
		sha(root + '/prepared.json')! != prepared_hash {
		return error('requires original interrupted attempt and fresh output')
	}
	serial := os.read_file(root + '/results/serial.log')!
	if serial.contains('PERF-RESULT') || serial.contains('PERF-DONE') {
		return error('expected failed no-result diagnostic')
	}
	mut pins := tools()!
	os.mkdir(output)!
	os.mkdir(root + '/failure-retention')!
	for path in [state + '/native-input-check.log', state + '/native-prepare.log', state + '/native-run.log',
		state + '/tools/run-x86', @FILE, os.executable(), reader, reader_source, sealer] {
		hash := sha(path)!
		dest := root + '/failure-retention/' + os.file_name(path)
		os.cp(path, dest, fail_if_exists: true)!
		if sha(dest)! != hash || sha(path)! != hash { return error('copy changed') }
		pins[path] = hash
	}
	os.write_file(root + '/failure-retention/disposition.json', json2.encode({
		'prepared_sha256': prepared_hash
		'observed_controller_exit': '1 after operator SIGINT'
		'observed_result': 'No PERF result or completion marker; native qualification failed/incomplete.'
		'diagnosis': 'Original V init inherited framebuffer console; corrected init explicitly routes stdout/stderr to /dev/com1. No claim that unobserved workloads executed.'
		'run_argv': json2.encode([state + '/tools/run-x86', 'run', root, prepared_hash])
	}) + '\n')!
	os.setenv('COPYFILE_DISABLE', '1', true)
	invoke([sealer, 'seal', root, archive], output + '/seal.log')!
	archive_hash := sha(archive)!
	os.cp(root + '/bundle.sha256', output + '/original-manifest.sha256', fail_if_exists: true)!
	manifest_hash := sha(output + '/original-manifest.sha256')!
	invoke([sealer, 'check', root], output + '/original-before.log')!
	invoke([reader, 'check', archive, 'attempt01', output + '/original-manifest.sha256', archive_hash], output + '/strict-stream.log')!
	invoke([sealer, 'check', root], output + '/original-after.log')!
	pins[archive] = archive_hash
	pins[output + '/original-manifest.sha256'] = manifest_hash
	pins[archive + '.sha256'] = sha(archive + '.sha256')!
	verify(pins)!
	j := identity()!
	if i.dev != j.dev || i.inode != j.inode { return error('original identity changed') }
	os.write_file(output + '/eligible.json', json2.encode(Eligibility{u64(i.dev), i.inode, pins, archive_hash, manifest_hash}) + '\n')!
	println('PRESERVED failed attempt01; eligibility sha256=' + sha(output + '/eligible.json')!)
}

fn reclaim(expected string) ! {
	if sha(output + '/eligible.json')! != expected || os.exists(output + '/completed.json') {
		return error('requires exact reviewed eligibility and fresh completion')
	}
	e := json2.decode[Eligibility](os.read_file(output + '/eligible.json')!)!
	verify(tools()!)!
	verify(e.pins)!
	i := identity()!
	if u64(i.dev) != e.device || i.inode != e.inode { return error('original identity differs') }
	invoke([sealer, 'check', root], output + '/reclaim-original-before.log')!
	invoke([reader, 'check', archive, 'attempt01', output + '/original-manifest.sha256', e.archive_sha256], output + '/reclaim-strict-stream.log')!
	invoke([sealer, 'check', root], output + '/reclaim-original-after.log')!
	verify(e.pins)!
	j := identity()!
	if i.dev != j.dev || i.inode != j.inode { return error('original identity changed') }
	// V os.rmdir_all checks links before recursing; no archive deletion occurs.
	os.rmdir_all(root)!
	if os.exists(root) || os.is_link(root) { return error('expanded original remains') }
	verify(e.pins)!
	os.write_file(output + '/completed.json', json2.encode({
		'eligible_sha256': expected
		'expanded_original_removed': 'true'
		'archive_sha256': e.archive_sha256
		'manifest_sha256': e.manifest_sha256
		'scope': 'Failed diagnostic only; complete original checks and independent strict archive verification passed twice. No native acceptance.'
	}) + '\n')!
	println('RECLAIM PASS: independently verified failed attempt01 only')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'preserve' {
		preserve() or { eprintln(err); exit(1) }
	} else if os.args.len == 3 && os.args[1] == '--reclaim-reviewed' {
		reclaim(os.args[2]) or { eprintln(err); exit(1) }
	} else { eprintln('expected preserve | --reclaim-reviewed ELIGIBILITY_SHA256'); exit(1) }
}
