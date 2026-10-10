// SPDX-License-Identifier: GPL-2.0-only
module main

import os
import policyhost

fn main() { exit(policyhost.command(os.args[1..], 'mounted')) }
