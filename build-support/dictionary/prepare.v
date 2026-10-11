// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main
import dictionarycore
import os
fn main() { exit(dictionarycore.cli(os.args[1..], os.real_path(@DIR + '/../..'))) }
