// SPDX-License-Identifier: GPL-2.0-or-later
import bundlehost
import os

fn main() { exit(bundlehost.cli('root', os.args[1..])) }
