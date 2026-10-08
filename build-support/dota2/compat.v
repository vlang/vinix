// SPDX-License-Identifier: GPL-2.0-or-later
// Generate a Dota compatibility module's C build artifact from native V.
module main

import hosttest
import os

fn main() {
	args := hosttest.parse_arguments_choices(os.args[1..], [
		hosttest.Option{'--arch', true, ['amd64', 'arm64']},
		hosttest.Option{'--bare', false, []string{}},
	], 2, [['early', 'mmap32', 'mmap-probe'], []string{}], 'Usage: compat.v {early|mmap32|mmap-probe} OUTPUT [--arch amd64|arm64] [--bare]',
		"Generate a Dota compatibility module's C build artifact from native V.") or {
		eprintln(err)
		exit(2)
	}
	name := args.positional[0]
	if name !in ['early', 'mmap32', 'mmap-probe'] {
		eprintln('Unknown compatibility module: ' + name)
		exit(2)
	}
	source := hosttest.root() + if name == 'early' {
		'/build-support/dota2/earlycore'
	} else if name == 'mmap32' {
		'/build-support/dota2/mmapcore'
	} else {
		'/tests/dota2/mmapprobe'
	}
	output := hosttest.module_resolve(args.positional[1]) or {
		eprintln(err)
		exit(1)
	}
	arch := if '--arch' in args.options { args.options['--arch'] } else { 'amd64' }
	hosttest.generate_module(source, output, arch, ['nofloat']) or {
		eprintln(err)
		exit(1)
	}
	if '--bare' in args.options {
		hosttest.rewrite_generated_text(args.positional[1], '#include <inttypes.h>\n', '') or {
			eprintln(err)
			exit(1)
		}
	}
}
