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
	kind string = 'stage-recovery'
	scenario string = 'packages-stage-recovery'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-stage-recovery', guest: 'tests/packages/stage-recovery-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/stage_recovery_test.v', path: 'usr/share/package-fixtures/stage-recovery-core' },
			hwhost.Program{ source: 'tools/packages/pkgcore/distribution_test.v', path: 'usr/share/package-fixtures/stage-recovery-lifecycle' },
		], scenarios: [hwhost.Scenario{ name: 'packages-stage-recovery', arches: ['aarch64', 'x86_64'],
			about: 'safe abandoned-stage retirement and interrupted transaction cleanup',
			required: [
				'HWTEST START packages-stage-recovery',
				'STAGE RECOVERY 12 malformed-root transaction/collection refusals preserve all stages, generations, cache and outside data; restored roots retry PASS',
				'STAGE RECOVERY five changed captured roots preserve original and replacement identities; restored inode retires PASS',
				'STAGE RECOVERY ten replaced nested/ancestor directories refuse without traversing aliases or deleting saved/replacement data; restored trees retire PASS',
				'STAGE RECOVERY ten in-flight prepared/staged replacements preserve saved stages and outside data; restored originals retry PASS',
				'STAGE RECOVERY incomplete 64-level tree and 128 mixed-tree retirements/refusals keep descriptors below 32 without traversing aliases or opening FIFOs PASS',
				'STAGE RECOVERY 1024 long-name files spanning directory buffers retire completely in one recovery pass PASS',
				'STAGE PROCESS stage-recovery-core PASS',
				'STAGE PROCESS stage-recovery-lifecycle PASS',
				'HWTEST PASS packages-stage-recovery'], ending: .poweroff, timeout: 600 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-stage-recovery-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('stage-recovery-core', root + 'stage-recovery-core')!,
			artifact('stage-recovery-lifecycle', root + 'stage-recovery-lifecycle')!,
			artifact('serial-log', base + '/packages-stage-recovery/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
