// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt {
	format int = 1
	sdk int = 1
	architecture string
	completed_at i64
	kind string = 'publisher-manifest-decoding'
	scenario string = 'packages-manifest-decode'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-manifest-decode', guest: 'tests/packages/manifest-decode-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/manifest_decode_test.v', path: 'usr/share/package-fixtures/manifest-decode' },
			hwhost.Program{ source: 'tools/packages/pkgcore/index_schema_test.v', path: 'usr/share/package-fixtures/index-schema' },
			hwhost.Program{ source: 'tools/packages/pkgcore/configuration_observation_test.v', path: 'usr/share/package-fixtures/configuration-observation' },
		], scenarios: [hwhost.Scenario{ name: 'packages-manifest-decode', arches: ['aarch64', 'x86_64'],
			about: 'bounded publisher manifests, signed-schema maintenance and unchanged scoped configuration ownership',
			required: ['HWTEST START packages-manifest-decode',
				'MANIFEST DECODE both architectures, owned template/inventory fields, independent results, exact canonical bytes and full 16384 payload bounds PASS',
				'MANIFEST DECODE omitted package/dependency/payload defaults, full integer ranges and complete-inventory refusals retire scratch PASS',
				'MANIFEST DECODE every truncated prefix and schema/UTF8/number/permission refusal cycles retire scratch PASS',
				'MANIFEST DECODE exact 8 MiB and limit-minus-one accepted; metadata/payload/argument/dependency/association/string overflows refused PASS',
				'MANIFEST DECODE invalid pack input preserves source and absent destination; restored template defaults and captured inventory publish unchanged canonical bytes PASS',
				'MANIFEST PROCESS manifest-decode PASS',
				'MANIFEST PROCESS index-schema PASS',
				'MANIFEST PROCESS configuration-observation PASS',
				'CONFIGURATION OBSERVATION both architectures, independent repository/policy fields, canonical policy order, unchanged wire bytes and stored offline flag PASS',
				'CONFIGURATION OBSERVATION 1000 legacy/default and growing 64-record cycles retire scratch; full 4096 repository/pin observations preserve source configuration PASS',
				'CONFIGURATION OBSERVATION maintenance FIFOs remain unopened; 1000 schema/missing/alias/FIFO/lock/busy refusal cycles retire scratch and permit restored reads PASS',
				'HWTEST PASS packages-manifest-decode'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-manifest-decode-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('manifest-decode', root + 'manifest-decode')!,
			artifact('index-schema', root + 'index-schema')!, artifact('configuration-observation', root + 'configuration-observation')!,
			artifact('serial-log', base + '/packages-manifest-decode/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
