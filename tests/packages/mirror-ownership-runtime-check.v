// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact { role string bytes u64 sha256 string }
struct Receipt { format int = 1 architecture string completed_at i64 scenario string = 'packages-mirror-ownership' artifacts []Artifact }

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-mirror-ownership', guest: 'tests/packages/mirror-ownership-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/mirror_ownership_test.v', path: 'usr/share/package-fixtures/mirror-ownership', flags: ['-d', 'track_heap'] },
			hwhost.Program{ source: 'tools/packages/pkgcore/mirror_test.v', path: 'usr/share/package-fixtures/mirror' },
			hwhost.Program{ source: 'tools/packages/pkgcore/deployment_test.v', path: 'usr/share/package-fixtures/deployment' },
			hwhost.Program{ source: 'tools/packages/pkgcore/release_test.v', path: 'usr/share/package-fixtures/release' },
		], scenarios: [hwhost.Scenario{ name: 'packages-mirror-ownership', arches: ['aarch64', 'x86_64'],
			about: 'mirror preparation/review ownership, fingerprint compatibility and signed ordinary/locked offline publication and installation',
			required: ['HWTEST START packages-mirror-ownership',
				'MIRROR OWNERSHIP preflight: 1000 path cycles retained 0 bytes; 1000 space cycles retained 0 bytes; 1000 warmed prepared metadata cycles retained 0 bytes',
				'MIRROR OWNERSHIP 1000 independent review build/retirement cycles retained 0 bytes',
				'MIRROR OWNERSHIP 2000 filesystem/overflow failure cycles retained 0 bytes',
				'MIRROR OWNERSHIP review fields survive prepared retirement, repeated close and intact borrowed manifests PASS',
				'MIRROR OWNERSHIP occupied/special/unsafe paths, malformed metadata, filesystem and overflow failures preserve inputs, retire scratch and permit retry PASS',
				'MIRROR OWNERSHIP physical aliases, selected/revoked snapshot lifetimes and byte-identical ordinary/deployment review fingerprints PASS',
				'MIRROR OWNERSHIP PROCESS mirror-ownership PASS', 'MIRROR OWNERSHIP PROCESS mirror PASS',
				'MIRROR OWNERSHIP PROCESS deployment PASS', 'MIRROR OWNERSHIP PROCESS release PASS',
				'HWTEST PASS packages-mirror-ownership'], forbidden: ['V panic:', 'HWTEST FAIL'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) || os.getenv('VINIX_HWTEST_TCG') != '1' {
		return error('provide VINIX_HWTEST_TCG=1, --kernel and a new --state-dir')
	}
	work := os.temp_dir() + '/vinix-mirror-ownership-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 {
		base := options.state_dir; root := base + '/guest/root/usr/share/package-fixtures/'
		mut artifacts := [kernel, artifact('guest-init', base + '/guest/init')!]
		for name in ['mirror-ownership', 'mirror', 'deployment', 'release']! { artifacts << artifact(name, root + name)! }
		artifacts << artifact('serial-log', base + '/packages-mirror-ownership/serial.log')!
		os.write_file(base + '/qualification.json', json2.encode(Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: artifacts }) + '\n')!
	}
	return status
}

fn main() { exit(check() or { eprintln(err); 2 }) }
