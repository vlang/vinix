// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import json2
import os

struct Pin {
	path   string
	sha256 string
}

struct Job {
	id               string = 'fixture'
	executable       Pin
	arguments        []string
	directory        string            = '/home/developer'
	interval_seconds int               = 3600
	timeout_seconds  int               = 10
	environment      map[string]string = {
		'VINIX_DEVELOPMENT_PAYLOAD': '1'
	}
	credential_files map[string]string
}

struct Plan {
	schema int = 1
	uid    int = 1000
	jobs   []Job
}

struct Stage {
	schema       int
	architecture string
	complete     bool
	binaries     map[string]string
}

struct BuildStep {
	name      string   = 'payload'
	argv      []string = ['{payload}']
	directory string   = '.'
	artifacts []string = ['artifact.txt']
}

struct BuildPlan {
	schema          int = 1
	source          Pin
	tools           map[string]Pin
	epoch           i64               = 1700000000
	timeout_seconds int               = 10
	environment     map[string]string = {
		'VINIX_DEVELOPMENT_PAYLOAD': 'build'
	}
	steps           []BuildStep = [BuildStep{}]
}

struct NativeStep {
	exit_code int
	artifacts map[string]string
}

struct NativeBuild {
	complete bool
	uid      int
	kernel   string
	epoch    i64
	steps    []NativeStep
}

struct Receipt {
	schema          int = 1
	arch            string
	uid             int = 1000
	kernel_sha256   string
	fixture_sha256  string
	tools           map[string]string
	command         []string
	native_receipts map[string]string
	passed          bool
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn run() !int {
	if os.args.len != 5 {
		return error('usage: run-guest aarch64|x86_64 KERNEL-DIR STAGED-TOOLS NEW-STATE')
	}
	arch := os.args[1]
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	kernel := os.real_path(os.args[2])
	stage := os.real_path(os.args[3])
	state := os.abs_path(os.args[4])
	if os.exists(state) { return error('state directory must be new') }
	manifest := json2.decode[Stage](os.read_file(stage + '/development-tools.json')!, strict: true)!
	if manifest.schema != 1 || !manifest.complete || manifest.architecture != arch {
		return error('incomplete or wrong-architecture tools')
	}
	os.mkdir_all(state)!
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(kernel + '/bin/vinix', state + '/kernel/bin/vinix')!
	init := guesthost.compile_init(guesthost.root() + '/tests/development/guestfixture/core.v', state, arch, false)!
	root := state + '/rootfs'
	os.mkdir_all(root + '/usr/bin')!
	os.mkdir_all(root + '/home/developer')!
	mut hashes := map[string]string{}
	for tool in ['vinix-build', 'vinix-qualify', 'vinix-vm', 'vinix-jobs'] {
		binary := stage + '/usr/bin/' + tool
		hash := digest(binary)!
		if manifest.binaries[tool] != hash { return error('staged tool changed: ' + tool) }
		header := os.read_bytes(binary)!
		machine := if header.len >= 20 { u16(header[18]) | (u16(header[19]) << 8) } else { u16(0) }
		if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' {
			u16(183)
		} else {
			u16(62)
		} {
			return error('wrong ELF tool: ' + tool)
		}
		os.cp(binary, root + '/usr/bin/' + tool)!
		os.chmod(root + '/usr/bin/' + tool, 0o755)!
		hashes[tool] = hash
	}
	os.cp(init, root + '/usr/bin/development-payload')!
	os.chmod(root + '/usr/bin/development-payload', 0o755)!
	for name in ['jobs', 'link-jobs'] {
		plan := Plan{
			jobs: [Job{
				executable:       Pin{'/usr/bin/development-payload', digest(init)!}
				credential_files: {
					'TEST_TOKEN': '/home/developer/' + if name == 'jobs' {
						'token'
					} else {
						'token-link'
					}
				}
			}]
		}
		os.write_file(root + '/home/developer/' + name + '.json', json2.encode(plan))!
	}
	os.write_file(root + '/home/developer/token', 'vinix-native-fixture-secret')!
	os.mkdir_all(root + '/home/developer/source')!
	os.write_file(root + '/home/developer/source/input.txt', 'build-fixture-input\n')!
	os.write_file(root + '/home/developer/build-template.json', json2.encode(BuildPlan{
		source: Pin{'/home/developer/source', '%s'}
		tools:  {
			'payload': Pin{'/usr/bin/development-payload', digest(init)!}
		}
	}))!
	archive := guesthost.image(init, state)!
	launch := guesthost.launch(init, archive, state, state + '/kernel', arch, true)!
	result := guesthost.boot(launch.command, launch.env, state, [
		'DEVELOPMENT ACCOUNT PASS:',
		'DEVELOPMENT BUILD PASS:',
		'DEVELOPMENT GUEST PASS',
	],
		['DEVELOPMENT GUEST FAIL', 'KERNEL PANIC', 'vinix-native-fixture-secret'], 180, true)!
	mut receipts := map[string]string{}
	for line in os.read_lines(state + '/serial.log')! {
		if !line.starts_with('DEVELOPMENT RECEIPT ') { continue }
		entry := line.all_after('DEVELOPMENT RECEIPT ').trim_space()
		path := entry.all_before(' ')
		body := entry.all_after(' ')
		if path !in ['/home/developer/good/state.json', '/home/developer/good/plan.json',
			'/home/developer/public-token/state.json', '/home/developer/link-token/state.json',
			'/home/developer/build-a/receipt.json', '/home/developer/build-b/receipt.json'] {
			return error('unexpected guest receipt path')
		}
		json2.decode[json2.Any](body)!
		receipts[path] = body
	}
	if result == 0 && receipts.len != 6 { return error('missing native workflow receipts') }
	if result == 0 {
		expected := sha256.sum('build-fixture-input\n'.bytes()).hex()
		for name in ['build-a', 'build-b'] {
			receipt := json2.decode[NativeBuild](receipts['/home/developer/' + name + '/receipt.json'],
				strict: true
			)!
			if !receipt.complete || receipt.uid != 1000 || receipt.kernel != 'Vinix'
				|| receipt.epoch != 1700000000 || receipt.steps.len != 1
				|| receipt.steps[0].exit_code != 0 || receipt.steps[0].artifacts['artifact.txt'] != expected {
				return error('native build receipt failed independent artifact check')
			}
		}
	}
	os.write_file(state + '/receipt.json', json2.encode(Receipt{
		arch:            arch
		kernel_sha256:   digest(state + '/kernel/bin/vinix')!
		fixture_sha256:  digest(init)!
		tools:           hashes
		command:         launch.command
		native_receipts: receipts
		passed:          result == 0
	}, prettify: true))!
	return result
}

fn main() {
	exit(run() or {
		eprintln(err)
		1
	})
}
