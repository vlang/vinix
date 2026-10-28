// SPDX-License-Identifier: GPL-2.0-or-later
// Seal/check host-only account handoff tests. No ART or sign-in claim.
module main

import crypto.sha256
import json2
import os

struct Limits {
	rss u64
	wall_ms i64
	reserve u64
}

struct GuardReceipt {
	argv []string
	limits Limits
	exit_code int
	child_exit_code int
	reason string
	cleanup_complete bool
	peak_sampled_rss_bytes u64
}

fn file_hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn verify_results(root string) ! {
	for name in ['parser', 'broker'] {
		for action in ['build', 'run'] {
			label := name + '-' + action + '-r2'
			receipt := json2.decode[GuardReceipt](os.read_file(root + '/' + label + '.guard.json')!)!
			assert receipt.exit_code == 0 && receipt.child_exit_code == 0
				&& receipt.reason == '' && receipt.cleanup_complete
			assert receipt.limits.rss <= 600 * u64(1024 * 1024)
				&& receipt.peak_sampled_rss_bytes <= receipt.limits.rss
				&& receipt.limits.reserve >= 1024 * u64(1024 * 1024)
				&& receipt.limits.wall_ms <= 300000
			assert receipt.argv.len >= 3 && receipt.argv[..2] == ['/usr/bin/time', '-l']
			expected := if action == 'build' {
				if name == 'parser' { 'build-support/android/accounthandoff/diagnostics_test.v' }
				else { 'build-support/android/accountbroker/interaction_test.v' }
			} else { root + '/tools/' + name + '-test-r2' }
			assert receipt.argv.last() == expected
			mut measured := false
			for line in os.read_file(root + '/' + label + '.log')!.split_into_lines() {
				fields := line.fields()
				if fields.len == 2 && fields[1] == 'swaps' {
					assert fields[0] == '0'
					measured = true
				}
			}
			assert measured
		}
	}
}

fn main() {
	assert os.args.len == 3 && os.args[1] in ['seal', 'check'],
		'usage: check-account-handoff seal|check EXTERNAL_DIR'
	root := os.real_path(os.args[2])
	repo := os.real_path(os.getwd())
	assert os.is_dir(root) && root != repo && !root.starts_with(repo + '/')
	manifest := root + '/sha256.json'
	if os.args[1] == 'seal' {
		assert !os.exists(manifest) && !os.exists(root + '/frozen')
		verify_results(root)!
		for name in ['accountbroker', 'accountipc', 'accountinteraction', 'accountuifd',
			'nativeaccountauth', 'accounthandoff'] {
			for path in os.walk_ext('build-support/android/' + name, '.v') {
				out := root + '/frozen/' + path
				os.mkdir_all(os.dir(out))!
				os.write_file(out, os.read_file(path)!)!
			}
		}
		os.write_file(root + '/checker.v.input', os.read_file(@FILE)!)!
		revision := os.exec(['git', 'rev-parse', 'HEAD'])
		assert revision.exit_code == 0
		build := json2.decode[GuardReceipt](os.read_file(root + '/broker-build-r2.guard.json')!)!
		os.write_file(root + '/evidence.json', json2.encode({
			'scope': 'Host-only finite numeric schema and real broker offer/redemption/result tests. Native UI stages are source-reviewed only; no ART, UI or authentication claim.'
			'source_revision': revision.output.trim_space()
			'compiler': build.argv[2]
			'compiler_sha256': file_hash(build.argv[2])!
			'checker_sha256': file_hash(@FILE)!
		}, prettify: true))!
		mut inventory := map[string]string{}
		for path in os.walk_ext(root, '') {
			if os.is_file(path) { inventory[path[root.len + 1..]] = file_hash(path)! }
		}
		os.write_file(manifest, json2.encode(inventory, prettify: true))!
	}
	inventory := json2.decode[map[string]string](os.read_file(manifest)!)!
	mut count := 0
	for path in os.walk_ext(root, '') {
		if !os.is_file(path) || path == manifest { continue }
		relative := path[root.len + 1..]
		assert !os.is_link(path) && relative in inventory && inventory[relative] == file_hash(path)!
		count++
	}
	assert count == inventory.len
	verify_results(root)!
	println('ACCOUNT-HANDOFF-CHECK-PASS files=${count} manifest=' + file_hash(manifest)!)
}
