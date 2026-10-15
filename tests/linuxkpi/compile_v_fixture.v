// SPDX-License-Identifier: GPL-2.0-or-later
// Emit an independent native LinuxKPI fixture from its maintained V module.
module main

import hosttest
import os

#include <stdlib.h>
#include <stdio.h>
fn C.mkdtemp(&char) &char
fn C.rename(&char, &char) int

const fixture_modules = ['cachefixture', 'i915policyfixture', 'pciconfigfixture',
	'runtimefixture', 'taskfixture', 'timefixture', 'timerfixture', 'syncfixture',
	'wwfixture', 'iofixture', 'seqfixture', 'srcufixture', 'workerfixture',
	'workfixture', 'usleepfixture', 'waitbitfixture', 'printkfixture', 'smpfixture',
	'workirqfixture', 'rcufixture', 'rcufreefixture', 'irqworkfixture', 'dmafencefixture', 'fencecontainerfixture', 'resvfixture', 'swfencefixture', 'cpubugfixture', 'migrationfixture', 'tscfixture', 'aggregatefixture']

fn generate_fixture(name string, output string, arch string, host bool) ! {
	// Keep the replacement on the destination filesystem. A failed compiler,
	// metadata rewrite or rename must leave the previous artifact intact.
	mut pattern := (output.all_before_last('/') + '/.vinix-fixture-XXXXXX\x00').bytes()
	work := unsafe {
		pointer := C.mkdtemp(&char(pattern.data))
		if pointer == nil {
			return error('Cannot create private fixture output directory')
		}
		pointer.vstring().clone()
	}
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	staged := work + '/fixture.c'
	mut defines := ['nofloat']
	if host { defines << 'linuxkpi_host_test' }
	source := hosttest.root() + '/kernel/linuxkpi/' + name
	result := hosttest.generate_module_capture(source, staged, arch, defines)!
	print(result.stdout)
	eprint(result.stderr)
	// os.rename treats a directory destination as a request to move into it.
	// The primitive rename keeps the requested artifact path exact.
	if C.rename(staged.str, output.str) != 0 {
		return error('Cannot publish generated fixture: ' + output)
	}
}

fn main() {
	args := hosttest.parse_arguments_choices(os.args[1..], [
		hosttest.Option{'--arch', true, ['amd64', 'arm64']},
		hosttest.Option{'--host', false, []string{}},
	], 2, [fixture_modules, []string{}],
		'Usage: compile_v_fixture.v MODULE OUTPUT [--arch amd64|arm64] [--host]',
		'Emit an independent native LinuxKPI fixture from its maintained V module.') or {
		eprintln(err.msg())
		exit(2)
	}
	output := hosttest.module_resolve(args.positional[1]) or {
		eprintln(err.msg())
		exit(1)
	}
	generate_fixture(args.positional[0], output, args.options['--arch'] or { 'amd64' },
		'--host' in args.options) or {
		eprintln(err.msg())
		exit(1)
	}
}
