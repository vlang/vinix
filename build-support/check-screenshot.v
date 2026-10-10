// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import screenshotcore

fn main() { exit(screenshotcore.run(os.args[1..])) }
