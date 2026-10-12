// SPDX-License-Identifier: GPL-2.0-or-later
// Build the production native sandbox and boot signed-package enforcement.
module main

import hwhost
import crypto.sha256
import json2
import os
import time

struct Artifact {
	role   string
	bytes  u64
	sha256 string
}

struct Receipt {
	format       int = 1
	architecture string
	completed_at i64
	platform     string = 'qemu'
	kind         string = 'native'
	sdk          int    = 1
	scenario     string = 'packages-enforced'
	artifacts    []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn invoke(command []string) ! {
	mut process := os.new_process(command[0])
	process.set_args(command[1..])
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('runtime staging failed (${code})') }
}

fn runtime_suite(sandbox string) hwhost.Suite {
	return hwhost.Suite{
		name:         'package-runtime'
		guest:        'tests/accounts/guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs:     [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
		]
		binaries:     [hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }]
		files:        [
			hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
			hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
			hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
		]
		directories:  ['run', 'home', 'var/log', 'tmp:1777']
		scenarios:    [hwhost.Scenario{
			name:     'packages-enforced'
			arches:   ['aarch64', 'x86_64']
			about:    'signed package launch through the production sandbox, using real kernel enforcement'
			required: ['HWTEST START packages-enforced', 'PACKAGE SESSION', 'PACKAGE ENFORCEMENT',
				'HWTEST PASS packages-enforced']
			ending:   .poweroff
			timeout:  180
		}]
	}
}

fn check() !int {
	args := os.args[1..]
	options := hwhost.parse_options(args)!
	if options.help || options.list {
		return hwhost.run_suite(runtime_suite(''), args, @FILE)
	}
	if !os.is_file(options.kernel) { return error('--kernel is not a file: ${options.kernel}') }
	repository := hwhost.find_root(@FILE)!
	work := os.temp_dir() + '/vinix-package-runtime-' + os.getpid().str()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	// Keep the boot input stable even if another session removes its worktree.
	kernel := os.join_path(work, 'kernel')
	os.cp(options.kernel, kernel)!
	invoke([repository + '/build-support/security-tools/stage', '--arch', options.arch, '--staging',
		work])!
	sandbox := work + '/usr/bin/vinix-sandbox'
	status := hwhost.run_suite(runtime_suite(sandbox), [...args, '--kernel', kernel], @FILE)
	if status == 0 && options.state_dir != '' {
		root := os.join_path(options.state_dir, 'guest', 'root')
		receipt := Receipt{
			architecture: options.arch
			completed_at: time.now().unix()
			artifacts:    [
				artifact('kernel', kernel)!,
				artifact('sandbox', sandbox)!,
				artifact('signed-native-payload', os.join_path(options.state_dir, 'guest', 'init'))!,
				artifact('package-service', os.join_path(root, 'usr/bin/vinix-package'))!,
				artifact('session-runner', os.join_path(root, 'usr/sbin/vinix-session'))!,
				artifact('serial-log', os.join_path(options.state_dir, 'packages-enforced', 'serial.log'))!,
			]
		}
		os.write_file(os.join_path(options.state_dir, 'qualification.json'), json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() {
	code := check() or {
		eprintln(err)
		exit(1)
	}
	exit(code)
}
