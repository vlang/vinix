// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ansreads
import os

fn main() { exit(ansreads.run(os.args[1..])) }
