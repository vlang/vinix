// SPDX-License-Identifier: GPL-2.0-or-later
module main
import guesthost
import os
fn main() { exit(guesthost.rsp_budget_command(os.args[1..])) }
