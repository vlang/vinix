// SPDX-License-Identifier: GPL-2.0-or-later
// An actual executable records every legacy acquisition in the host fixture.
module main

import os

fn main() {
	mut log := os.open_append(os.getenv('VINIX_SETUP_TOOL_LOG')) or { panic(err) }
	defer { log.close() }
	log.writeln(os.args[1..].join('|')) or { panic(err) }
}
