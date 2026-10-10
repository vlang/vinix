// SPDX-License-Identifier: GPL-2.0-only
module main

import os
import tarlink

fn main() { exit(tarlink.run(os.args[1..])) }
