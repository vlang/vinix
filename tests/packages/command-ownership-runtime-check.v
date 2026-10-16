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
	kind string = 'command-request-ownership'
	scenario string = 'packages-command-ownership'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-command-ownership', guest: 'tests/packages/command-ownership-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/command_ownership_test.v', path: 'usr/share/package-fixtures/command-ownership' },
			hwhost.Program{ source: 'tools/packages/pkgcore/command_test.v', path: 'usr/share/package-fixtures/command' },
			hwhost.Program{ source: 'tools/packages/pkgcore/session_test.v', path: 'usr/share/package-fixtures/session' },
			hwhost.Program{ source: 'tools/packages/pkgcore/context_test.v', path: 'usr/share/package-fixtures/context' },
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tests/packages/command-ownership-cli.v', path: 'usr/share/package-fixtures/command-cli' },
		], scenarios: [hwhost.Scenario{ name: 'packages-command-ownership', arches: ['aarch64', 'x86_64'],
			about: 'owned bounded literal launch requests, reusable cleanup, unchanged session/sandbox/context arguments',
			required: ['HWTEST START packages-command-ownership',
				'COMMAND OWNERSHIP independent literal arguments/documents survive source and sibling retirement; repeated close resets both vectors and data-cwd PASS',
				'COMMAND OWNERSHIP repeated empty/one/64/256-document requests and twelve syntax/string/count/aggregate refusal paths retire all scratch PASS',
				'COMMAND OWNERSHIP exact 256 arguments/documents, 4096-byte values and 65535/65536/65537 aggregate bytes preserve limits and error precedence PASS',
				'COMMAND OWNERSHIP isolated transport borrows bounded prefixes, preserves literal source vectors and exact 772-value/document refusal diagnostics PASS',
				'COMMAND PROCESS command-ownership PASS', 'COMMAND PROCESS command PASS', 'COMMAND PROCESS session PASS', 'COMMAND PROCESS context PASS',
				'COMMAND CLI run-args/run-terminal-args preserve parser and outer admission diagnostics before session setup PASS', 'COMMAND PROCESS command-cli PASS',
				'HWTEST PASS packages-command-ownership'], ending: .poweroff, timeout: 180 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-command-ownership-' + os.getpid().str()
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir; root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('command-ownership', root + 'command-ownership')!,
			artifact('command', root + 'command')!, artifact('session', root + 'session')!, artifact('context', root + 'context')!,
			artifact('package-service', base + '/guest/root/usr/bin/vinix-package')!, artifact('command-cli', root + 'command-cli')!,
			artifact('serial-log', base + '/packages-command-ownership/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
