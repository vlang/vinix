// SPDX-License-Identifier: GPL-2.0-or-later
import minecraftnative
import os

fn main() { exit(minecraftnative.login_cli(os.args[1..])) }
