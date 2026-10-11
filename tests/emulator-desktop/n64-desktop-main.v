// SPDX-License-Identifier: GPL-2.0-or-later
module main
import emulatorhost
import os
fn main() { exit(emulatorhost.desktop_command('n64', os.args[1..])) }
