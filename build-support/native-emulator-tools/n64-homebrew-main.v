// SPDX-License-Identifier: GPL-2.0-or-later
module main
import emulatorbuild
import os
fn main() { exit(emulatorbuild.command("n64-homebrew", os.args[1..])) }
