// SPDX-License-Identifier: MIT
module main
import emulatorbuild
import os
fn main() { exit(emulatorbuild.command('ps2', os.args[1..])) }
