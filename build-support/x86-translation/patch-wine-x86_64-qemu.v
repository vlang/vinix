// SPDX-License-Identifier: GPL-2.0-or-later
module main

import winepatch
import os

fn main() { exit(winepatch.run('wine-x86_64-qemu', os.args[1..])) }
