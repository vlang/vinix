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
	kind string = 'launch-process-lifecycle'
	scenario string = 'packages-launch-process'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-launch-process', guest: 'tests/packages/launch-process-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/launch_process_test.v', path: 'usr/share/package-fixtures/launch-process',
				flags: ['-manualfree', '-d', 'track_heap'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/coordination_test.v', path: 'usr/share/package-fixtures/coordination' },
			hwhost.Program{ source: 'tests/packages/launch-process-child.v', path: 'usr/share/package-fixtures/launch-child' },
			hwhost.Program{ source: 'tools/packages/pkgcore/session_test.v', path: 'usr/share/package-fixtures/session' },
			hwhost.Program{ source: 'tools/packages/pkgcore/command_test.v', path: 'usr/share/package-fixtures/command' },
		], scenarios: [hwhost.Scenario{ name: 'packages-launch-process', arches: ['aarch64', 'x86_64'],
			about: 'tracked synchronous execution as root and UID 1000 with literal arguments, status/streams/identity, launch diagnostics and generation-lease lifetime',
			required: ['HWTEST START packages-launch-process',
				'LAUNCH PROCESS literal empty/Unicode/shell-looking arguments, inherited environment, exact working directory and identity PASS',
				'LAUNCH PROCESS tracked exits: four modes, 1000 attempts each retained 0 bytes',
				'LAUNCH PROCESS normal and signal exits preserve 37/126/127/143 status, reap children and retire parent storage/descriptors PASS',
				'LAUNCH PROCESS tracked refusals: ten paths, 1000 attempts each retained 0 bytes',
				'LAUNCH PROCESS missing/non-directory cwd, missing/denied/invalid executable and malformed-plan diagnostics refuse before execution with retired scratch PASS',
				'LAUNCH PROCESS existing stdin/stdout/stderr stay separate and closed standard descriptors remain closed PASS',
				'LAUNCH PROCESS tracked descriptor exhaustion: 1000 refusals retained 0 bytes',
				'LAUNCH PROCESS parent retains its generation lease, final close releases it, descriptor exhaustion retires scratch and restoration permits retry PASS',
				'LAUNCH PROCESS ACTOR root PASS', 'LAUNCH PROCESS ACTOR UID 1000 PASS',
				'LAUNCH PROCESS COMPANION coordination PASS', 'LAUNCH PROCESS COMPANION session PASS', 'LAUNCH PROCESS COMPANION command PASS',
				'HWTEST PASS packages-launch-process'], ending: .poweroff, timeout: 1200 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-launch-process-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir; root := base + '/guest/root/usr/share/package-fixtures/'
		mut artifacts := [kernel, artifact('guest-init', base + '/guest/init')!]
		for name in ['launch-process', 'coordination', 'launch-child', 'session', 'command']! { artifacts << artifact(name, root + name)! }
		artifacts << artifact('serial-log', base + '/packages-launch-process/serial.log')!
		os.write_file(base + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: artifacts }) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
