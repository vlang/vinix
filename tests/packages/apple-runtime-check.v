// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time
import tests.packages.applefixture

struct AppleArtifact { role string bytes u64 sha256 string }
struct AppleReceipt {
	format int = 1
	architecture string
	completed_at i64
	platform string = 'qemu-tcg'
	scenario string = 'packages-apple'
	coverage []string = ['Apple publisher profile and pinned catalog packing', 'explicit AArch64 composition with a dual-host shared catalog', 'Foundation container paths and file writes', 'Security generic-password CRUD and private persistence', 'signed package launch and maintenance']
	seconds f64
	artifacts []AppleArtifact
}

fn apple_artifact(role string, path string) !AppleArtifact {
	bytes := os.read_bytes(path)!
	return AppleArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn build_apple_runtime(host hwhost.Host, work string) !string {
	cc := os.find_abs_path_of_executable(os.getenv_opt('VINIX_MUSL_CC_AARCH64') or { 'aarch64-linux-musl-gcc' })!
	source := work + '/run-ios.c'
	hwhost.run_tool([host.v, '-nocache', '-os', 'linux', '-arch', 'arm64', '-enable-globals', '-gc', 'none', '-prod',
		'-d', 'glibc', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-path', '@vlib|' + host.root + '/compat/ios|@vmodules', '-o', source, host.root + '/compat/ios/runner'],
		{}, work + '/runtime-v.log', 300)!
	// Raw C output does not link V's optional helper objects. Retire unused
	// sections, including unused os shell-capture helpers, before resolution.
	hwhost.run_tool([cc, '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', '-ffixed-x18',
		'-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections', '-w', source,
		host.root + '/compat/ios/runner/abi/dispatch.S', '-o', work + '/run-ios', '-lm', '-lpthread'],
		{}, work + '/runtime-cc.log', 300)!
	return work + '/run-ios'
}

fn apple_suite(runtime string, sandbox string, repository string) !hwhost.Suite {
	return hwhost.Suite{
		name: 'package-apple-runtime', guest: 'tests/accounts/guest',
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring'],
		programs: [hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
			hwhost.Program{ source: 'tests/packages/apple-runtime-probe.v', path: 'usr/share/apple-fixtures/launcher' }],
		binaries: [hwhost.RootBinary{ source: runtime, path: 'usr/share/apple-fixtures/run-ios' },
			hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }],
		files: [hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
			hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
			hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
			hwhost.RootFile{ path: 'usr/share/apple-fixtures/hidden.txt', text: 'outside the signed closure' },
			hwhost.RootFile{ path: 'usr/share/apple-fixtures/COPYING', text: if repository == '' { '' } else { os.read_file(repository + '/LICENSE')! } },
			hwhost.RootFile{ path: 'usr/share/apple-fixtures/v-LICENSE', text: if repository == '' { '' } else {
				os.read_file(os.dir(os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!) + '/LICENSE')! } },
			hwhost.RootFile{ path: 'usr/share/apple-fixtures/musl-COPYRIGHT', text: if repository == '' { '' } else { os.read_file(repository + '/build-support/musl/COPYRIGHT')! } }],
		directories: ['run', 'home', 'var/log', 'tmp:1777'],
		scenarios: [hwhost.Scenario{ name: 'packages-apple', arches: ['aarch64'],
			about: 'signed ARM64 Mach-O execution in the production sandbox with private Apple containers',
			required: ['HWTEST START packages-apple',
				'PACKAGE APPLE PROFILE version=1.0.0 runtime=1.0.0 architecture=aarch64',
				'PACKAGE APPLE PROFILE version=1.1.0 runtime=1.1.0 architecture=aarch64',
				'PACKAGE APPLE COMPOSITION version=1.0.0 target=aarch64 shared-notice full-provenance unsupported-x86-refusal',
				'PACKAGE APPLE COMPOSITION version=1.1.0 target=aarch64 shared-notice full-provenance unsupported-x86-refusal',
				'PACKAGE APPLE signed Mach-O execution ordinary identities private containers literal document ambient overrides PASS',
				'PACKAGE APPLE reviewed update rollback runtime tamper refusal clean uninstall cached reinstall retained private data PASS',
				'PACKAGE APPLE Foundation home Documents temporary files keychain CRUD persistence entitlement damaged-store refusal PASS',
				'PACKAGE APPLE FRAMEWORK counter=1 paths files keychain PASS',
				'PACKAGE APPLE FRAMEWORK counter=2 paths files keychain PASS',
				'PACKAGE APPLE FRAMEWORK counter=3 paths files keychain PASS',
				'PACKAGE APPLE FRAMEWORK counter=4 paths files keychain PASS',
				'HWTEST PASS packages-apple'], forbidden: ['V panic:', 'HWTEST FAIL', 'pledge "'], ending: .poweroff, timeout: 300 }],
	}
}

fn check_apple() !int {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list { return hwhost.run_suite(apple_suite('', '', '')!, os.args[1..], @FILE) }
	if options.arch != 'aarch64' { return error('the current iOS runtime executes only on AArch64; no x86-64 translation runtime is supplied') }
	mut runtime := os.getenv('VINIX_APPLE_RUNTIME')
	sandbox := os.getenv('VINIX_APPLE_SANDBOX')
	if os.getenv('VINIX_HWTEST_TCG') != '1' || (runtime != '' && !os.is_file(runtime)) || !os.is_file(sandbox)
		|| !os.is_file(options.kernel) || options.state_dir == '' || os.exists(options.state_dir) || os.is_link(options.state_dir) {
		return error('provide VINIX_HWTEST_TCG=1, VINIX_APPLE_SANDBOX, --kernel and a new --state-dir; VINIX_APPLE_RUNTIME may select a prebuilt static runner')
	}
	repository := hwhost.find_root(@FILE)!
	host := hwhost.find_host(repository, options.arch, options.qemu)!
	hwhost.validate_scenarios(apple_suite('', '', '')!.scenarios)!
	selection := hwhost.select_scenarios(apple_suite('', '', '')!.scenarios, options.arch, options.scenarios)!
	if selection.run.len != 1 { return error('select packages-apple') }
	os.mkdir_all(options.state_dir)!
	work := os.real_path(options.state_dir)
	os.cp(options.kernel, work + '/kernel')!
	hwhost.watch_interrupts()
	if runtime == '' { runtime = build_apple_runtime(host, work)! }
	definition := apple_suite(runtime, sandbox, repository)!
	guest := hwhost.build_program(host, repository + '/' + definition.guest, work + '/guest', 'init', definition.module_paths)!
	root := hwhost.build_extras(host, definition, work + '/guest')!
	os.write_file_array(work + '/image-v1.macho', applefixture.framework_image(23))!
	os.write_file_array(work + '/image-v2.macho', applefixture.framework_image(24))!
	mut artifacts := []AppleArtifact{}
	for role, path in { 'kernel': work + '/kernel', 'guest-init': guest, 'package-service': root + '/usr/bin/vinix-package',
		'account-manager': root + '/usr/sbin/vinix-account', 'session-runner': root + '/usr/sbin/vinix-session',
		'run-ios': root + '/usr/share/apple-fixtures/run-ios', 'launcher': root + '/usr/share/apple-fixtures/launcher',
		'sandbox': root + '/usr/bin/vinix-sandbox', 'Mach-O-1': work + '/image-v1.macho', 'Mach-O-2': work + '/image-v2.macho' } {
		artifacts << apple_artifact(role, path)!
	}
	outcome := hwhost.run_scenario(host, selection.run[0], hwhost.Run{ kernel: work + '/kernel', guest: guest, extras: root,
		state: work + '/packages-apple', timeout: if options.timeout > 300 { options.timeout } else { 300 }, keep: true })
	println(hwhost.report(options.arch, outcome))
	if outcome.interrupted { return 130 }
	if !outcome.passed { return 1 }
	artifacts << apple_artifact('serial-log', work + '/packages-apple/serial.log')!
	os.write_file(work + '/qualification.json', json2.encode(AppleReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), seconds: outcome.seconds, artifacts: artifacts }) + '\n')!
	return 0
}

fn main() { exit(check_apple() or { eprintln(err); 2 }) }
