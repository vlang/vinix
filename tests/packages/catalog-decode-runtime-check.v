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
	kind string = 'pinned-catalog-decoding'
	scenario string = 'packages-catalog-decode'
	artifacts []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn suite() hwhost.Suite {
	return hwhost.Suite{ name: 'package-catalog-decode', guest: 'tests/packages/catalog-decode-guest',
		module_paths: ['.', 'tools/accounts'], directories: ['tmp:1777'], programs: [
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_decode_test.v', path: 'usr/share/package-fixtures/catalog-decode' },
			hwhost.Program{ source: 'tools/packages/pkgcore/publisher_schema_test.v', path: 'usr/share/package-fixtures/publisher-schema' },
			hwhost.Program{ source: 'tools/packages/pkgcore/catalog_test.v', path: 'usr/share/package-fixtures/catalog' },
			hwhost.Program{ source: 'tools/packages/pkgcore/composition_test.v', path: 'usr/share/package-fixtures/composition' },
		], scenarios: [hwhost.Scenario{ name: 'packages-catalog-decode', arches: ['aarch64', 'x86_64'],
			about: 'bounded complete catalog locks, unchanged signed publication and composed offline maintenance',
			required: ['HWTEST START packages-catalog-decode',
				'CATALOG DECODE both architectures, independent owned complete records, exact writer bytes and full 4096 import bounds PASS',
				'CATALOG DECODE whitespace, escaped keys and legacy window protocol preserve writer bytes; source defaults cannot enter complete catalog locks PASS',
				'CATALOG DECODE every truncated prefix and schema/UTF8/number/late import and selector refusal cycles retire scratch PASS',
				'CATALOG DECODE exact 8 MiB accepted; metadata/import/architecture/source/selector/payload/argument/permission overflow refused PASS',
				'CATALOG DECODE full 1024 selectors retire tracked storage; 16384 payloads preserve complete fields and retire their single live owner PASS',
				'CATALOG DECODE invalid catalog preserves sources and existing/absent pack/composition destinations; restored complete and legacy locks publish unchanged canonical bytes PASS',
				'CATALOG PROCESS catalog-decode PASS',
				'CATALOG PROCESS publisher-schema PASS',
				'CATALOG PROCESS catalog PASS',
				'CATALOG PROCESS composition PASS',
				'HWTEST PASS packages-catalog-decode'], ending: .poweroff, timeout: 300 }]
	}
}

fn check() !int {
	args := os.args[1..]; options := hwhost.parse_options(args)!
	if options.help || options.list { return hwhost.run_suite(suite(), args, @FILE) }
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-catalog-decode-' + os.getpid().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	os.cp(options.kernel, work + '/kernel')!
	kernel := artifact('kernel', work + '/kernel')!
	status := hwhost.run_suite(suite(), [...args, '--kernel', work + '/kernel'], @FILE)
	if status == 0 && options.state_dir != '' {
		base := options.state_dir
		root := base + '/guest/root/usr/share/package-fixtures/'
		receipt := Receipt{ architecture: options.arch, completed_at: time.now().unix(), artifacts: [kernel,
			artifact('guest-init', base + '/guest/init')!, artifact('catalog-decode', root + 'catalog-decode')!,
			artifact('publisher-schema', root + 'publisher-schema')!, artifact('catalog', root + 'catalog')!, artifact('composition', root + 'composition')!,
			artifact('serial-log', base + '/packages-catalog-decode/serial.log')!] }
		os.write_file(base + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() { code := check() or { eprintln(err); exit(1) }; exit(code) }
