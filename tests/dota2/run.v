// SPDX-License-Identifier: GPL-2.0-or-later
import nativehost
import os

fn main() { exit(nativehost.command('game', os.args[1..])) }
