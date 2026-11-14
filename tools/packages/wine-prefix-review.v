// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tools.packages.wineadapter

fn run() ! {
	if os.args.len !in [4, 5] || (os.args.len == 5 && os.args[4] != '--idle') { return error('usage: wine-prefix-review PACKAGE_STORE PRIVATE_DATA NEW_BUILTINS [--idle]; run as prefix owner; --idle may create coordination files') }
	if os.args.len == 5 {
		mut capture := wineadapter.capture_idle_binding_review(os.args[2], os.args[3], os.args[1])!
		defer { capture.close() }
		capture.recheck()!
		println(json2.encode(capture.review))
		return
	}
	mut review := wineadapter.review_prefix_bindings(os.args[2], os.args[3], os.args[1])!
	defer { review.close() }
	println(json2.encode(review))
}

fn main() { run() or { eprintln(err); exit(1) } }
