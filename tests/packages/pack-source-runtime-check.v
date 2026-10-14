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
	scenario string = 'packages-pack-source'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{
		name: 'package-pack-source'
		guest: 'tests/packages/pack-source-guest'
		module_paths: ['.', 'tools/accounts']
		programs: [
			hwhost.Program{ source: 'tests/packages/pack-source-check.v', path: 'usr/share/package-fixtures/pack-source-check' },
			hwhost.Program{ source: 'tools/packages/pkgcore/pack_source_test.v', path: 'usr/share/package-fixtures/pack-source-core' },
		]
		directories: ['tmp:1777']
		scenarios: [hwhost.Scenario{
			name: 'packages-pack-source'
			arches: ['aarch64', 'x86_64']
			about: 'captured package source traversal, bounded work, identity/mode checks and canonical metadata'
			required: ['HWTEST START packages-pack-source', 'Pack source qualification passed',
				'PACKAGE PACK SOURCE captured-tree bounded-work checked-mode canonical-retry PASS',
				'HWTEST PASS packages-pack-source']
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
	work := os.temp_dir() + '/vinix-pack-source-' + os.getpid().str()
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
			artifact('pack-source-check', root + 'pack-source-check')!,
			artifact('pack-source-core', root + 'pack-source-core')!,
			artifact('serial-log', base + '/packages-pack-source/serial.log')!,
		] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
