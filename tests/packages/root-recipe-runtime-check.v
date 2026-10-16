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
	kind string = 'prepared-root-recipe-decoding'
	scenario string = 'packages-root-recipe'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-root-recipe', guest: 'tests/packages/root-recipe-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/root_recipe_decode_test.v', path: 'usr/share/package-fixtures/root-recipe-decode' },
			hwhost.Program{ source: 'tools/packages/pkgcore/publisher_schema_test.v', path: 'usr/share/package-fixtures/publisher-schema' },
			hwhost.Program{ source: 'tools/packages/pkgcore/import_test.v', path: 'usr/share/package-fixtures/import' },
		], scenarios: [hwhost.Scenario{ name: 'packages-root-recipe', arches: ['aarch64', 'x86_64'],
			about: 'bounded prepared-root templates, selector admission and unchanged publisher/import behavior',
			required: ['HWTEST START packages-root-recipe',
				'ROOT RECIPE both architectures, independent owned templates, exact canonical bytes and full 1024 selector bounds PASS',
				'ROOT RECIPE omitted format and nested manifest defaults, full payload integers and reordered fields preserve admission and retire scratch PASS',
				'ROOT RECIPE every truncated prefix and schema/UTF8/number/selector/overlap refusal cycles retire scratch PASS',
				'ROOT RECIPE exact 8 MiB and 1024-byte selectors accepted; metadata, selector and nested manifest overflow refused PASS',
				'ROOT RECIPE full 16384 payload template inventories preserve fields and retire their single live owner PASS',
				'ROOT RECIPE 1000 borrowed selector validation cycles preserve equal/parent/child/Unicode/component boundaries and retire scratch PASS',
				'ROOT RECIPE invalid import preserves sources and existing/absent workspace; restored template captures payload and unchanged canonical publication PASS',
				'ROOT PROCESS root-recipe-decode PASS',
				'ROOT PROCESS publisher-schema PASS',
				'ROOT PROCESS import PASS',
				'HWTEST PASS packages-root-recipe'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-root-recipe-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('root-recipe-decode', root + 'root-recipe-decode')!,
			artifact('publisher-schema', root + 'publisher-schema')!, artifact('import', root + 'import')!,
			artifact('serial-log', base + '/packages-root-recipe/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
