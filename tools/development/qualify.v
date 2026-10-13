// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import qualcore

fn main() {
	if os.base(os.executable()) == 'api' && os.getenv('GATEWAY_INTERFACE') == 'CGI/1.1' {
		qualcore.http_cgi() or { eprintln('CGI request failed'); exit(1) }
		return
	}
	mut args := os.args[1..].clone()
	if args.len == 0 || args == ['--help'] {
		println('Usage: vinix-qualify [--require-vinix] FRESH-OUTPUT [c,cpp,v,node,typescript,rust,cargo,go,java,make,cmake,ninja,npm,gdb,sqlite,http]')
		println('VINIX_QUALIFY_TIMEOUT_SECONDS selects each command deadline (1..86400, default 120)')
		println('VINIX_QUALIFY_JIT=1 requests Java JIT execution through an administrator-approved runtime mount')
		return
	}
	require := args[0] == '--require-vinix'
	if require { args.delete(0) }
	if args.len !in [1, 2] {
		eprintln('invalid arguments')
		exit(2)
	}
	profiles := if args.len == 1 { qualcore.catalog } else { args[1].split(',') }
	report := qualcore.qualify(profiles, args[0], require) or {
		eprintln(err)
		exit(1)
	}
	if !report.all_selected_passed { exit(1) }
}
