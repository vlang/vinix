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
	kind string = 'publisher-input'
	scenario string = 'packages-publisher-workspace'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{
		name: 'package-publisher-workspace'
		guest: 'tests/packages/publisher-workspace-guest'
		module_paths: ['.', 'tools/accounts']
		programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/publisher_workspace_test.v', path: 'usr/share/package-fixtures/publisher-workspace-core' },
		]
		directories: ['tmp:1777']
		scenarios: [hwhost.Scenario{
			name: 'packages-publisher-workspace'
			arches: ['aarch64', 'x86_64']
			about: 'publisher exclusion, source/output separation, safe workspace admission and interrupted-writer recovery'
			required: ['HWTEST START packages-publisher-workspace', 'PACKAGE PUBLISHER WORKSPACE common-lock confined-output safe-admission recovery PASS',
				'PUBLISHER WORKSPACE CASE writers PASS', 'PUBLISHER WORKSPACE CASE admission PASS',
				'PUBLISHER WORKSPACE CASE containment PASS', 'PUBLISHER WORKSPACE CASE entries PASS',
				'PUBLISHER WORKSPACE CASE retirement PASS',
				'HWTEST PASS packages-publisher-workspace']
			ending: .poweroff
			// Full mutation/retry and descriptor-retirement matrix under TCG.
			timeout: 300
		}]
	}
}

fn check() !int {
	args := os.args[1..]
	options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-publisher-workspace-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [
			kernel, artifact('guest-init', base + '/guest/init')!,
			artifact('publisher-workspace-core', root + 'publisher-workspace-core')!,
			artifact('serial-log', base + '/packages-publisher-workspace/serial.log')!,
		] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
