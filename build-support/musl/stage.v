// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import muslnative
import os

fn main() {
	root := hosttest.root()
	exit(muslnative.cli(os.args[1..], root, root + '/build-support/musl', false))
}
