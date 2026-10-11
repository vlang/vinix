// SPDX-License-Identifier: GPL-2.0-or-later
import verifiedhost
import os

fn main() { exit(verifiedhost.cli('root-runtime', os.args[1..])) }
