// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import glvm
import os

fn main() { exit(glvm.command(os.args[1..])) }
