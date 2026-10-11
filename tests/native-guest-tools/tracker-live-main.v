// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import os

fn main() { exit(guesthost.policy_guest_command(os.args[1..], 'tracker-live')) }
