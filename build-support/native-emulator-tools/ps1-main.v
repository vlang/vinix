// SPDX-License-Identifier: GPL-2.0-or-later
module main
import emulatorbuild
import os
fn main() { exit(emulatorbuild.command("ps1", os.args[1..])) }
