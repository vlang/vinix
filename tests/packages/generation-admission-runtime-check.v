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
	kind string = 'generation-admission'
	scenario string = 'packages-generation-admission'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-generation-admission', guest: 'tests/packages/generation-admission-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/generation_admission_test.v', path: 'usr/share/package-fixtures/generation-admission-core' },
			hwhost.Program{ source: 'tools/packages/pkgcore/distribution_test.v', path: 'usr/share/package-fixtures/generation-admission-lifecycle' },
		], scenarios: [hwhost.Scenario{ name: 'packages-generation-admission', arches: ['aarch64', 'x86_64'],
			about: 'complete generation admission, exclusive publication, activation and rollback recovery',
			required: [
				'HWTEST START packages-generation-admission',
				'GENERATION ADMISSION 90 prepared/staged/published/activate refusals preserve current state, history and outside data; no completion, clean unpublished stages, retained published failures and offline retry PASS',
				'GENERATION ADMISSION exclusive publication preserves raced destination and retries at a fresh identity PASS',
				'GENERATION ADMISSION rollback refuses four late changes without switching current; captured whitespace-compatible metadata retries PASS',
				'GENERATION ADMISSION 128 valid and refused scans of 64-level trees retire descriptors under a 32-descriptor limit PASS',
				'GENERATION PROCESS generation-admission-core PASS',
				'GENERATION PROCESS generation-admission-lifecycle PASS',
				'HWTEST PASS packages-generation-admission'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-generation-admission-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('generation-admission-core', root + 'generation-admission-core')!,
			artifact('generation-admission-lifecycle', root + 'generation-admission-lifecycle')!,
			artifact('serial-log', base + '/packages-generation-admission/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
