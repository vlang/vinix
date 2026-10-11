// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import hosttest
import os
import policyhost

fn qualify(binary string, profile string) ! {
	controls := '/tmp/vinix-security-controls-' + profile
	os.mkdir(controls)!
	for path, revision in {
		'tests/security-mac/cli_test.c':         'aaa2e6d5^'
		'tests/application-sandbox/host.c':      '223b549e^'
		'tests/security-audit/collector_test.c': '9a706788^'
	} {
		os.mkdir_all(os.dir(controls + '/' + path))!
		os.write_file(controls + '/' + path, policyhost.capture(['git', '-C', hosttest.root(),
			'show', revision + ':' + path])!)!
	}
	for directory in ['tools/security-mac', 'tools/sandbox', 'tools/security-audit'] {
		for source in os.walk_ext(hosttest.root() + '/' + directory, '.h') {
			target := controls + '/' + source[hosttest.root().len + 1..]
			os.mkdir_all(os.dir(target))!
			os.cp(source, target)!
		}
	}
	mut env := policyhost.environment()
	env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	for tool in ['mac', 'sandbox', 'audit'] {
		family := tool + '-host'
		control := controls + '/' + match tool {
			'mac' { 'tests/security-mac/cli_test.c' }
			'sandbox' { 'tests/application-sandbox/host.c' }
			else { 'tests/security-audit/collector_test.c' }
		}
		mut streams := [][]string{}
		for variant in ['v', 'c'] {
			work := '/tmp/vinix-security-final-' + tool + '-' + profile + '-' + variant
			mut args := [binary, family, '--keep-dir', work]
			if variant == 'c' { args << ['--source', control] }
			result := fixturehost.capture_both_preferred(args, env, policyhost.caller_arch())!
			os.write_file(work + '.log', result.stdout + result.stderr)!
			if result.status != 0 { return error(work + ' failed: ' + result.stderr) }
			streams << [os.read_file(work + '/host.log')!, os.read_file(work + '/failures.log')!]
			receipt := hosttest.decode_json(os.read_file(work + '/inputs.json')!)!.as_map()
			inputs := (receipt['inputs'] or { return error('Missing inputs') }).as_map()
			for path, item in inputs {
				fields := item.as_map()
				if hosttest.sha(path)! != (fields['sha256'] or { return error('Missing hash') }).str() {
					return error('Stale input ' + path)
				}
			}
		}
		if streams[0] != streams[1] {
			return error(tool + ' original C/V stdout or stderr differs')
		}
		println(tool + ' original C/V sanitizer differential and receipt hashes PASS (' + profile + ')')
	}
}

fn main() {
	if os.args.len != 3 {
		eprintln('Usage: check-security.v CONTROLLER PROFILE')
		exit(2)
	}
	qualify(os.args[1], os.args[2]) or {
		eprintln(err.msg())
		exit(1)
	}
}
