// SPDX-License-Identifier: GPL-2.0-or-later
// Collect observed command logs and narrow input/output identities; this is
// not a complete compiler/sysroot provenance or independent native retainer.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return sha256.hexhash(unsafe { tos(bytes.data, bytes.len) })
}

fn main() {
	if os.args.len != 5 { panic('ROOT BUILD_WORK NATIVE_RUN NEW_OUTPUT') }
	root := os.real_path(os.args[1])
	build := os.real_path(os.args[2])
	native := os.real_path(os.args[3])
	output := os.abs_path(os.args[4])
	if os.exists(output) || os.is_link(output) { panic('output must be new') }
	os.mkdir(output) or { panic(err) }
	mut sources := map[string]json2.Any{}
	for name in ['build-support/init-aarch64/initcore/core.v', 'build-support/init-amd64/desktop-init',
		'tools/accounts/session.v', 'tools/accounts/sessioncore/become.v',
		'tools/accounts/sessioncore/launch.v', 'tools/accounts/sessioncore/manager.v',
		'tools/accounts/sessioncore/graphical.v', 'tests/graphical-login/exec-check.v',
		'tests/graphical-login/exec-fixture.v.txt', 'tests/graphical-login/secret-check.v',
		'tests/graphical-login/secret-fixture.v.txt', 'tests/init-policy/guestfixture/core.v',
		'tests/init-policy/raw-module-check.v', 'tests/native-guest-tools/guesthost/init_policy.v'] {
		sources[name] = digest(root + '/' + name) or { panic(err) }
	}
	mut logs := map[string]json2.Any{}
	for name in ['exec-sanitize.log', 'exec-negative.log', 'manager-sanitize.log',
		'reference-refusal.log', 'native-init-policy.log'] {
		os.cp(build + '/' + name, output + '/' + name) or { panic(err) }
		logs[name] = digest(output + '/' + name) or { panic(err) }
	}
	mut captured := map[string]json2.Any{}
	for name in ['session-aarch64', 'session-aarch64.c', 'session-x86_64', 'session-x86_64.c',
		'clang-driver.v'] {
		captured[build + '/' + name] = digest(build + '/' + name) or { panic(err) }
	}
	for policy in ['shell', 'full', 'desktop'] {
		os.cp(native + '/' + policy + '/serial.log', output + '/' + policy + '-serial.log') or { panic(err) }
		logs[policy + '-serial.log'] = digest(output + '/' + policy + '-serial.log') or { panic(err) }
		for name in ['test.iso', 'limine.conf'] {
			path := native + '/' + policy + '/' + if name == 'limine.conf' {
				'iso-root/boot/limine.conf'
			} else {
				name
			}
			captured[path] = digest(path) or { panic(err) }
		}
	}
	v := os.getenv('VEXE')
	report := {
		'scope':                   json2.Any('Observed exit-0 host tests and ARM current-init stand-in guests. Assertions enabled (no -prod). Cross-compiled session outputs only; no new graphical login, GPU-native, installed-root or complete toolchain provenance claim.')
		'commands':                json2.Any({
			'exec':      json2.Any('exec-check --sanitize')
			'negative':  json2.Any('exec-check --negative-no-fallback (disabled recovery must fail)')
			'manager':   json2.Any('secret-check --sanitize')
			'native':    json2.Any('raw-init-policy /tmp/vinix-init-manager-policy-build /Users/alex/code/vinix/build/package-software-persistence-work/kernel-arm/kernel /tmp/vinix-init-manager-policy-raw-4')
			'reference': json2.Any('init-policy --kernel-dir /nonexistent --state-dir /tmp/vinix-init-reference-must-not-exist --reference-guest /nonexistent; exit2 and state absent')
		})
		'source_sha256':           json2.Any(sources)
		'logs_sha256':             json2.Any(logs)
		'captured_outputs_sha256': json2.Any(captured)
		'compiler_path':           json2.Any(v)
		'compiler_sha256':         json2.Any(digest(v) or { panic(err) })
	}
	os.write_file(output + '/checks.json', json2.encode(report) + '\n') or { panic(err) }
}
