// SPDX-License-Identifier: GPL-2.0-or-later
module main
import nativepolicy
import os
fn main() { exit(nativepolicy.command(os.args[1..], "cpu")) }
