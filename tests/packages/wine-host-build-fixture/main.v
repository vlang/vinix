// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tests.packages.winehostfixture

fn main() {
	if winehostfixture.token() != 42 { panic('hidden host fixture import differs') }
	println('WINE HOST BUILD FIXTURE PASS')
}
