// SPDX-License-Identifier: GPL-2.0-only
module main

import guesthost
import os

fn main() { exit(guesthost.init_fixture_command(os.args[1..])) }
