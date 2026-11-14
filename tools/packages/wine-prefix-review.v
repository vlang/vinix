// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tools.packages.wineadapter

fn run() ! {
	if os.args.len != 4 { return error('usage: wine-prefix-review PACKAGE_STORE PRIVATE_DATA NEW_BUILTINS; run as prefix owner') }
	mut review := wineadapter.review_prefix_bindings(os.args[2], os.args[3], os.args[1])!
	defer { review.close() }
	println(json2.encode(review))
}

fn main() { run() or { eprintln(err); exit(1) } }
