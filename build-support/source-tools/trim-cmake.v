// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import sourcefixture

fn main() {
	if os.args.len != 2 { eprintln('Usage: trim-cmake CMakeLists.txt'); exit(2) }
	text := sourcefixture.read(os.args[1]) or { eprintln(err);exit(1) }
	os.write_file(os.args[1],sourcefixture.trim_cmake(text)) or { eprintln(err);exit(1) }
}
