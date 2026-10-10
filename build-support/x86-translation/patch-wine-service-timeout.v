// SPDX-License-Identifier: GPL-2.0-or-later
module main

import winepatch
import os

fn main() { exit(winepatch.run('wine-service-timeout', os.args[1..])) }
