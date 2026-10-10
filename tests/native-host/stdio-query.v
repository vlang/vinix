// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os

struct Request {
	mode string
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or { panic(err) }
		os.chmod(os.args[2], 0o700) or { panic(err) }
		return
	}
	request := json2.decode[Request](os.get_raw_line()) or { panic(err) }
	if request.mode == 'eof' {
		return
	}
	println('{"callback":"probe","arguments":{}}')
	// Echo the actual transport response, including a pending callback error.
	println(os.get_raw_line())
}
