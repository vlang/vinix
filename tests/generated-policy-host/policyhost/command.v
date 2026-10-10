// SPDX-License-Identifier: GPL-2.0-only
module policyhost

import hosttest
import json2

// Each maintained command owns its fixture in this process. The diagnostic
// JSON query remains available, with native file and process operations.
pub fn command(arguments []string, family string) int {
	if family == 'assembly' {
		if arguments in [['--help'], ['-h']] {
			println('Usage: check-assembly')
			return 0
		}
		assembly_main(hosttest.root()) or {
			eprintln(err.msg())
			return 1
		}
		return 0
	}
	options := if family == 'mounted' {
		[hosttest.Option{'--arch', true, ['aarch64', 'amd64']}]
	} else {
		[]hosttest.Option{}
	}
	parsed := hosttest.parse_arguments(arguments, options, 1,
		'Generated production policy fixture', 'Usage: ' +
			if family == 'syscall' {
				'run-host BLOB.c'
			} else if family == 'mounted' {
				'check-generated --arch=aarch64|amd64 BLOB.c'
			} else {
				'check-generated BLOB.c'
			}) or {
		eprintln(err.msg())
		return 2
	}
	if family == 'mounted' && '--arch' !in parsed.options {
		eprintln('--arch is required')
		return 2
	}
	dispatch({
		'operation': json2.Any('main')
		'family':    json2.Any(family)
		'path':      json2.Any(parsed.positional[0].bytes().hex())
		'arch':      json2.Any(parsed.options['--arch'])
	}) or {
		eprintln(err.msg())
		return 1
	}
	return 0
}
