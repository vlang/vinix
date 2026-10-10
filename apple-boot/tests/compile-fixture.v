// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import os

fn host_arch() string {
	$if arm64 {
		return 'arm64'
	} $else {
		return 'amd64'
	}
}

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--arch', true, [
		'arm64',
		'amd64',
	]}],
		2, 'Usage: compile-fixture converter|boot|helpers OUTPUT [--arch arm64|amd64]',
		'Generate independent Apple boot host fixtures from maintained V modules.') or {
		eprintln(err)
		exit(2)
	}
	name := match args.positional[0] {
		'converter' { 'convertercore' }
		'boot' { 'bootfixture' }
		'helpers' { 'helperfixture' }
		else {
			eprintln('fixture must be converter, boot or helpers')
			exit(2)
		}
	}
	arch := args.options['--arch'] or { host_arch() }
	output := hosttest.module_resolve(args.positional[1]) or {
		eprintln(err)
		exit(1)
	}
	hosttest.generate_module(hosttest.root() + '/apple-boot/tests/' + name, output, arch, ['nofloat']) or {
		eprintln(err)
		exit(1)
	}
}
