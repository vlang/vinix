// SPDX-License-Identifier: GPL-2.0-or-later
module main

import compathost
import fixturehost
import hosttest
import os
import policyhost

fn check(ok bool, message string) ! { if !ok { return error(message) } }

fn owners(prefix string) ![]string {
	mut names := os.ls('/tmp')!.filter(it.starts_with(prefix))
	names.sort()
	return names
}

fn qualify(binary string) ! {
	declarations := '#if __has_include(<stdio.h>)\n#include <stdio.h>\n#else\nint fprintf(void * stream, char * format, ...);\nextern void * stderr;\n#endif\n'
	check(compathost.diagnostic_declarations()! == declarations, 'Production diagnostic imports differ')!
	check(compathost.office_exports('[Ordinal/Name Pointer] Table\n [ 2] Zeta\n [0] Alpha\n[ 3] +base[ 9] ab12 Beta\nThe Function Table\n[4] Ignore\n')! == ['Alpha', 'Beta', 'Zeta'], 'PE export table boundaries differ')!
	check(compathost.shared_libraries('  (NEEDED) Shared library: [libc.so]\nOther [ignore]\n (NEEDED) Shared library: [libwine.so]\n') == ['libc.so', 'libwine.so'], 'ELF dependency names differ')!
	work := hosttest.work_dir('', 'vinix-compat-qualification-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	// Byte/stat copying follows links and retains executable mode and timestamps.
	os.write_file(work + '/source', 'native runtime\x00\xff')!
	os.chmod(work + '/source', 0o751)!
	os.symlink('source', work + '/link')!
	hosttest.module_copy_file_preserving_stat(work + '/link', work + '/copy')!
	check(os.read_bytes(work + '/source')! == os.read_bytes(work + '/copy')!, 'Runtime copy bytes differ')!
	original := os.stat(work + '/source')!
	copied := os.stat(work + '/copy')!
	check(original.mode & 0o7777 == copied.mode & 0o7777 && original.mtime == copied.mtime && !os.is_link(work + '/copy'), 'Runtime copy metadata differs')!
	mut env := policyhost.environment()
	env['CC'] = 'false'
	env['CC_AARCH64'] = 'false'
	env['CC_AMD64'] = 'false'
	for family in ['robust-compile', 'robust-test', 'robust-guest', 'office-compile', 'office-test', 'office-guest', 'net-random', 'n64-bridge'] {
		help := fixturehost.capture_both_preferred([binary, family, '--help'], env, policyhost.caller_arch())!
		check(help.status == 0 && help.stdout.contains('Usage:'), family + ' help failed')!
		bad := fixturehost.capture_both_preferred([binary, family, '--unknown'], env, policyhost.caller_arch())!
		check(bad.status == 2, family + ' unknown option accepted')!
	}
	before := owners('vinix-net-random-')!
	for _ in 0 .. 12 {
		failed := fixturehost.capture_both_preferred([binary, 'net-random'], env, policyhost.caller_arch())!
		check(failed.status == 1 && owners('vinix-net-random-')! == before, 'Failed random build retained a private owner')!
	}
	// A retained directory is never overwritten, including on compilation failure.
	os.mkdir(work + '/keep')!
	os.write_file(work + '/keep/sentinel', 'preserve')!
	for family, option in {'robust-test': '--output-dir', 'office-test': '--state-dir', 'net-random': '--state-dir'} {
		result := fixturehost.capture_both_preferred([binary, family, option, work + '/keep'], env, policyhost.caller_arch())!
		check(result.status == 1 && os.read_file(work + '/keep/sentinel')! == 'preserve', 'Existing workspace overwritten')!
	}
	println('Compatibility declarations, ABI parsers, runtime stat copy, CLI and failed-build cleanup PASS')
}

fn main() {
	if os.args.len != 2 { eprintln('Usage: check-tooling.v CONTROLLER'); exit(2) }
	qualify(os.args[1]) or { eprintln(err.msg()); exit(1) }
}
