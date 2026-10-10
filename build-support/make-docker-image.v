// SPDX-License-Identifier: GPL-2.0-only
module main

import dockerimage
import os

fn main() { exit(dockerimage.run(os.args[1..])) }
