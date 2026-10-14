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
	kind string = 'cache-promotion'
	scenario string = 'packages-cache-promotion'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-cache-promotion', guest: 'tests/packages/cache-promotion-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/cache_promotion_test.v', path: 'usr/share/package-fixtures/cache-promotion-core' },
			hwhost.Program{ source: 'tests/packages/cache-promotion-check.v', path: 'usr/share/package-fixtures/cache-promotion-probe' },
		], scenarios: [hwhost.Scenario{ name: 'packages-cache-promotion', arches: ['aarch64', 'x86_64'],
			about: 'captured cache promotion, hard-link recovery refusal and ordinary offline retry',
			required: ['HWTEST START packages-cache-promotion',
				'CACHE PROMOTION captured partial/parent, link/replacement/FIFO/content refusal and atomic destination-link replacement PASS',
				'CACHE PROMOTION signed reviewed recovery, hard-link refusal, preserved outside metadata and ordinary cache/rollback PASS',
				'CACHE PROMOTION signed hash/length, captured flush EINTR/EIO, published-cache diagnostics and 128 cycles under 32 descriptors PASS',
				'CACHE PROCESS cache-promotion-core PASS', 'CACHE PROCESS cache-promotion-probe PASS',
				'HWTEST PASS packages-cache-promotion'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-cache-promotion-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('cache-promotion-core', root + 'cache-promotion-core')!,
			artifact('cache-promotion-probe', root + 'cache-promotion-probe')!,
			artifact('serial-log', base + '/packages-cache-promotion/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
