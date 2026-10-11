// SPDX-License-Identifier: MIT
module main
import emulatorbuild
import os
fn main() { exit(emulatorbuild.command('n64', os.args[1..])) }
