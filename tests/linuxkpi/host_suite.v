// SPDX-License-Identifier: GPL-2.0-or-later
module main
import hostfixturebuild
import hosttest
import os

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--arch', true, ['arm64', 'amd64']}, hosttest.Option{'--native', false, []string{}}], 1,
		'Usage: host_suite.v WORK --arch arm64|amd64 [--native]', 'Compile independent V LinuxKPI host tests against the production objects.') or { eprintln(err); exit(2) }
	arch := args.options['--arch'] or { eprintln('--arch is required'); exit(2) }
	work := hosttest.module_resolve(args.positional[0]) or { eprintln(err); exit(1) }
	hostfixturebuild.build_suite(work, arch, '--native' !in args.options, os.environ(), '') or { eprintln(err); exit(1) }
}
