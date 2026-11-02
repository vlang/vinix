// SPDX-License-Identifier: GPL-2.0-or-later
// Linux ARM64 runtime checks, including QEMU user execution on x86_64.
module main

import os
import linuxcheck

fn main() {
	if linuxcheck.maybe_probe_desktop_child() or {
		eprintln(err)
		exit(1)
	} {
		return
	}
	if linuxcheck.maybe_tls_child() or {
		eprintln(err)
		exit(1)
	} {
		return
	}
	if os.args.len != 3 {
		eprintln('usage: linux-checks url-request|data-http|storekit-purchase|netdb-scope|reachability|network-path|gles|cxx|cxx-gles|image-initializers|build-run-ios|build-run-ios-gles|build-run-ios-cxx|build-run-ios-cxx-gles|probe-no-ads FRESH_EXTERNAL_DIRECTORY')
		exit(2)
	}
	linuxcheck.run(os.getwd(), os.args[1], os.args[2]) or {
		eprintln('Linux iOS checks: ${err}')
		exit(1)
	}
}
