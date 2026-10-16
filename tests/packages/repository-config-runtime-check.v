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
	kind string = 'repository-configuration'
	scenario string = 'packages-repository-config'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-repository-config', guest: 'tests/packages/repository-config-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/repository_configuration_test.v', path: 'usr/share/package-fixtures/repository-config-core' },
			hwhost.Program{ source: 'tools/packages/pkgprotocol/repository_configuration_test.v', path: 'usr/share/package-fixtures/repository-config-protocol' },
			hwhost.Program{ source: 'tools/packages/pkgcore/configuration_observation_test.v', path: 'usr/share/package-fixtures/configuration-observation' },
		], scenarios: [hwhost.Scenario{ name: 'packages-repository-config', arches: ['aarch64', 'x86_64'],
			about: 'configuration-only repository discovery and reviewed revocation while maintenance metadata remains refused',
			required: ['HWTEST START packages-repository-config',
				'REPOSITORY CONFIG fresh/locked/corrupt configuration checks; damaged cache/history listing and reviewed revocation preserve maintenance failures PASS',
				'REPOSITORY CONFIG protocol explicit scope, complete bounded metadata, legacy separation and owned close PASS',
				'CONFIGURATION PROCESS repository-config-core PASS', 'CONFIGURATION PROCESS repository-config-protocol PASS',
				'CONFIGURATION OBSERVATION both architectures, independent repository/policy fields, canonical policy order, unchanged wire bytes and stored offline flag PASS',
				'CONFIGURATION OBSERVATION 1000 legacy/default and growing 64-record cycles retire scratch; full 4096 repository/pin observations preserve source configuration PASS',
				'CONFIGURATION OBSERVATION maintenance FIFOs remain unopened; 1000 schema/missing/alias/FIFO/lock/busy refusal cycles retire scratch and permit restored reads PASS',
				'CONFIGURATION PROCESS configuration-observation PASS',
				'HWTEST PASS packages-repository-config'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-repository-config-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('repository-config-core', root + 'repository-config-core')!,
			artifact('repository-config-protocol', root + 'repository-config-protocol')!,
			artifact('configuration-observation', root + 'configuration-observation')!,
			artifact('serial-log', base + '/packages-repository-config/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
