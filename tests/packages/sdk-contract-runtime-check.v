// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct SdkSource { path string sha256 string }
struct SdkArtifact { role string bytes u64 sha256 string }
struct SdkReceipt {
	format int = 1
	kind string = 'sdk-contract'
	scenario string = 'packages-sdk-contract'
	architecture string
	fixture_architecture string = 'aarch64'
	completed_at i64
	source_revision string
	sources []SdkSource
	artifacts []SdkArtifact
	toolchain_limit string = 'Repository sources, controller, V executable and executed artifacts are pinned. Imported vlib/thirdparty, headers, sysroots, linker, firmware and transitive build tools are not frozen; this is not a hermetic or reproducible-build qualification.'
}

fn sdk_hash(path string) !string {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return sha256.sum(bytes).hex()
}

fn sdk_command(arguments []string, directory string) !string {
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..]); child.set_work_folder(directory)
	child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait()
	if child.code != 0 { return error(output) }
	return output
}

fn sdk_sources(root string) ![]SdkSource {
	text := sdk_command(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--',
		'tools/packages', 'tools/accounts/authclient', 'tools/accounts/authproto', 'compat/ios/plist',
		'build-support/build-amd64-iso.sh', 'build-support/limine-binary.sh', 'build-support/limine.conf',
		'tests/hardware-platform/hwhost', 'tests/packages/sdk-contract-runtime-check.v',
		'tests/packages/sdk-contract-guest', 'tests/packages/capabilities-check.v',
		'tests/packages/deployment-writer-check.v', 'tests/packages/repository-url-check.v',
		'tests/packages/policy-writer-check.v'], root)!
	defer { unsafe { text.free() } }
	mut paths := text.split('\x00').filter(it != '' && (it.ends_with('.v') || it.ends_with('.h') || it.ends_with('.c') || it.ends_with('.sh') || it.ends_with('.conf')))
	defer { unsafe { paths.free() } }
	paths.sort()
	mut sources := []SdkSource{cap: paths.len}
	for path in paths { sources << SdkSource{ path: path.clone(), sha256: sdk_hash(root + '/' + path)! } }
	return sources
}

fn sdk_artifact(role string, path string, architecture string) !SdkArtifact {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	if architecture != '' {
		machine := if architecture == 'aarch64' { 183 } else { 62 }
		if bytes.len < 20 || bytes[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
			|| int(bytes[18]) + (int(bytes[19]) << 8) != machine {
			return error(role + ': wrong native ELF architecture')
		}
	}
	return SdkArtifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn sdk_markers(architecture string) []string {
	return ['HWTEST START packages-sdk-contract',
		'PACKAGE CAPABILITIES real CLI no-config exact-version discovery, eight argument refusals and unchanged private state PASS',
		'DEPLOYMENT WRITER real CLI accepts formats 1/2, refuses five semantic/catalog cases, preserves package tree PASS',
		'REPOSITORY URL actual CLI 48 literal controls, 88 malformed refusals, 2 missing/corrupt controls; fresh/existing roots unchanged PASS',
		'POLICY WRITER real CLI accepts complete/empty/arbitrary-order policies, canonical fingerprint agrees, refuses 8 semantic cases, preserves state PASS',
		'SDK CONTRACT PROCESS capabilities PASS', 'SDK CONTRACT PROCESS deployment-writer PASS',
		'SDK CONTRACT PROCESS repository-url PASS', 'SDK CONTRACT PROCESS policy-writer PASS',
		'SDK CONTRACT arity 45 early refusals and 9 valid controls preserve missing/corrupt/valid fixture trees PASS',
		'SDK CONTRACT native ' + architecture + ' executes configured aarch64 document fixtures PASS',
		'HWTEST PASS packages-sdk-contract']
}

fn sdk_staged(role string, built string, staged string, architecture string) !SdkArtifact {
	artifact := sdk_artifact(role, staged, architecture)!
	if sdk_hash(built)! != artifact.sha256 { return error(role + ': staged executable differs from build output') }
	return artifact
}

fn sdk_suite(architecture string) hwhost.Suite {
	return hwhost.Suite{ name: 'package-sdk-contract', guest: 'tests/packages/sdk-contract-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package', flags: ['-prod', '-manualfree'] },
			hwhost.Program{ source: 'tests/packages/capabilities-check.v', path: 'usr/share/package-fixtures/capabilities', flags: ['-prod', '-manualfree'] },
			hwhost.Program{ source: 'tests/packages/deployment-writer-check.v', path: 'usr/share/package-fixtures/deployment-writer', flags: ['-prod', '-manualfree'] },
			hwhost.Program{ source: 'tests/packages/repository-url-check.v', path: 'usr/share/package-fixtures/repository-url', flags: ['-prod', '-manualfree'] },
			hwhost.Program{ source: 'tests/packages/policy-writer-check.v', path: 'usr/share/package-fixtures/policy-writer', flags: ['-prod', '-manualfree'] },
		], scenarios: [hwhost.Scenario{ name: 'packages-sdk-contract', arches: ['aarch64', 'x86_64'],
			about: 'native production CLI/public SDK consumers, exact document reviews and early read-only operand refusals',
			required: sdk_markers(architecture), ending: .poweroff, timeout: 600 }]
	}
}

fn sdk_check() !int {
	if sdk_hash(@FILE)! != sha256.hexhash($embed_file('sdk-contract-runtime-check.v').to_string()) {
		return error('controller source differs from executable')
	}
	args := os.args[1..]
	options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(sdk_suite(options.arch), args, @FILE) }
	if options.state_dir == '' || options.failures_only { return error('provide a fresh --state-dir and retain passing artifacts') }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, options.arch, options.qemu)!
	sources := sdk_sources(root)!
	revision := sdk_command(['git', 'rev-parse', 'HEAD'], root)!
	compiler := sdk_artifact('v-compiler', host.v, '')!
	controller := sdk_artifact('host-controller', os.executable(), '')!
	work := os.temp_dir() + '/vinix-sdk-contract-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := sdk_artifact('kernel', work + '/kernel', options.arch)!
	status := hwhost.run_suite(sdk_suite(options.arch), [...args, '--kernel', work + '/kernel'], @FILE)
	if sdk_sources(root)! != sources || sdk_command(['git', 'rev-parse', 'HEAD'], root)! != revision
		|| sdk_artifact('v-compiler', host.v, '')! != compiler
		|| sdk_artifact('host-controller', os.executable(), '')! != controller {
		return error('qualification repository source closure, revision or executable changed during checks')
	}
	if status != 0 { return status }
	if sdk_artifact('kernel', work + '/kernel', options.arch)! != kernel {
		return error('copied kernel changed during qualification')
	}
	base := os.abs_path(options.state_dir)
	scenario := base + '/packages-sdk-contract'
	serial := scenario + '/serial.log'
	lines := os.read_file(serial)!.split_into_lines()
	for marker in sdk_markers(options.arch) {
		if lines.filter(it == marker).len != 1 { return error('missing or duplicate exact serial marker: ' + marker) }
	}
	medium := scenario + if options.arch == 'aarch64' { '/boot.img' } else { '/test.iso' }
	// Check the kernel copied into the retained medium, not only its input.
	if options.arch == 'aarch64' {
		sdk_command(['mcopy', '-o', '-i', medium, '::/boot/vinix', work + '/boot-kernel'], root)!
	} else {
		sdk_command(['xorriso', '-osirrox', 'on', '-indev', medium, '-extract', '/boot/vinix', work + '/boot-kernel'], root)!
	}
	boot_kernel := sdk_artifact('boot-kernel', work + '/boot-kernel', options.arch)!
	if boot_kernel.sha256 != kernel.sha256 { return error('boot medium kernel differs from pinned input') }
	fixture := '/usr/share/package-fixtures/'
	mut artifacts := [kernel, compiler, controller,
		boot_kernel, sdk_artifact('boot-medium', medium, '')!,
		sdk_artifact('initramfs', scenario + '/initramfs.tar', '')!,
		sdk_staged('guest-init', base + '/guest/init', scenario + '/rootfs/sbin/init', options.arch)!,
		sdk_staged('package-cli', base + '/guest/root/usr/bin/vinix-package', scenario + '/rootfs/usr/bin/vinix-package', options.arch)!,
		sdk_artifact('serial-log', serial, '')!]
	for name in ['capabilities', 'deployment-writer', 'repository-url', 'policy-writer'] {
		artifacts << sdk_staged(name, base + '/guest/root' + fixture + name,
			scenario + '/rootfs' + fixture + name, options.arch)!
	}
	os.write_file(base + '/sources.json', json2.encode(sources) + '\n')!
	artifacts << sdk_artifact('source-inventory', base + '/sources.json', '')!
	os.write_file(base + '/qualification.json', json2.encode(SdkReceipt{ architecture: options.arch,
		completed_at: time.now().unix(), source_revision: revision.trim_space(), sources: sources, artifacts: artifacts }) + '\n')!
	println('SDK CONTRACT repository source closure unchanged and native artifacts pinned PASS')
	return 0
}

fn main() { code := sdk_check() or { eprintln(err); exit(1) }; exit(code) }
