// SPDX-License-Identifier: GPL-2.0-only
module main

import hosttest
import nativepolicy
import os
import policyhost

fn main() {
	guard := policyhost.own_commands()
	defer { guard.close() }
	args := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{ name: '--host' }, hosttest.Option{ name: '--wifi-bundle' },
		hosttest.Option{ name: '--busybox-echo-test' },
	], 2, 'Usage: compile-init shell|full|desktop OUTPUT [--host] [--wifi-bundle] [--busybox-echo-test]',
		'Emit the standalone freestanding init translation unit.') or { eprintln(err.msg()); exit(2) }
	if args.positional[0] !in ['shell', 'full', 'desktop'] { eprintln('Unknown init policy'); exit(2) }
	output := hosttest.module_resolve(args.positional[1]) or { eprintln(err.msg()); exit(1) }
	nativepolicy.generate_init(args.positional[0], output, '--host' in args.options,
		'--busybox-echo-test' in args.options, '--wifi-bundle' in args.options) or {
		eprintln(err.msg()); exit(if err.msg() == 'Host test interrupted' { 130 } else { 1 })
	}
}
