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
	kind string = 'launch-plan-ownership'
	scenario string = 'packages-launch-ownership'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-launch-ownership', guest: 'tests/packages/launch-ownership-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/launch_ownership_test.v', path: 'usr/share/package-fixtures/launch-ownership' },
			hwhost.Program{ source: 'tools/packages/pkgcore/command_test.v', path: 'usr/share/package-fixtures/command' },
			hwhost.Program{ source: 'tools/packages/pkgcore/session_test.v', path: 'usr/share/package-fixtures/session' },
			hwhost.Program{ source: 'tools/packages/pkgcore/context_test.v', path: 'usr/share/package-fixtures/context' },
			hwhost.Program{ source: 'tools/packages/pkgcore/document_test.v', path: 'usr/share/package-fixtures/document' },
			hwhost.Program{ source: 'tools/packages/pkgcore/installed_namespace_test.v', path: 'usr/share/package-fixtures/namespace' },
			hwhost.Program{ source: 'tools/packages/pkgcore/registration_parent_test.v', path: 'usr/share/package-fixtures/registration' },
		], scenarios: [hwhost.Scenario{ name: 'packages-launch-ownership', arches: ['aarch64', 'x86_64'],
			about: 'owned sandbox/session launch plans, source retirement, unchanged grants/context and refusal before execution',
			required: ['HWTEST START packages-launch-ownership',
				'LAUNCH OWNERSHIP plans survive request/state/path/account and sibling retirement; repeated close resets all fields PASS',
				'LAUNCH OWNERSHIP both architectures and native/Linux/Windows/Apple plans preserve promises, environment, templates and literal tails PASS',
				'LAUNCH OWNERSHIP 0/1/64 dependencies, shared edges/cycles, 256 documents and 256 literal arguments retire vector growth PASS',
				'LAUNCH OWNERSHIP policy, revoked/weak publishers, SDK directories and regular-file/permission refusals retire partial plans PASS',
				'LAUNCH OWNERSHIP five isolated session modes and 0/1/64/256 documents release independent vectors PASS',
				'LAUNCH PROCESS launch-ownership PASS', 'LAUNCH PROCESS command PASS', 'LAUNCH PROCESS session PASS',
				'LAUNCH PROCESS context PASS', 'LAUNCH PROCESS document PASS', 'LAUNCH PROCESS namespace PASS', 'LAUNCH PROCESS registration PASS',
				'HWTEST PASS packages-launch-ownership'], ending: .poweroff, timeout: 240 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-launch-ownership-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir; root := base + '/guest/root/usr/share/package-fixtures/'
		mut artifacts := [kernel, artifact('guest-init', base + '/guest/init')!]
		for name in ['launch-ownership', 'command', 'session', 'context', 'document', 'namespace', 'registration']! {
			artifacts << artifact(name, root + name)!
		}
		artifacts << artifact('serial-log', base + '/packages-launch-ownership/serial.log')!
		os.write_file(base + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: artifacts }) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
