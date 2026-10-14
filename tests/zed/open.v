// SPDX-License-Identifier: GPL-2.0-or-later
// Only the demo starts with a sample file; the shipped launcher has no default.
module main

import os

fn main() {
	os.execvp('/usr/bin/run-zed-app', ['/root/hello.v']) or {
		eprintln(err)
		exit(1)
	}
}
