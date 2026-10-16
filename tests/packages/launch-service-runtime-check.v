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
	kind string = 'launch-service-lifecycle'
	scenario string = 'packages-launch-service'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-launch-service', guest: 'tests/packages/launch-service-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/launch_service_test.v', path: 'usr/share/package-fixtures/launch-service',
				flags: ['-manualfree', '-d', 'track_heap'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/coordination_test.v', path: 'usr/share/package-fixtures/coordination' },
			hwhost.Program{ source: 'tools/packages/pkgcore/state_schema_test.v', path: 'usr/share/package-fixtures/state-schema' },
			hwhost.Program{ source: 'tools/packages/pkgcore/session_test.v', path: 'usr/share/package-fixtures/session' },
			hwhost.Program{ source: 'tools/packages/pkgcore/command_test.v', path: 'usr/share/package-fixtures/command' },
		], scenarios: [hwhost.Scenario{ name: 'packages-launch-service', arches: ['aarch64', 'x86_64'],
			about: 'owned service configuration/state/lease lifetime with tracked root and ordinary-account launch refusals',
			required: ['HWTEST START packages-launch-service',
				'LAUNCH SERVICE tracked preparation: 1000 small and 16 large cycles per architecture retained 0 bytes',
				'LAUNCH SERVICE both architectures, independent 1/64-entry snapshots, offline overlay, reusable close, reader release and exact generation lease lifetime PASS',
				'LAUNCH SERVICE executable identity owns independent paths and retires lookup scratch PASS',
				'LAUNCH SERVICE tracked preparation refusals: 1000 attempts per path retained 0 bytes',
				'LAUNCH SERVICE root/lock/config/state/ID and missing/FIFO/hard-linked/busy lease refusals retire scratch, preserve files and permit retry PASS',
				'LAUNCH SERVICE tracked root: five modes, 1000 refusals each retained 0 bytes',
				'LAUNCH SERVICE tracked UID 1000: five modes, 1000 refusals each retained 0 bytes',
				'LAUNCH SERVICE real-root root and UID 1000 runners retire all five launch modes before session/data creation or execution PASS',
				'LAUNCH SERVICE PROCESS launch-service PASS', 'LAUNCH SERVICE PROCESS coordination PASS', 'LAUNCH SERVICE PROCESS state-schema PASS',
				'LAUNCH SERVICE PROCESS session PASS', 'LAUNCH SERVICE PROCESS command PASS',
				'HWTEST PASS packages-launch-service'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-launch-service-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir; root := base + '/guest/root/usr/share/package-fixtures/'
		mut artifacts := [kernel, artifact('guest-init', base + '/guest/init')!]
		for name in ['launch-service', 'coordination', 'state-schema', 'session', 'command']! { artifacts << artifact(name, root + name)! }
		artifacts << artifact('serial-log', base + '/packages-launch-service/serial.log')!
		os.write_file(base + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: artifacts }) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
