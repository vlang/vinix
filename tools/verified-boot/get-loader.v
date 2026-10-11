// SPDX-License-Identifier: GPL-2.0-or-later
import bundlehost
import os

fn main() { exit(bundlehost.cli('loader', os.args[1..])) }
