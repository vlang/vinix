// SPDX-License-Identifier: GPL-2.0-or-later
module main
import emulatorhost
import os
fn main() { exit(emulatorhost.run_command('ps2', os.args[1..])) }
